//! What happens to a session's words after the Speech Model hears them:
//! the Tidy pass, the vocabulary, App rules, and then the window. Also live
//! insertion's per-pass commits, Retry, and the records a finished
//! dictation leaves (history, Insights).

use std::time::Instant;

use talkify_core::apps::{self, Rules, Send};
use talkify_core::insights;
use talkify_core::live::{LiveCommitter, Word};
use talkify_core::protocol::{Event, MarkKind, TextMark, utf16_len};
use talkify_core::session::{Action, State};
use talkify_core::tidy::{self, TidyOptions};

use super::audio::AudioCmd;
use super::engine::{Job, Pass};
use super::insert::{self, Destination, Method};
use super::sounds::{self, Cue};
use super::{Daemon, LIVE_EVERY, LIVE_MIN_NEW_SAMPLES, Landing, Live, Msg, hyprland};

impl Daemon {
  fn current_rules(&self) -> Rules {
    self
      .rules
      .clone()
      .unwrap_or_else(|| apps::resolve(&self.config, "", false))
  }

  /// The Tidy pass's options under these rules; `with_send` looks for the
  /// send phrase, which only matters at the end of a session.
  fn tidy_options(&self, rules: &Rules, with_send: bool) -> TidyOptions {
    let tidy = &self.config.tidy;
    let send_phrases = if with_send && rules.send == Send::Spoken {
      tidy::parse_phrases(&tidy.send_phrases)
    } else {
      Vec::new()
    };
    if rules.tidy {
      TidyOptions {
        fillers: tidy.fillers,
        stutters: tidy.stutters,
        spoken_punctuation: tidy.spoken_punctuation,
        scratch: tidy.scratch,
        send_phrases,
      }
    } else {
      TidyOptions {
        send_phrases,
        ..TidyOptions::none()
      }
    }
  }

  /// The vocabulary, then App rules' finishing touches for text that ends
  /// the dictation.
  fn polish(&mut self, text: &str, rules: &Rules) -> String {
    let text = self.apply_vocabulary(text);
    rules.format(&text)
  }

  /// For a live chunk in the middle of a dictation: the vocabulary and the
  /// case rule, but never the final-period rule, which would strip every
  /// sentence end that happens to close a chunk.
  fn polish_chunk(&mut self, text: &str, rules: &Rules) -> String {
    let text = self.apply_vocabulary(text);
    rules.format_chunk(&text)
  }

  fn apply_vocabulary(&mut self, text: &str) -> String {
    if self.config.vocab.enabled && !self.vocab.vocabulary.is_empty() {
      let applied = self.vocab.vocabulary.apply(text, self.config.vocab.fuzzy);
      if !applied.hits.is_empty() {
        self.vocab.record_hits(&applied.hits);
        let event = self.vocab_event();
        self.broadcast(&event);
      }
      applied.text
    } else {
      text.to_string()
    }
  }

  pub(super) fn keep_audio(&mut self, samples: Vec<f32>) {
    self.session_audio = Some(samples);
  }

  /// Live insertion runs when it is on and the text is meant for the
  /// window; copying to the clipboard has nothing to insert as it goes.
  pub(super) fn start_live(&self) -> Option<Live> {
    let insertion = &self.config.insertion;
    let destination = Destination::from_config(&insertion.destination);
    if !insertion.live || destination == Destination::Clipboard {
      return None;
    }
    let id = self.session_id;
    let tx = self.tx.clone();
    let inserter = insert::LiveInserter::start(
      self.target.clone(),
      destination == Destination::Insert,
      move |outcome| {
        let _ = tx.send(Msg::LiveDone { id, outcome });
      },
    );
    Some(Live {
      committer: LiveCommitter::new(insertion.live_pause_ms as f32 / 1000.0),
      inserter,
    })
  }

  /// A cancelled session keeps what is already in the window (a paste
  /// cannot be taken back) and gets its clipboard back.
  pub(super) fn abandon_live(&mut self) {
    if let Some(live) = self.live.take() {
      live.inserter.finish(false);
    }
  }

