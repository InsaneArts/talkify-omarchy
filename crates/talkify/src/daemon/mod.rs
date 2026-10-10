//! The daemon: one loop owns the session machine and the chord guard, and
//! everything impure (keyboard, microphone, engine, insertion, media,
//! socket) runs on its own thread and reports back as a `Msg`.
//!
//! Every session gets an id. Anything that comes back carrying an old id
//! (a microphone that opened after a cancel, a live draft that finished
//! after the final pass) is ignored, which settles the races without
//! locks.
//!
//! The loop lives here; what happens to the text after the final pass is in
//! `pipeline`, the socket's commands in `commands`, the files in `store`.

mod audio;
mod commands;
mod engine;
mod hyprland;
mod insert;
mod keyboard;
mod media;
mod models;
mod pipeline;
mod server;
mod sounds;
mod store;

use std::collections::VecDeque;
use std::time::{Duration, Instant};

use anyhow::Context;
use crossbeam_channel::{Receiver, RecvTimeoutError, Sender, TrySendError};
use talkify_core::apps::{self, Rules};
use talkify_core::chord::{ChordGuard, GuardOutput, KeyInput};
use talkify_core::config::Config;
use talkify_core::history::History;
use talkify_core::insights::UsageDocument;
use talkify_core::level::MicWatchdog;
use talkify_core::live::LiveCommitter;
use talkify_core::protocol::{Command, EngineStatus, Event, HudPhase, TextMark, TriggerSource};
use talkify_core::session::{Action, Effect, SessionMachine, State};

use audio::{Audio, AudioCmd};
use engine::{Engine, Job, Pass};
use hyprland::Target;
use media::Media;
use sounds::Cue;

use crate::paths;

/// How often a live draft may run while speaking.
const LIVE_EVERY: Duration = Duration::from_millis(600);
/// A live draft waits for at least this much new audio.
const LIVE_MIN_NEW_SAMPLES: usize = 16_000 / 2;
/// A message on the HUD stays this long.
const MESSAGE_FOR: Duration = Duration::from_millis(1800);
/// A microphone delivering nothing but exact zeros for this long is muted.
const SILENT_MICROPHONE_AFTER: Duration = Duration::from_millis(1200);
/// While recording the loop wakes at least this often for the watchdog and
/// live drafts.
const RECORDING_TICK: Duration = Duration::from_millis(100);
/// How many events a new watcher is greeted with: the daemon's whole state.
/// `talkify status` prints exactly these.
pub const GREETING_EVENTS: usize = 7;

pub enum Msg {
  Key {
    code: u16,
    down: bool,
    at: Instant,
  },
  Command(Command, Sender<String>),
  Watch(Sender<String>),
  MicStarted {
    id: u64,
    at: Instant,
    name: String,
  },
  MicFailed {
    id: u64,
    error: String,
  },
  MicStreamError {
    id: u64,
  },
  Level {
    id: u64,
    level: f32,
    /// False when the window was nothing but exact zeros.
    signal: bool,
    at: Instant,
  },
  AudioFinished {
    id: u64,
    samples: Vec<f32>,
  },
  Transcribed {
    id: u64,
    is_final: bool,
    offset: usize,
    pass: Pass,
  },
  EngineStatus {
    status: EngineStatus,
    detail: String,
    progress: f32,
  },
  Inserted {
    id: u64,
    outcome: insert::Outcome,
  },
  /// Live insertion's worker finished the session's last chunk.
  LiveDone {
    id: u64,
    outcome: insert::Outcome,
  },
  /// Paste again or Retry landed.
  Replayed {
    text: String,
    outcome: insert::Outcome,
  },
}

/// A session that inserts while the user speaks.
struct Live {
  committer: LiveCommitter,
  inserter: insert::LiveInserter,
}

/// A finished session on its way to the window: what was heard, what will
/// land, and what the result should say about it.
struct Landing {
  raw: String,
  text: String,
  send: bool,
  audio: Option<Vec<f32>>,
}

