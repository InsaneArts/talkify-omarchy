//! What crosses the daemon's socket. One JSON object per line both ways.
//!
//! The Omarchy shell plugin runs `talkify watch` and reads `Event`s off its
//! stdout; the CLI and the plugin's buttons send `Command`s. Every field
//! added after the first release carries a default, so an older plugin
//! reading a newer daemon (or the reverse) keeps working.
//!
//! Text offsets (`TextMark`) count UTF-16 code units, because the plugin is
//! JavaScript and that is what its strings index by.

use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(tag = "cmd", rename_all = "kebab-case")]
pub enum Command {
  /// Stream events until the client hangs up.
  Watch,
  /// Start a latched session, or finish the one in flight.
  Toggle,
  Cancel,
  /// The trigger as a pair of commands, for compositor key binds when the
  /// daemon cannot read the keyboard itself.
  Press,
  Release,
  /// A tap of the trigger seen by the compositor. A toggle when the daemon
  /// cannot read the keyboard; ignored when it can, because then it has
  /// already seen the same tap itself. One bind works either way.
  Tap,
  /// Pause or resume the latched session in flight.
  Pause,
  ConfigSet {
    key: String,
    value: String,
  },
  /// Ask the daemon to (re)load the Speech Model, downloading it if missing.
  LoadModel,
  /// Insert a past dictation again into the window focused now. `index` 0
  /// is the latest; `raw` is the text before the Tidy pass and the
  /// vocabulary.
  PasteLast {
    #[serde(default)]
    index: usize,
    #[serde(default)]
    raw: bool,
  },
  CopyLast {
    #[serde(default)]
    index: usize,
    #[serde(default)]
    raw: bool,
  },
  /// Decode a past dictation's kept audio again and insert the result into
  /// the window focused now.
  Retry {
    #[serde(default)]
    index: usize,
  },
  /// Learn from a correction: the primary selection holds the right
  /// spelling of a word the last dictation got wrong.
  Teach,
  /// Add or remove one line of the vocabulary file (`word`,
  /// `heard -> written`, or `trigger => expansion`).
  VocabAdd {
    line: String,
  },
  VocabRemove {
    line: String,
  },
  HistoryClear,
  /// Stop the daemon process, cleanly releasing its socket and resources.
  Disconnect,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum HudPhase {
  Hidden,
  Listening,
  Live,
  Finalizing,
  Message,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum EngineStatus {
  Missing,
  Downloading,
  Loading,
  Ready,
  Failed,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum TriggerSource {
  /// The daemon reads the keyboard and runs the chord guard itself.
  Keyboard,
  /// No keyboard access: only `press`/`release`/`toggle` commands drive it.
  Commands,
}

/// What a stretch of the draft is, so the HUD can draw it: a filler or a
/// scratched phrase the Tidy pass will remove, spoken punctuation it will
/// turn into a mark, or a vocabulary hit.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum MarkKind {
  Filler,
  Scratched,
  Punctuation,
  Vocabulary,
  Send,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct TextMark {
  /// UTF-16 offsets into the event's `text`, end exclusive.
  pub start: usize,
  pub end: usize,
  pub kind: MarkKind,
  /// For a vocabulary mark, what the vocabulary will write in its place.
  #[serde(default, skip_serializing_if = "String::is_empty")]
  pub replacement: String,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct HistoryItem {
  /// Stable for the daemon's lifetime; newest has the highest.
  pub id: u64,
  /// Unix seconds.
  pub at: i64,
  /// The window class it was dictated into, "" when unknown.
  pub app: String,
  /// What landed (or would have).
  pub text: String,
  /// What the Speech Model heard, before any cleanup.
  pub raw: String,
  pub words: usize,
  pub seconds: f32,
  pub inserted: bool,
  /// Whether its audio is still kept for a retry.
  pub retryable: bool,
  /// The App rules that applied, by name, or "".
  #[serde(default)]
  pub rule: String,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct VocabEntry {
  /// The line as written in the file.
  pub line: String,
  /// `word`, `replacement` or `snippet`.
  pub kind: String,
  /// How often it changed a dictation since the daemon started.
  pub hits: u32,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(tag = "t", rename_all = "kebab-case")]
pub enum Event {
  Hello {
    version: String,
    trigger: TriggerSource,
    config: serde_json::Value,
  },
  /// What the HUD shows. `latched` matters while listening; `text` carries
  /// the live draft or a message.
  Hud {
    phase: HudPhase,
    latched: bool,
    text: String,
    /// The start of `text` that live insertion has already put in the
    /// window; the rest is still a draft.
    #[serde(default)]
    committed: String,
    /// The session is paused: the microphone is still open but nothing it
    /// hears is kept.
    #[serde(default)]
    paused: bool,
    /// The App rules in force, by name ("terminal", a window class), or ""
    /// for none.
    #[serde(default)]
    rule: String,
    #[serde(default)]
    marks: Vec<TextMark>,
  },
  Recording {
    active: bool,
  },
  /// Microphone level 0–1, about 50 times a second while recording.
  Level {
    level: f32,
  },
  /// Whether buffers are still arriving. False means a dead microphone,
  /// which the HUD draws differently from silence.
  Mic {
    alive: bool,
  },
  Engine {
    status: EngineStatus,
    detail: String,
    progress: f32,
  },
  /// A finished session's text and where it went.
  Result {
    text: String,
    inserted: bool,
    note: String,
    /// What the Speech Model heard, before the Tidy pass and the
    /// vocabulary.
    #[serde(default)]
    raw: String,
    /// Whether a spoken send pressed Enter after it.
    #[serde(default)]
    sent: bool,
    #[serde(default)]
    rule: String,
  },
  /// A past dictation inserted again (paste-last, retry): the HUD flashes
  /// what landed.
  Replayed {
    text: String,
    inserted: bool,
    note: String,
  },
  Config {
    config: serde_json::Value,
  },
  /// The recent dictations, newest first. Sent on watch and after each
  /// session.
  History {
    items: Vec<HistoryItem>,
  },
  /// The vocabulary file's entries. Sent on watch and whenever it changes.
  Vocab {
    entries: Vec<VocabEntry>,
    path: String,
  },
  /// A correction learned by Teach.
  Taught {
    heard: String,
    written: String,
  },
  /// The Insights snapshot. Sent on watch and after each session.
  Insights {
    insights: serde_json::Value,
  },
  /// A milestone reached for the first time: `words`, `streak` or
  /// `sessions`, with the round number reached.
  Milestone {
    kind: String,
    value: u64,
  },
}

impl Event {
  pub fn to_line(&self) -> String {
    let mut line = serde_json::to_string(self).expect("events always serialize");
    line.push('\n');
    line
  }
}

/// UTF-16 length of a string, the unit `TextMark` offsets use.
pub fn utf16_len(text: &str) -> usize {
  text.encode_utf16().count()
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn commands_round_trip_as_tagged_json() {
    let set = Command::ConfigSet {
      key: "hud.visual".into(),
      value: "glow".into(),
    };
    let json = serde_json::to_string(&set).unwrap();
    assert_eq!(
      json,
      r#"{"cmd":"config-set","key":"hud.visual","value":"glow"}"#
    );
    assert_eq!(serde_json::from_str::<Command>(&json).unwrap(), set);
    assert_eq!(
      serde_json::from_str::<Command>(r#"{"cmd":"toggle"}"#).unwrap(),
      Command::Toggle
    );
  }

  #[test]
  fn optional_command_fields_default() {
    assert_eq!(
      serde_json::from_str::<Command>(r#"{"cmd":"paste-last"}"#).unwrap(),
      Command::PasteLast {
        index: 0,
        raw: false
      }
    );
    assert_eq!(
      serde_json::from_str::<Command>(r#"{"cmd":"retry","index":2}"#).unwrap(),
      Command::Retry { index: 2 }
    );
  }

  #[test]
  fn events_are_one_line_each() {
    let line = Event::Hud {
      phase: HudPhase::Live,
      latched: false,
      text: "a\nb".into(),
      committed: String::new(),
      paused: false,
      rule: String::new(),
      marks: vec![],
    }
    .to_line();
    assert_eq!(line.matches('\n').count(), 1);
    assert!(line.starts_with(r#"{"t":"hud","phase":"live""#));
  }

  #[test]
  fn an_old_hud_event_still_reads() {
    let event: Event =
      serde_json::from_str(r#"{"t":"hud","phase":"live","latched":false,"text":"hi"}"#).unwrap();
    let Event::Hud {
      committed, marks, ..
    } = event
    else {
      panic!()
    };
    assert!(committed.is_empty());
    assert!(marks.is_empty());
  }

  #[test]
  fn utf16_counts_like_javascript() {
    assert_eq!(utf16_len("héllo"), 5);
    assert_eq!(utf16_len("👻"), 2);
  }
}