  pub(super) fn maybe_request_live_draft(&mut self, now: Instant) {
    let wanted = self.config.engine.live_draft || self.live.is_some();
    if !wanted || self.live_in_flight {
      return;
    }
    let recorded = self.audio.recorded_len();
    if now.duration_since(self.last_live_at) < LIVE_EVERY
      || recorded < self.last_live_len + LIVE_MIN_NEW_SAMPLES
    {
      return;
    }
    let samples = self.audio.snapshot();
    let offset = self.segment_start.min(samples.len());
    self.live_in_flight = true;
    self.last_live_at = now;
    self.last_live_len = recorded;
    self.engine.send(Job::Live {
      id: self.session_id,
      offset,
      samples: samples[offset..].to_vec(),
    });
  }

  pub(super) fn live_pass(&mut self, pass: Pass) {
    self.live_in_flight = false;
    if !matches!(self.machine.state(), State::Recording(_))
      || self.warned_silent && !self.heard_signal
    {
      return;
    }
    let rules = self.current_rules();
    let tidied = tidy::tidy(&pass.words, &self.tidy_options(&rules, false));
    // Only a latched session inserts as it goes. While the trigger is held,
    // a synthetic paste lands mid-chord and confuses the compositor's
    // record of which keys are down; a held session inserts on release.
    if self.live.is_some() && self.latched {
      let commit = {
        let live = self.live.as_mut().expect("checked above");
        live
          .committer
          .pass(&tidied.kept, pass.seconds, pass.trailing_silence)
      };
      let mut pending: Vec<Word> = tidied.kept.clone();
      if let Some(commit) = commit {
        let cut = commit.cut as f32 / 16_000.0;
        self.segment_start += commit.cut;
        let chunk = self.polish_chunk(&commit.text, &rules);
        if let Some(live) = &self.live {
          live.inserter.chunk(chunk);
        }
        pending.retain(|word| word.start >= cut);
      }
      let live = self.live.as_ref().expect("checked above");
      self.committed = live.committer.inserted().to_string();
      self.draft = live.committer.display(&pending);
      self.marks.clear();
    } else {
      let (draft, mut marks) = tidied.draft_with_marks();
      if self.config.vocab.enabled && !self.vocab.vocabulary.is_empty() {
        let applied = self.vocab.vocabulary.apply(&draft, self.config.vocab.fuzzy);
        for (span, replacement) in applied.spans.into_iter().zip(applied.replacements) {
          marks.push(TextMark {
            start: utf16_len(&draft[..span.start]),
            end: utf16_len(&draft[..span.end]),
            kind: MarkKind::Vocabulary,
            replacement,
          });
        }
        marks.sort_by_key(|mark| mark.start);
      }
      self.draft = draft;
      self.marks = marks;
    }
    if !self.draft.is_empty() {
      self.dispatch(Action::UpdateReceived {
        has_visible_text: true,
      });
    }
  }

  /// The final pass is in: decide what lands, and send it on its way.
  pub(super) fn finished(&mut self, pass: Pass) {
    let rules = self.current_rules();
    let audio = self.session_audio.take();

    if self.live.is_some() {
      let tidied = tidy::tidy(&pass.words, &self.tidy_options(&rules, true));
      let send = tidied.send || rules.send == Send::Always;
      let rest = {
        let live = self.live.as_mut().expect("checked above");
        live.committer.finish(&tidied.kept).unwrap_or_default()
      };
      let mut rest = self.polish(&rest, &rules);
      let live = self.live.as_ref().expect("checked above");
      let inserted = live.committer.inserted().to_string();
      if rules.trailing_space && !send && !inserted.is_empty() {
        rest.push(' ');
      }
      if !rest.is_empty() {
        live.inserter.chunk(rest);
      }
      live.inserter.finish(send);
      self.committed = inserted.clone();
      self.draft = inserted.clone();
      self.landing = Some(Landing {
        raw: pass.text,
        text: inserted,
        send,
        audio,
      });
      return;
    }

    let tidied = tidy::tidy(&pass.words, &self.tidy_options(&rules, true));
    let text = if pass.words.is_empty() {
      pass.text.clone()
    } else {
      tidied.text.clone()
    };
    let text = self.polish(&text, &rules);
    if text.trim().is_empty() {
      self.no_speech();
      return;
    }
    self.landing = Some(Landing {
      raw: pass.text,
      text,
      send: tidied.send || rules.send == Send::Always,
      audio,
    });
    self.deliver();
  }