pub fn run() -> anyhow::Result<()> {
  let listener = server::bind()?;
  remove_socket_on_exit()?;
  let config = store::load_config();
  let (tx, rx) = crossbeam_channel::unbounded();

  let trigger_source = keyboard::start(tx.clone());
  let model = models::find(&config.engine.model).unwrap_or(&models::PARAKEET_V3_INT8);
  let engine = Engine::spawn(model, tx.clone());
  let audio = Audio::spawn(tx.clone());
  {
    let tx = tx.clone();
    std::thread::Builder::new()
      .name("socket".into())
      .spawn(move || server::serve(listener, tx))?;
  }
  tracing::info!(
    "listening on {} (trigger: {trigger_source:?})",
    paths::socket().display()
  );

  let mut daemon = Daemon {
    guard: ChordGuard::new(guard_for(
      &config.trigger.key,
      config.trigger.chord_guard_ms,
    )),
    trigger_code: keyboard::key_code(&config.trigger.key),
    history: History::new(config.history.size as usize),
    vocab: store::VocabFile::load(),
    usage: store::load_usage(),
    config,
    machine: SessionMachine::default(),
    trigger_source,
    audio,
    engine,
    media: Media::spawn(),
    engine_event: Event::Engine {
      status: EngineStatus::Loading,
      detail: String::new(),
      progress: 0.0,
    },
    hud_event: hidden(),
    watchers: Vec::new(),
    tx,
    session_id: 0,
    prepared: None,
    target: None,
    rules: None,
    draft: String::new(),
    committed: String::new(),
    marks: Vec::new(),
    segment_start: 0,
    live: None,
    landing: None,
    session_audio: None,
    latched: false,
    paused: false,
    watchdog: None,
    mic_alive: true,
    heard_signal: false,
    warned_silent: false,
    mic_opened_at: None,
    mic_name: "The microphone".into(),
    no_speech_deadline: None,
    message_until: None,
    live_in_flight: false,
    last_live_at: Instant::now(),
    last_live_len: 0,
    played_begin: false,
    speaking_seconds: 0.0,
    replay: None,
  };
  daemon.run(rx);
  Ok(())
}

/// Mouse buttons are never chorded; other keys wait the configured guard.
fn guard_for(key: &str, guard_ms: u64) -> Duration {
  if keyboard::is_button(key) {
    Duration::ZERO
  } else {
    Duration::from_millis(guard_ms)
  }
}

/// systemd stops the daemon with SIGTERM; leave no socket behind for the
/// next start to trip over.
fn remove_socket_on_exit() -> anyhow::Result<()> {
  use signal_hook::consts::{SIGINT, SIGTERM};
  let mut signals = signal_hook::iterator::Signals::new([SIGTERM, SIGINT])?;
  std::thread::Builder::new()
    .name("signals".into())
    .spawn(move || {
      if signals.forever().next().is_some() {
        let _ = std::fs::remove_file(paths::socket());
        std::process::exit(0);
      }
    })?;
  Ok(())
}

pub fn transcribe_file(path: &str) -> anyhow::Result<()> {
  let mut reader = hound::WavReader::open(path).with_context(|| format!("open {path}"))?;
  let spec = reader.spec();
  let interleaved: Vec<f32> = match spec.sample_format {
    hound::SampleFormat::Float => reader.samples::<f32>().collect::<Result<_, _>>()?,
    hound::SampleFormat::Int => {
      let scale = (1_i64 << (spec.bits_per_sample - 1)) as f32;
      reader
        .samples::<i32>()
        .map(|s| s.map(|s| s as f32 / scale))
        .collect::<Result<_, _>>()?
    }
  };
  let mut samples = Vec::new();
  talkify_core::resample::Resampler::new(spec.sample_rate, spec.channels)
    .process(&interleaved, &mut samples);
  let model = models::find(&store::load_config().engine.model).unwrap_or(&models::PARAKEET_V3_INT8);
  if !model.is_complete() {
    anyhow::bail!("the Speech Model is not downloaded yet (talkify load-model)");
  }
  let started = Instant::now();
  let text = engine::transcribe_once(model, &samples)?;
  eprintln!(
    "{:.1} s of audio in {:?}",
    samples.len() as f32 / 16_000.0,
    started.elapsed()
  );
  println!("{text}");
  Ok(())
}

