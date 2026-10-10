//! The session's three sounds: Begin when the microphone is live, End when
//! speech stops, Paste when the text lands. Played through PipeWire's
//! `pw-play` so the daemon needs no audio output of its own.

use std::process::{Command, Stdio};

use talkify_core::config::SoundConfig;

use crate::paths;

#[derive(Clone, Copy)]
pub enum Cue {
  Begin,
  End,
  Paste,
}

pub fn play(cue: Cue, config: &SoundConfig) {
  if !config.enabled {
    return;
  }
  let suffix = match cue {
    Cue::Begin => "Begin",
    Cue::End => "End",
    Cue::Paste => "Paste",
  };
  let prefix = match config.set.as_str() {
    "chime" => "Chime",
    "click" => "Click",
    _ => "Synth8",
  };
  let file = paths::sounds_dir().join(format!("{prefix}{suffix}.wav"));
  if !file.exists() {
    tracing::debug!("no sound at {}", file.display());
    return;
  }
  let spawned = Command::new("pw-play")
    .arg(format!("--volume={:.2}", config.volume.clamp(0.0, 1.0)))
    .arg(&file)
    .stdin(Stdio::null())
    .stdout(Stdio::null())
    .stderr(Stdio::null())
    .spawn();
  match spawned {
    // Reap it off the hot path so no zombie is left behind.
    Ok(mut child) => drop(std::thread::spawn(move || child.wait())),
    Err(error) => tracing::warn!("could not play {}: {error}", file.display()),
  }
}