  /// Sends the landing to the window (or the clipboard) on another thread.
  fn deliver(&mut self) {
    let rules = self.current_rules();
    let Some(landing) = self.landing.as_ref() else {
      return;
    };
    self.draft = landing.text.clone();
    let id = self.session_id;
    let tx = self.tx.clone();
    let mut insertion = landing.text.clone();
    if rules.trailing_space && !landing.send {
      insertion.push(' ');
    }
    let enter = landing.send;
    let target = self.target.clone();
    let destination = Destination::from_config(&self.config.insertion.destination);
    let method = Method::from_config(&self.config.insertion.method);
    std::thread::spawn(move || {
      let outcome = insert::insert(&insertion, target.as_ref(), destination, method, enter);
      let _ = tx.send(Msg::Inserted { id, outcome });
    });
  }

  pub(super) fn landed(&mut self, outcome: insert::Outcome) {
    let Some(landing) = self.landing.take() else {
      self.dispatch(Action::SessionEnded);
      return;
    };
    let sent = landing.send && outcome.inserted;
    self.finish_session(landing, outcome, sent);
  }

  pub(super) fn live_landed(&mut self, outcome: insert::Outcome) {
    let text = self.committed.trim_end().to_string();
    let landing = self.landing.take().unwrap_or(Landing {
      raw: text.clone(),
      text: text.clone(),
      send: false,
      audio: None,
    });
    if text.is_empty() && outcome.note.is_empty() {
      self.no_speech();
      return;
    }
    let sent = landing.send && outcome.inserted;
    let landing = Landing { text, ..landing };
    self.finish_session(landing, outcome, sent);
  }

  fn finish_session(&mut self, landing: Landing, outcome: insert::Outcome, sent: bool) {
    let text = landing.text.trim_end().to_string();
    self.log_outcome(&text, outcome.inserted, &outcome.note);
    if outcome.inserted {
      sounds::play(Cue::Paste, &self.config.sounds);
    }
    let rule = self
      .rules
      .as_ref()
      .map(|rules| rules.name.clone())
      .unwrap_or_default();
    // The result goes out before the HUD is told to hide, so it can play
    // what landed (the diff, the send key) without guessing how long to wait.
    self.broadcast(&Event::Result {
      text: text.clone(),
      inserted: outcome.inserted,
      note: outcome.note.clone(),
      raw: landing.raw.clone(),
      sent,
      rule,
    });
    if outcome.note.is_empty() {
      self.set_hud(super::hidden());
    } else {
      self.show_message(&outcome.note);
    }
    let finished = outcome.inserted || outcome.note.starts_with("Copied");
    self.record(
      &text,
      &landing.raw,
      outcome.inserted,
      landing.audio,
      finished,
    );
    self.dispatch(Action::SessionEnded);
  }

  /// What a finished dictation leaves behind: a history entry (with its
  /// audio, for Retry), a line in today's file when saving is on, and
  /// Insights' aggregates.
  fn record(
    &mut self,
    text: &str,
    raw: &str,
    inserted: bool,
    audio: Option<Vec<f32>>,
    finished: bool,
  ) {
    if text.is_empty() {
      return;
    }
    let app = self
      .target
      .as_ref()
      .map(|target| target.class.clone())
      .unwrap_or_default();
    self.history.push(talkify_core::history::Record {
      at: chrono::Local::now().timestamp(),
      app: app.clone(),
      text: text.to_string(),
      raw: raw.to_string(),
      seconds: self.speaking_seconds,
      inserted,
      rule: self
        .rules
        .as_ref()
        .map(|rules| rules.name.clone())
        .unwrap_or_default(),
      audio,
    });
    let event = Event::History {
      items: self.history.items(),
    };
    self.broadcast(&event);
    if self.config.history.save {
      super::store::save_dictation(&app, text);
    }
    if self.config.insights.enabled && finished {
      let today = chrono::Local::now().date_naive();
      let reached = self.usage.record(
        today,
        insights::word_count(text),
        f64::from(self.speaking_seconds),
      );
      if let Err(error) = super::store::save_usage(&self.usage) {
        tracing::warn!("could not save Insights: {error:#}");
      }
      let event = self.insights_event();
      self.broadcast(&event);
      for milestone in reached {
        tracing::info!("milestone: {} {}", milestone.kind, milestone.value);
        self.broadcast(&Event::Milestone {
          kind: milestone.kind,
          value: milestone.value,
        });
      }
    }
  }