fn hidden() -> Event {
  hud_event(HudPhase::Hidden, false, String::new())
}

fn hud_event(phase: HudPhase, latched: bool, text: String) -> Event {
  Event::Hud {
    phase,
    latched,
    text,
    committed: String::new(),
    paused: false,
    rule: String::new(),
    marks: Vec::new(),
  }
}

struct Daemon {
  config: Config,
  machine: SessionMachine,
  guard: ChordGuard,
  trigger_code: Option<u16>,
  trigger_source: TriggerSource,
  audio: Audio,
  engine: Engine,
  media: Media,
  engine_event: Event,
  /// The last HUD state, replayed to a watcher that connects mid-session.
  hud_event: Event,
  watchers: Vec<Sender<String>>,
  tx: Sender<Msg>,

  session_id: u64,
  /// A microphone opened at key-down for the press the chord guard is still
  /// deciding about.
  prepared: Option<u64>,
  target: Option<Target>,
  rules: Option<Rules>,
  draft: String,
  /// The part of the draft live insertion has already put in the window.
  committed: String,
  marks: Vec<TextMark>,
  /// Where the stretch still being decoded starts in the recording. Live
  /// insertion moves it past every commit.
  segment_start: usize,
  live: Option<Live>,
  landing: Option<Landing>,
  /// The whole recording, kept from the moment the microphone closes until
  /// the dictation lands, for Retry.
  session_audio: Option<Vec<f32>>,
  latched: bool,
  paused: bool,
  watchdog: Option<MicWatchdog>,
  mic_alive: bool,
  /// Whether any window this session carried more than exact zeros.
  heard_signal: bool,
  warned_silent: bool,
  mic_opened_at: Option<Instant>,
  mic_name: String,
  no_speech_deadline: Option<Instant>,
  message_until: Option<Instant>,
  live_in_flight: bool,
  last_live_at: Instant,
  last_live_len: usize,
  played_begin: bool,
  speaking_seconds: f32,

  history: History,
  /// A Retry in flight: the id its decode carries.
  replay: Option<u64>,
  vocab: store::VocabFile,
  usage: UsageDocument,
}

impl Daemon {
  fn run(&mut self, rx: Receiver<Msg>) {
    loop {
      let received = match self.next_wake() {
        Some(at) => rx.recv_deadline(at),
        None => rx.recv().map_err(|_| RecvTimeoutError::Disconnected),
      };
      match received {
        Ok(msg) => self.handle(msg),
        Err(RecvTimeoutError::Timeout) => {}
        Err(RecvTimeoutError::Disconnected) => return,
      }
      self.tick(Instant::now());
    }
  }

  fn next_wake(&self) -> Option<Instant> {
    let recording = matches!(
      self.machine.state(),
      State::Recording(_) | State::Starting(_)
    );
    [
      self.guard.deadline(),
      self.no_speech_deadline,
      self.message_until,
      recording.then(|| Instant::now() + RECORDING_TICK),
    ]
    .into_iter()
    .flatten()
    .min()
  }

