//! The microphone: opened when a session starts (or, with pre-roll, when the
//! trigger goes down), closed when it ends, never left running between
//! sessions.
//!
//! A cpal stream is not `Send`, so one thread owns it and takes commands.
//! Samples land 16 kHz mono in a buffer the daemon can snapshot for live
//! drafts; levels go out about 50 times a second for the HUD.
//!
//! The device and its format are looked up once and reused: enumerating
//! ALSA devices is most of what opening costs, and every millisecond here is
//! the start of the first word.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Instant;

use anyhow::{Context, anyhow};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use crossbeam_channel::{Receiver, Sender};
use talkify_core::level::normalized_level;
use talkify_core::resample::{Resampler, TARGET_RATE};

use super::Msg;

/// 20 ms of 16 kHz audio: one level reading.
const LEVEL_WINDOW: usize = TARGET_RATE as usize / 50;

pub enum AudioCmd {
  /// Open the microphone ahead of a session that may not happen (the chord
  /// guard is still deciding). Buffers, but reports nothing as started.
  Prepare(u64),
  /// The session is real: report the microphone started, opening it first
  /// unless it was prepared for this id.
  Start(u64),
  Stop(u64),
  Cancel(u64),
  /// While paused the stream stays open but nothing is kept.
  Pause(bool),
}

#[derive(Clone)]
pub struct Audio {
  commands: Sender<AudioCmd>,
  recording: Arc<Mutex<Vec<f32>>>,
}

impl Audio {
  pub fn spawn(events: Sender<Msg>) -> Self {
    let (commands, rx) = crossbeam_channel::unbounded();
    let recording = Arc::new(Mutex::new(Vec::new()));
    let buffer = recording.clone();
    std::thread::Builder::new()
      .name("microphone".into())
      .spawn(move || Microphone::new(buffer, events).run(rx))
      .expect("spawn microphone thread");
    Self {
      commands,
      recording,
    }
  }

  pub fn send(&self, command: AudioCmd) {
    let _ = self.commands.send(command);
  }

  /// A copy of everything recorded so far, for a live draft.
  pub fn snapshot(&self) -> Vec<f32> {
    self.recording.lock().unwrap().clone()
  }

  pub fn recorded_len(&self) -> usize {
    self.recording.lock().unwrap().len()
  }
}

struct Microphone {
  recording: Arc<Mutex<Vec<f32>>>,
  events: Sender<Msg>,
  paused: Arc<AtomicBool>,
  device: Option<(cpal::Device, cpal::StreamConfig)>,
  name: Arc<Mutex<String>>,
  /// The open stream and the id it was opened for.
  stream: Option<(u64, cpal::Stream)>,
}

impl Microphone {
  fn new(recording: Arc<Mutex<Vec<f32>>>, events: Sender<Msg>) -> Self {
    let name = Arc::new(Mutex::new("The microphone".to_string()));
    refresh_name(name.clone());
    Self {
      recording,
      events,
      paused: Arc::new(AtomicBool::new(false)),
      device: None,
      name,
      stream: None,
    }
  }

  fn run(mut self, commands: Receiver<AudioCmd>) {
    for command in commands {
      match command {
        AudioCmd::Prepare(id) => {
          if let Err(error) = self.open(id) {
            tracing::warn!("microphone pre-roll: {error:#}");
          }
        }
        AudioCmd::Start(id) => {
          let prepared = self.stream.as_ref().is_some_and(|(open, _)| *open == id);
          let opened = if prepared { Ok(()) } else { self.open(id) };
          match opened {
            Ok(()) => {
              let name = self.name.lock().unwrap().clone();
              let _ = self.events.send(Msg::MicStarted {
                id,
                at: Instant::now(),
                name,
              });
              // The default microphone can change between sessions.
              refresh_name(self.name.clone());
            }
            Err(error) => {
              tracing::error!("microphone: {error:#}");
              let _ = self.events.send(Msg::MicFailed {
                id,
                error: format!("{error:#}"),
              });
            }
          }
        }
        AudioCmd::Stop(id) => {
          self.close(id);
          let samples = std::mem::take(&mut *self.recording.lock().unwrap());
          let _ = self.events.send(Msg::AudioFinished { id, samples });
        }
        AudioCmd::Cancel(id) => {
          self.close(id);
          self.recording.lock().unwrap().clear();
        }
        AudioCmd::Pause(paused) => self.paused.store(paused, Ordering::Relaxed),
      }
    }
  }

