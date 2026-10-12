//! What the socket can ask for: session control, Paste again, Retry,
//! Teach, the vocabulary, settings.

use std::time::Instant;

use talkify_core::chord::ChordGuard;
use talkify_core::protocol::{Command, Event, HudPhase, TriggerSource};
use talkify_core::session::{Action, Gesture, State};
use talkify_core::vocab::Vocabulary;

use super::audio::AudioCmd;
use super::{Daemon, guard_for, insert, keyboard, store};

impl Daemon {
  pub(super) fn command(&mut self, command: Command) -> String {
    let now = Instant::now();
    let result: Result<(), String> = match command {
      Command::Toggle => {
        self.dispatch(Action::Toggled { now });
        Ok(())
      }
      Command::Cancel => {
        self.dispatch(Action::EscapePressed);
        Ok(())
      }
      Command::Press => {
        self.dispatch(Action::TriggerPressed { now });
        Ok(())
      }
      Command::Release => {
        self.dispatch(Action::TriggerReleased { now });
        Ok(())
      }
      Command::Tap => {
        if self.trigger_source == TriggerSource::Commands {
          self.dispatch(Action::Toggled { now });
        }
        Ok(())
      }
      Command::Pause => self.toggle_pause(),
      Command::LoadModel => {
        self.engine.send(super::engine::Job::Load);
        Ok(())
      }
      Command::ConfigSet { key, value } => self.set_config(&key, &value),
      Command::PasteLast { index, raw } => self.past_text(index, raw).map(|text| {
        let trailing = self.config.insertion.trailing_space;
        self.paste_again(text, trailing);
      }),
      Command::CopyLast { index, raw } => self.past_text(index, raw).and_then(|text| {
        insert::copy(&text).map_err(|error| format!("{error:#}"))?;
        self.show_message("Copied");
        Ok(())
      }),
      Command::Retry { index } => self.retry(index),
      Command::Teach => self.teach(),
      Command::VocabAdd { line } => self.vocab_edit(|vocab| vocab.add(&line)),
      Command::VocabRemove { line } => self.vocab_edit(|vocab| vocab.remove(&line)),
      Command::HistoryClear => {
        self.history.clear();
        let event = Event::History { items: Vec::new() };
        self.broadcast(&event);
        Ok(())
      }
      Command::Disconnect => {
        tracing::info!("disconnect requested, shutting down daemon");
        std::thread::spawn(|| {
          std::thread::sleep(std::time::Duration::from_millis(50));
          let _ = std::fs::remove_file(crate::paths::socket());
          std::process::exit(0);
        });
        Ok(())
      }
      Command::Watch => Ok(()),
    };
    match result {
      Ok(()) => "ok".into(),
      Err(error) => format!("error: {error}"),
    }
  }

  fn toggle_pause(&mut self) -> Result<(), String> {
    if !matches!(self.machine.state(), State::Recording(Gesture::Latched)) {
      return Err("only a hands-free session can pause".into());
    }
    self.paused = !self.paused;
    self.audio.send(AudioCmd::Pause(self.paused));
    // Silence while paused is expected, not a reason to give up.
    self.no_speech_deadline = None;
    let phase = if self.draft.is_empty() {
      HudPhase::Listening
    } else {
      HudPhase::Live
    };
    self.hud(phase);
    Ok(())
  }

  fn past_text(&self, index: usize, raw: bool) -> Result<String, String> {
    let entry = self.history.get(index).ok_or("no such dictation")?;
    let text = if raw && !entry.item.raw.is_empty() {
      entry.item.raw.clone()
    } else {
      entry.item.text.clone()
    };
    if text.is_empty() {
      return Err("that dictation is empty".into());
    }
    Ok(text)
  }

  /// Learns from a correction: the primary selection is the right spelling
  /// of something the last dictation got wrong.
  fn teach(&mut self) -> Result<(), String> {
    let selection = insert::primary_selection().ok_or("select the corrected word first")?;
    let last = self
      .history
      .latest()
      .map(|entry| entry.item.text.clone())
      .ok_or("dictate something first")?;
    let Some(line) = Vocabulary::teach(&last, &selection) else {
      self.show_message("Already right");
      return Ok(());
    };
    self.vocab_edit(|vocab| vocab.add(&line))?;
    let (heard, written) = match line.split_once(" -> ") {
      Some((heard, written)) => (heard.to_string(), written.to_string()),
      None => (String::new(), line.clone()),
    };
    tracing::info!("taught {line:?}");
    self.broadcast(&Event::Taught { heard, written });
    Ok(())
  }

  fn vocab_edit(
    &mut self,
    edit: impl FnOnce(&mut store::VocabFile) -> anyhow::Result<()>,
  ) -> Result<(), String> {
    edit(&mut self.vocab).map_err(|error| format!("{error:#}"))?;
    let event = self.vocab_event();
    self.broadcast(&event);
    Ok(())
  }

  fn set_config(&mut self, key: &str, value: &str) -> Result<(), String> {
    let mut config = self.config.clone();
    config.set(key, value).map_err(|error| error.to_string())?;
    if key == "trigger.key"
      && !config.trigger.key.is_empty()
      && keyboard::key_code(&config.trigger.key).is_none()
    {
      return Err(format!(
        "{value} is not a Linux key name like KEY_RIGHTMETA"
      ));
    }
    if key.starts_with("trigger.") {
      self.trigger_code = keyboard::key_code(&config.trigger.key);
      self.guard = ChordGuard::new(guard_for(
        &config.trigger.key,
        config.trigger.chord_guard_ms,
      ));
    }
    if key == "history.size" {
      self.history.resize(config.history.size as usize);
    }
    self.config = config;
    if let Err(error) = store::save_config(&self.config) {
      tracing::warn!("could not save settings: {error:#}");
    }
    let event = Event::Config {
      config: self.config.to_json(),
    };
    self.broadcast(&event);
    if key == "insights.typing_wpm" {
      let event = self.insights_event();
      self.broadcast(&event);
    }
    Ok(())
  }
}