  fn handle(&mut self, msg: Msg) {
    match msg {
      Msg::Key { code, down, at } => self.key(code, down, at),
      Msg::Command(command, reply) => {
        let answer = self.command(command);
        let _ = reply.send(answer);
      }
      Msg::Watch(watcher) => self.add_watcher(watcher),
      Msg::MicStarted { id, at, name } if id == self.session_id => {
        self.mic_name = name;
        self.mic_opened_at = Some(at);
        self.dispatch(Action::RecognitionStarted { now: at });
      }
      Msg::MicFailed { id, error } if id == self.session_id => {
        tracing::error!("microphone failed: {error}");
        self.show_message("Microphone unavailable");
        self.dispatch(Action::RecognitionFailed {
          was_cancelled: false,
        });
      }
      Msg::MicStreamError { id } if id == self.session_id => {
        // The watchdog turns the visual amber once buffers stop.
      }
      Msg::Level {
        id,
        level,
        signal,
        at,
      } if id == self.session_id => self.level(level, signal, at),
      Msg::AudioFinished { id, samples } if id == self.session_id => {
        let offset = self.segment_start.min(samples.len());
        self.engine.send(Job::Final {
          id,
          offset,
          samples: samples[offset..].to_vec(),
        });
        self.keep_audio(samples);
      }
      Msg::Transcribed {
        id,
        is_final,
        offset,
        pass,
      } => {
        if Some(id) == self.replay {
          self.replay_decoded(pass);
        } else if id == self.session_id {
          if is_final {
            self.finished(pass);
          } else if offset == self.segment_start {
            self.live_pass(pass);
          } else {
            // Decoded from before the last commit: its words are partly in
            // the window already.
            self.live_in_flight = false;
          }
        }
      }
      Msg::EngineStatus {
        status,
        detail,
        progress,
      } => {
        self.engine_event = Event::Engine {
          status,
          detail,
          progress,
        };
        self.broadcast(&self.engine_event.clone());
      }
      Msg::Inserted { id, outcome } if id == self.session_id => self.landed(outcome),
      Msg::LiveDone { id, outcome } if id == self.session_id => {
        if self.live.take().is_some() {
          self.live_landed(outcome);
        }
      }
      Msg::Replayed { text, outcome } => self.replayed(text, outcome),
      // Anything else carries a stale session id.
      _ => {}
    }
  }

  fn tick(&mut self, now: Instant) {
    let outputs = self.guard.tick(now);
    self.guard_outputs(outputs);
    self.drop_unused_preroll();

    if self.no_speech_deadline.is_some_and(|at| now >= at) {
      self.no_speech_deadline = None;
      self.dispatch(Action::NoSpeechTimedOut);
    }
    if self.message_until.is_some_and(|at| now >= at) {
      self.message_until = None;
      if !self.machine.is_session_active() {
        self.set_hud(hidden());
      }
    }
    if matches!(self.machine.state(), State::Recording(_))
      && !self.paused
      && !self.heard_signal
      && !self.warned_silent
      && self
        .mic_opened_at
        .is_some_and(|at| now.duration_since(at) >= SILENT_MICROPHONE_AFTER)
    {
      self.warned_silent = true;
      self.draft = format!("{} is sending silence. Is it muted?", self.mic_name);
      self.marks.clear();
      self.hud(HudPhase::Live);
    }
    if let (State::Recording(_), Some(watchdog)) = (self.machine.state(), &self.watchdog) {
      // A paused session still gets buffers; it only keeps none of them.
      let alive = watchdog.is_alive(now) && !(self.warned_silent && !self.heard_signal);
      if alive != self.mic_alive {
        self.mic_alive = alive;
        self.broadcast(&Event::Mic { alive });
      }
      if !self.paused {
        self.maybe_request_live_draft(now);
      }
    }
  }

  /// A key or button went down or up. The Dictation Trigger has a chord
  /// guard; every other key is a possible chord, and Escape cancels.
  fn key(&mut self, code: u16, down: bool, at: Instant) {
    if self.trigger_source != TriggerSource::Keyboard {
      return;
    }
    let input = match (Some(code) == self.trigger_code, down) {
      (true, true) => Some(KeyInput::TriggerDown),
      (true, false) => Some(KeyInput::TriggerUp),
      (false, true) if code == keyboard::ESCAPE => Some(KeyInput::EscapeDown),
      (false, true) => Some(KeyInput::OtherKeyDown),
      (false, false) => None,
    };
    if let Some(input) = input {
      // Pre-roll: open the microphone the moment the trigger goes down, so
      // the guard's wait records instead of losing the first word.
      if input == KeyInput::TriggerDown
        && self.config.trigger.preroll
        && !self.machine.is_session_active()
        && self.prepared.is_none()
        && self.replay.is_none()
      {
        self.session_id += 1;
        self.prepared = Some(self.session_id);
        self.audio.send(AudioCmd::Prepare(self.session_id));
      }
      let outputs = self.guard.key(input, at);
      self.guard_outputs(outputs);
    }
    self.drop_unused_preroll();
  }