  fn close(&mut self, id: u64) {
    if self.stream.as_ref().is_some_and(|(open, _)| *open == id) {
      self.stream = None;
    }
    self.paused.store(false, Ordering::Relaxed);
  }

  fn open(&mut self, id: u64) -> anyhow::Result<()> {
    self.stream = None;
    self.paused.store(false, Ordering::Relaxed);
    self.recording.lock().unwrap().clear();
    let started = Instant::now();
    let stream = match self.build(id) {
      Ok(stream) => stream,
      Err(error) if self.device.is_some() => {
        // The cached device may have gone (a headset unplugged): look again.
        tracing::debug!("cached microphone failed ({error:#}), looking again");
        self.device = None;
        self.build(id)?
      }
      Err(error) => return Err(error),
    };
    tracing::debug!("microphone open in {:?}", started.elapsed());
    self.stream = Some((id, stream));
    Ok(())
  }

  fn build(&mut self, id: u64) -> anyhow::Result<cpal::Stream> {
    if self.device.is_none() {
      let host = cpal::default_host();
      let device = host
        .default_input_device()
        .context("no default microphone")?;
      let config = preferred_config(&device)?;
      tracing::debug!("microphone config {config:?}");
      self.device = Some((device, config));
    }
    let (device, config) = self.device.as_ref().expect("looked up above");

    let mut resampler = Resampler::new(config.sample_rate, config.channels);
    let mut converted = Vec::with_capacity(4096);
    let mut pending_level = Vec::with_capacity(LEVEL_WINDOW);
    let recording = self.recording.clone();
    let paused = self.paused.clone();
    let events = self.events.clone();
    let error_events = self.events.clone();

    let stream = device
      .build_input_stream::<f32, _, _>(
        *config,
        move |data: &[f32], _| {
          converted.clear();
          resampler.process(data, &mut converted);
          let is_paused = paused.load(Ordering::Relaxed);
          if !is_paused {
            recording.lock().unwrap().extend_from_slice(&converted);
          }
          for chunk in converted.chunks(LEVEL_WINDOW) {
            pending_level.extend_from_slice(chunk);
            if pending_level.len() >= LEVEL_WINDOW {
              let level = if is_paused {
                0.0
              } else {
                normalized_level(&pending_level)
              };
              // Exact zeros are a muted microphone, not a quiet room: even a
              // silent room carries a noise floor.
              let signal = pending_level.iter().any(|sample| *sample != 0.0);
              pending_level.clear();
              let _ = events.send(Msg::Level {
                id,
                level,
                signal,
                at: Instant::now(),
              });
            }
          }
        },
        move |error| {
          tracing::warn!("microphone stream error: {error}");
          let _ = error_events.send(Msg::MicStreamError { id });
        },
        None,
      )
      .map_err(|error| anyhow!("{error}"))?;
    stream.play().map_err(|error| anyhow!("{error}"))?;
    Ok(stream)
  }
}

/// The default source's name as the user knows it ("INZONE H5 Mono"), for
/// telling them which microphone is silent. Looked up off the hot path.
fn refresh_name(name: Arc<Mutex<String>>) {
  std::thread::spawn(move || {
    let found = std::process::Command::new("wpctl")
      .args(["inspect", "@DEFAULT_AUDIO_SOURCE@"])
      .output()
      .ok()
      .and_then(|output| {
        String::from_utf8_lossy(&output.stdout)
          .lines()
          .find_map(|line| {
            let value = line.trim().trim_start_matches('*').trim();
            value
              .strip_prefix("node.description = ")
              .map(|name| name.trim_matches('"').to_string())
          })
      });
    if let Some(found) = found {
      *name.lock().unwrap() = found;
    }
  });
}

/// 16 kHz mono f32 when the device offers it (PipeWire always does), so no
/// resampling happens on this side; otherwise the device default.
fn preferred_config(device: &cpal::Device) -> anyhow::Result<cpal::StreamConfig> {
  let wanted = device
    .supported_input_configs()
    .ok()
    .and_then(|mut ranges| {
      ranges.find(|range| {
        range.sample_format() == cpal::SampleFormat::F32
          && range.channels() == 1
          && range.min_sample_rate() <= TARGET_RATE
          && range.max_sample_rate() >= TARGET_RATE
      })
    });
  if let Some(range) = wanted {
    return Ok(range.with_sample_rate(TARGET_RATE).config());
  }
  let fallback = device
    .default_input_config()
    .map_err(|error| anyhow!("{error}"))?;
  if fallback.sample_format() != cpal::SampleFormat::F32 {
    return Err(anyhow!("microphone does not offer float samples"));
  }
  Ok(fallback.config())
}