  pub(super) fn no_speech(&mut self) {
    self.log_outcome("", false, "no speech");
    if self.heard_signal {
      self.show_message("No speech heard");
    } else {
      let message = format!("{} sent only silence. Is it muted?", self.mic_name);
      self.show_message(&message);
    }
    self.broadcast(&Event::Result {
      text: String::new(),
      inserted: false,
      note: "No speech heard".into(),
      raw: String::new(),
      sent: false,
      rule: String::new(),
    });
    self.landing = None;
    self.dispatch(Action::SessionEnded);
  }

  pub(super) fn log_outcome(&self, text: &str, inserted: bool, note: &str) {
    tracing::info!(
      "session {}: microphone {}, {} characters, {}{}",
      self.session_id,
      if self.heard_signal { "live" } else { "silent" },
      text.chars().count(),
      if inserted { "inserted" } else { "not inserted" },
      if note.is_empty() {
        String::new()
      } else {
        format!(" ({note})")
      }
    );
  }

  /// Retry's decode is in: run it through the same rules for the window
  /// focused now, and insert it there.
  pub(super) fn replay_decoded(&mut self, pass: Pass) {
    self.replay = None;
    let target = hyprland::active_window();
    let (class, is_terminal) = target.as_ref().map_or((String::new(), false), |target| {
      (target.class.clone(), target.is_terminal)
    });
    let rules = apps::resolve(&self.config, &class, is_terminal);
    let tidied = tidy::tidy(&pass.words, &self.tidy_options(&rules, false));
    let text = self.polish(&tidied.text, &rules);
    if text.trim().is_empty() {
      self.show_message("Nothing heard in it");
      return;
    }
    self.paste_again(text, rules.trailing_space);
  }

  /// Inserts text into the window focused now (Paste again, Retry): no focus
  /// check, there is no earlier window to compare with.
  pub(super) fn paste_again(&mut self, text: String, trailing_space: bool) {
    let tx = self.tx.clone();
    let method = Method::from_config(&self.config.insertion.method);
    std::thread::spawn(move || {
      let mut insertion = text.clone();
      if trailing_space {
        insertion.push(' ');
      }
      let outcome = insert::insert(&insertion, None, Destination::Insert, method, false);
      let _ = tx.send(Msg::Replayed { text, outcome });
    });
  }

  pub(super) fn replayed(&mut self, text: String, outcome: insert::Outcome) {
    if outcome.inserted {
      sounds::play(Cue::Paste, &self.config.sounds);
    }
    self.broadcast(&Event::Replayed {
      text,
      inserted: outcome.inserted,
      note: outcome.note,
    });
  }

  /// Starts decoding a past dictation's audio again.
  pub(super) fn retry(&mut self, index: usize) -> Result<(), String> {
    if self.machine.is_session_active() || self.replay.is_some() {
      return Err("finish dictating first".into());
    }
    let audio = self
      .history
      .get(index)
      .ok_or("no such dictation")?
      .audio
      .clone()
      .ok_or("its audio is no longer kept")?;
    if let Some(id) = self.prepared.take() {
      self.audio.send(AudioCmd::Cancel(id));
    }
    self.session_id += 1;
    self.replay = Some(self.session_id);
    self.engine.send(Job::Final {
      id: self.session_id,
      offset: 0,
      samples: audio,
    });
    Ok(())
  }

  pub(super) fn vocab_refresh(&mut self) {
    if self.vocab.refresh() {
      let event = self.vocab_event();
      self.broadcast(&event);
    }
  }

  pub(super) fn vocab_event(&self) -> Event {
    Event::Vocab {
      entries: self
        .vocab
        .vocabulary
        .entries
        .iter()
        .zip(&self.vocab.hits)
        .map(|(entry, hits)| talkify_core::protocol::VocabEntry {
          line: entry.line.clone(),
          kind: entry.kind.as_str().into(),
          hits: *hits,
        })
        .collect(),
      path: crate::paths::words_file().display().to_string(),
    }
  }

  pub(super) fn insights_event(&self) -> Event {
    let today = chrono::Local::now().date_naive();
    Event::Insights {
      insights: self.usage.snapshot(today, self.config.insights.typing_wpm),
    }
  }
}