  /// A pre-roll the chord guard decided against (a shortcut, not dictation)
  /// is closed and its audio thrown away.
  fn drop_unused_preroll(&mut self) {
    if let Some(id) = self.prepared
      && !self.machine.is_session_active()
      && self.guard.deadline().is_none()
    {
      self.prepared = None;
      self.audio.send(AudioCmd::Cancel(id));
    }
  }

  fn guard_outputs(&mut self, outputs: Vec<GuardOutput>) {
    for output in outputs {
      let action = match output {
        GuardOutput::Pressed { at } => Action::TriggerPressed { now: at },
        GuardOutput::Released { at } => Action::TriggerReleased { now: at },
        GuardOutput::Escape | GuardOutput::ChordCancel => Action::EscapePressed,
      };
      self.dispatch(action);
    }
  }

  fn add_watcher(&mut self, watcher: Sender<String>) {
    let greeting: [Event; GREETING_EVENTS] = [
      Event::Hello {
        version: env!("CARGO_PKG_VERSION").into(),
        trigger: self.trigger_source,
        config: self.config.to_json(),
      },
      self.engine_event.clone(),
      Event::Recording {
        active: self.machine.is_session_active(),
      },
      self.hud_event.clone(),
      Event::History {
        items: self.history.items(),
      },
      self.vocab_event(),
      self.insights_event(),
    ];
    for event in greeting {
      let _ = watcher.try_send(event.to_line());
    }
    self.watchers.push(watcher);
  }

  fn broadcast(&mut self, event: &Event) {
    let line = event.to_line();
    self
      .watchers
      .retain(|watcher| match watcher.try_send(line.clone()) {
        Ok(()) => true,
        // A watcher too far behind loses this event; only a gone one is dropped.
        Err(TrySendError::Full(_)) => true,
        Err(TrySendError::Disconnected(_)) => false,
      });
  }

  fn set_hud(&mut self, event: Event) {
    self.hud_event = event.clone();
    self.broadcast(&event);
  }

  fn show_message(&mut self, text: &str) {
    self.message_until = Some(Instant::now() + MESSAGE_FOR);
    self.set_hud(hud_event(HudPhase::Message, false, text.into()));
  }

  fn hud(&mut self, phase: HudPhase) {
    let event = Event::Hud {
      phase,
      latched: self.latched,
      text: self.draft.clone(),
      committed: self.committed.clone(),
      paused: self.paused,
      rule: self
        .rules
        .as_ref()
        .map(|rules| rules.name.clone())
        .unwrap_or_default(),
      marks: self.marks.clone(),
    };
    self.set_hud(event);
  }

  fn dispatch(&mut self, action: Action) {
    let mut queue = VecDeque::from([action]);
    while let Some(action) = queue.pop_front() {
      for effect in self.machine.reduce(action) {
        if let Some(next) = self.effect(effect) {
          queue.push_back(next);
        }
      }
    }
  }

  /// Runs one effect; returns an action to feed straight back when the
  /// effect completes synchronously.
  fn effect(&mut self, effect: Effect) -> Option<Action> {
    match effect {
      Effect::CheckAndBegin => Some(self.check_and_begin()),
      Effect::BeginRecognition => {
        // A pre-rolled microphone is already recording for this session.
        match self.prepared.take() {
          Some(id) => self.session_id = id,
          None => self.session_id += 1,
        }
        self.reset_session_state();
        self
          .media
          .quiet(&self.config.media.mode, self.config.media.duck_to);
        self.live = self.start_live();
        self.audio.send(AudioCmd::Start(self.session_id));
        None
      }
      Effect::FinishRecognition { speaking_duration } => {
        self.speaking_seconds = speaking_duration.as_secs_f32();
        sounds::play(Cue::End, &self.config.sounds);
        self.audio.send(AudioCmd::Stop(self.session_id));
        None
      }
      Effect::CancelRecognition => {
        self.audio.send(AudioCmd::Cancel(self.session_id));
        self.abandon_live();
        Some(Action::SessionEnded)
      }
      Effect::CancelStart => {
        self.audio.send(AudioCmd::Cancel(self.session_id));
        self.abandon_live();
        Some(Action::RecognitionFailed {
          was_cancelled: true,
        })
      }
      Effect::StartNoSpeechTimer => {
        let timeout = self.config.engine.no_speech_timeout_ms;
        if timeout > 0 && self.config.engine.live_draft {
          self.no_speech_deadline = Some(Instant::now() + Duration::from_millis(timeout));
        }
        None
      }
      Effect::StopNoSpeechTimer => {
        self.no_speech_deadline = None;
        None
      }
      Effect::ShowListening { latched } => {
        // A new session: its first frame must not carry the last one's
        // draft.
        self.draft.clear();
        self.committed.clear();
        self.marks.clear();
        self.latched = latched;
        self.hud(HudPhase::Listening);
        None
      }
      Effect::ShowLatched => {
        self.latched = true;
        self.hud(if self.draft.is_empty() {
          HudPhase::Listening
        } else {
          HudPhase::Live
        });
        None
      }
      Effect::ShowLiveText => {
        self.hud(HudPhase::Live);
        None
      }
      Effect::ShowFinalizing => {
        self.hud(HudPhase::Finalizing);
        None
      }
      Effect::HideHud => {
        self.set_hud(hidden());
        None
      }
      Effect::NotifyRecording(active) => {
        if !active {
          self.watchdog = None;
          self.latched = false;
          self.paused = false;
          self.media.restore();
        }
        self.broadcast(&Event::Recording { active });
        None
      }
    }
  }

  fn reset_session_state(&mut self) {
    self.draft.clear();
    self.committed.clear();
    self.marks.clear();
    self.played_begin = false;
    self.watchdog = Some(MicWatchdog::new(Instant::now()));
    self.mic_alive = true;
    self.live_in_flight = false;
    self.last_live_at = Instant::now();
    self.last_live_len = 0;
    self.message_until = None;
    self.segment_start = 0;
    self.heard_signal = false;
    self.warned_silent = false;
    self.mic_opened_at = None;
    self.paused = false;
    self.landing = None;
    self.session_audio = None;
    self.speaking_seconds = 0.0;
  }

  /// The begin guards: no Retry is decoding and the Speech Model is ready.
  /// The window focused now is remembered so the text never lands in
  /// another.
  fn check_and_begin(&mut self) -> Action {
    if let Some(message) = self.refusal() {
      self.show_message(&message);
      if let Some(id) = self.prepared.take() {
        self.audio.send(AudioCmd::Cancel(id));
      }
      return Action::BeginRejected;
    }
    Action::BeginApproved
  }

  /// Why a session cannot begin, or None. Captures the target window and
  /// its App rules along the way.
  fn refusal(&mut self) -> Option<String> {
    if self.replay.is_some() {
      return Some("Still retrying the last dictation".into());
    }
    if let Event::Engine {
      status, progress, ..
    } = &self.engine_event
      && *status != EngineStatus::Ready
    {
      return Some(match status {
        EngineStatus::Downloading => format!("Downloading speech model {:.0}%", progress * 100.0),
        EngineStatus::Loading => "Speech model is loading".into(),
        _ => "Speech model unavailable, see Settings".into(),
      });
    }
    self.vocab_refresh();
    self.target = hyprland::active_window();
    let (class, is_terminal) = self
      .target
      .as_ref()
      .map_or((String::new(), false), |target| {
        (target.class.clone(), target.is_terminal)
      });
    self.rules = Some(apps::resolve(&self.config, &class, is_terminal));
    None
  }

  fn level(&mut self, level: f32, signal: bool, at: Instant) {
    if !matches!(self.machine.state(), State::Recording(_)) {
      return;
    }
    if let Some(watchdog) = &mut self.watchdog {
      watchdog.buffer_arrived(at);
    }
    if signal && !self.heard_signal {
      self.heard_signal = true;
      if self.warned_silent {
        // Unmuted mid-session: drop the warning, the visual comes back.
        self.draft.clear();
        self.hud(HudPhase::Listening);
      }
    }
    if !self.played_begin {
      self.played_begin = true;
      sounds::play(Cue::Begin, &self.config.sounds);
    }
    self.broadcast(&Event::Level { level });
  }
}
