//! Lands a finished session's text in the window it was dictated for.
//!
//! Paste is the default: the text goes on the clipboard, Hyprland presses
//! the paste shortcut, and half a second later whatever was on the
//! clipboard before comes back, but only if the clipboard still holds
//! Talkify's text (someone copying in between wins). The write carries the
//! password-manager hint, which tells Omarchy's clipboard history not to
//! record every dictated phrase.

use std::io::Read;
use std::process::Command;
use std::time::{Duration, Instant};

use anyhow::{Context, anyhow};
use crossbeam_channel::Sender;
use wl_clipboard_rs::copy::{self, MimeSource, MimeType, Source};
use wl_clipboard_rs::paste::{self, Seat};

use super::hyprland::{self, Target};

const TRANSIENT_MARKER: &str = "application/x-talkify-transient";
const PASSWORD_MANAGER_HINT: &str = "x-kde-passwordManagerHint";
/// How long the target app gets to read the clipboard before it is restored.
const RESTORE_AFTER: Duration = Duration::from_millis(500);
/// Never hold more than this of the previous clipboard in memory.
const SNAPSHOT_LIMIT: usize = 32 * 1024 * 1024;
/// How long an app gets to read one live chunk before the clipboard changes
/// under it for the next.
const PASTE_SETTLE: Duration = Duration::from_millis(200);
/// How long the paste gets to land before a spoken send presses Enter.
const ENTER_AFTER: Duration = Duration::from_millis(120);

/// `TALKIFY_DRY_INSERT=1`: nothing touches the clipboard or presses a key,
/// and what would have landed is logged. The end-to-end tests run a second
/// daemon this way beside the user's.
pub fn dry() -> bool {
  std::env::var_os("TALKIFY_DRY_INSERT").is_some_and(|value| value == "1")
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Destination {
  /// Paste into the window, then put the old clipboard back.
  Insert,
  /// Copy only.
  Clipboard,
  /// Paste and leave the text on the clipboard.
  Both,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Method {
  Paste,
  Type,
}

impl Destination {
  pub fn from_config(value: &str) -> Self {
    match value {
      "clipboard" => Destination::Clipboard,
      "both" => Destination::Both,
      _ => Destination::Insert,
    }
  }
}

impl Method {
  pub fn from_config(value: &str) -> Self {
    if value == "type" {
      Method::Type
    } else {
      Method::Paste
    }
  }
}

pub struct Outcome {
  pub inserted: bool,
  pub note: String,
}

/// Lands `text`; `enter` presses Enter after it, for a spoken send.
pub fn insert(
  text: &str,
  target: Option<&Target>,
  destination: Destination,
  method: Method,
  enter: bool,
) -> Outcome {
  if dry() {
    tracing::info!("dry insert {text:?} into {destination:?}, enter {enter}");
    return Outcome {
      inserted: destination != Destination::Clipboard,
      note: if destination == Destination::Clipboard {
        "Copied".into()
      } else {
        String::new()
      },
    };
  }
  if destination == Destination::Clipboard {
    return match put_on_clipboard(text, false) {
      Ok(()) => Outcome {
        inserted: false,
        note: "Copied".into(),
      },
      Err(error) => Outcome {
        inserted: false,
        note: format!("Could not copy: {error:#}"),
      },
    };
  }
  // Focus-validated: text dictated for one window never lands in another.
  // When focus moved, the text waits on the clipboard instead.
  let focused = hyprland::active_window();
  let moved = match (target, focused.as_ref()) {
    (Some(target), Some(focused)) => target.address != focused.address,
    (Some(_), None) => true,
    (None, _) => false,
  };
  if moved {
    return match put_on_clipboard(text, false) {
      Ok(()) => Outcome {
        inserted: false,
        note: "Focus moved, copied instead".into(),
      },
      Err(error) => Outcome {
        inserted: false,
        note: format!("Could not copy: {error:#}"),
      },
    };
  }

  let is_terminal = focused.as_ref().is_some_and(|window| window.is_terminal);
  let result = match method {
    Method::Paste => paste(text, is_terminal, destination == Destination::Insert),
    Method::Type => {
      let typed = type_text(text);
      if typed.is_ok() && destination == Destination::Both {
        let _ = put_on_clipboard(text, false);
      }
      typed
    }
  };
  let result = result.and_then(|()| {
    if enter {
      std::thread::sleep(ENTER_AFTER);
      hyprland::press_enter()?;
    }
    Ok(())
  });
  match result {
    Ok(()) => Outcome {
      inserted: true,
      note: String::new(),
    },
    Err(error) => {
      tracing::error!("insertion failed: {error:#}");
      let _ = put_on_clipboard(text, false);
      Outcome {
        inserted: false,
        note: "Could not paste, copied instead".into(),
      }
    }
  }
}

enum LiveCmd {
  Chunk(String),
  /// No more chunks; press Enter after the last one for a spoken send.
  Finish {
    enter: bool,
  },
}

/// Live insertion's side of the clipboard: chunks are pasted in order on
/// one thread, the clipboard is snapshotted once before the first and put
/// back once after the last. Always a paste, never typed: while the trigger
/// is held, a virtual keyboard's letters would merge with the held Super
/// into shortcuts, and Hyprland's paste names its modifiers explicitly.
pub struct LiveInserter {
  commands: Sender<LiveCmd>,
}

impl LiveInserter {
  /// `done` runs once, after `finish`, with what happened to the session.
  pub fn start(
    target: Option<Target>,
    restore: bool,
    done: impl FnOnce(Outcome) + Send + 'static,
  ) -> Self {
    let (commands, rx) = crossbeam_channel::unbounded();
    std::thread::Builder::new()
      .name("live-insert".into())
      .spawn(move || {
        let mut previous: Option<Vec<(String, Vec<u8>)>> = None;
        let mut last_paste: Option<Instant> = None;
        let mut inserted = false;
        let mut stranded = String::new();
        let mut failed = false;
        for command in rx {
          match command {
            LiveCmd::Chunk(text) => {
              // Once a chunk misses its window, every later one waits with it,
              // so the text never lands out of order.
              if dry() {
                tracing::info!("dry live insert {text:?}");
                inserted = true;
                continue;
              }
              if failed || !stranded.is_empty() || !still_focused(target.as_ref()) {
                stranded.push_str(&text);
                continue;
              }
              if restore && previous.is_none() {
                previous = Some(snapshot());
              }
              if let Some(at) = last_paste {
                std::thread::sleep(PASTE_SETTLE.saturating_sub(at.elapsed()));
              }
              let is_terminal = target.as_ref().is_some_and(|window| window.is_terminal);
              let pasted = put_on_clipboard(&text, restore).and_then(|()| {
                std::thread::sleep(Duration::from_millis(30));
                hyprland::press_paste(is_terminal)
              });
              match pasted {
                Ok(()) => {
                  inserted = true;
                  last_paste = Some(Instant::now());
                }
                Err(error) => {
                  tracing::error!("live paste failed: {error:#}");
                  failed = true;
                  stranded.push_str(&text);
                }
              }
            }
            LiveCmd::Finish { enter } => {
              if enter && inserted && stranded.is_empty() && !dry() {
                std::thread::sleep(ENTER_AFTER);
                if let Err(error) = hyprland::press_enter() {
                  tracing::warn!("spoken send: {error:#}");
                }
              } else if enter && dry() {
                tracing::info!("dry live insert: enter");
              }
              break;
            }
          }
        }
        if stranded.is_empty() {
          done(Outcome {
            inserted,
            note: String::new(),
          });
          if let Some(previous) = previous {
            std::thread::sleep(RESTORE_AFTER);
            restore_if_unchanged(previous);
          }
        } else {
          let copied = put_on_clipboard(stranded.trim_start(), false).is_ok();
          let note = match (failed, copied) {
            (_, false) => "Could not copy the rest".into(),
            (true, true) => "Could not paste, copied the rest".into(),
            (false, true) => "Focus moved, copied the rest".into(),
          };
          done(Outcome { inserted, note });
        }
      })
      .expect("spawn live insertion thread");
    Self { commands }
  }

  pub fn chunk(&self, text: String) {
    let _ = self.commands.send(LiveCmd::Chunk(text));
  }

  pub fn finish(&self, enter: bool) {
    let _ = self.commands.send(LiveCmd::Finish { enter });
  }
}

fn still_focused(target: Option<&Target>) -> bool {
  match (target, hyprland::active_window()) {
    (Some(target), Some(focused)) => target.address == focused.address,
    (Some(_), None) => false,
    (None, _) => true,
  }
}

fn paste(text: &str, is_terminal: bool, restore: bool) -> anyhow::Result<()> {
  let previous = if restore { snapshot() } else { Vec::new() };
  // Only a write that is put back afterwards is transient; with `both` the
  // text stays, so it is an ordinary copy the history may keep.
  put_on_clipboard(text, restore)?;
  // Let the compositor announce the new selection before the paste asks
  // for it.
  std::thread::sleep(Duration::from_millis(30));
  hyprland::press_paste(is_terminal)?;
  // The session is over once the paste is sent; the restore must not hold
  // up the next one.
  if restore {
    std::thread::spawn(move || {
      std::thread::sleep(RESTORE_AFTER);
      restore_if_unchanged(previous);
    });
  }
  Ok(())
}

/// Puts text on the clipboard as an ordinary copy (Copy again).
pub fn copy(text: &str) -> anyhow::Result<()> {
  if dry() {
    tracing::info!("dry copy {text:?}");
    return Ok(());
  }
  put_on_clipboard(text, false)
}

/// The primary selection: the text selected anywhere right now, which is
/// what Teach learns from.
/// In the end-to-end tests the file named by `TALKIFY_TEST_SELECTION_FILE`
/// stands in for it, so they never touch the user's selection.
pub fn primary_selection() -> Option<String> {
  if let Some(path) = std::env::var_os("TALKIFY_TEST_SELECTION_FILE") {
    let fake = std::fs::read_to_string(path).unwrap_or_default();
    return (!fake.trim().is_empty()).then(|| fake.trim().to_string());
  }
  let (mut pipe, _) = paste::get_contents(
    paste::ClipboardType::Primary,
    Seat::Unspecified,
    paste::MimeType::Text,
  )
  .ok()?;
  let mut text = String::new();
  pipe.read_to_string(&mut text).ok()?;
  (!text.trim().is_empty()).then_some(text)
}

fn type_text(text: &str) -> anyhow::Result<()> {
  let status = Command::new("wtype")
    .arg("--")
    .arg(text)
    .status()
    .context("run wtype")?;
  if !status.success() {
    return Err(anyhow!("wtype exited with {status}"));
  }
  Ok(())
}

/// `transient` marks the write as Talkify's own, so the restore can tell
/// whether anyone replaced it, and asks clipboard histories to skip it.
fn put_on_clipboard(text: &str, transient: bool) -> anyhow::Result<()> {
  let mut sources = vec![MimeSource {
    source: Source::Bytes(text.as_bytes().into()),
    mime_type: MimeType::Text,
  }];
  if transient {
    sources.push(specific(PASSWORD_MANAGER_HINT, b"secret"));
    sources.push(specific(TRANSIENT_MARKER, b"1"));
  }
  let mut options = copy::Options::new();
  options.clipboard(copy::ClipboardType::Regular);
  options
    .copy_multi(sources)
    .map_err(|error| anyhow!("{error}"))
}

fn specific(mime: &str, bytes: &[u8]) -> MimeSource {
  MimeSource {
    source: Source::Bytes(bytes.into()),
    mime_type: MimeType::Specific(mime.into()),
  }
}

/// Every type the current clipboard offers, read in full, so images and
/// rich text survive the round trip, not just plain text.
fn snapshot() -> Vec<(String, Vec<u8>)> {
  let Ok(types) = paste::get_mime_types_ordered(paste::ClipboardType::Regular, Seat::Unspecified)
  else {
    return Vec::new();
  };
  let mut total = 0;
  let mut items = Vec::new();
  for mime in types {
    let Ok((mut pipe, _)) = paste::get_contents(
      paste::ClipboardType::Regular,
      Seat::Unspecified,
      paste::MimeType::Specific(&mime),
    ) else {
      continue;
    };
    let mut bytes = Vec::new();
    if pipe.read_to_end(&mut bytes).is_err() {
      continue;
    }
    total += bytes.len();
    if total > SNAPSHOT_LIMIT {
      tracing::warn!("clipboard too large to restore, keeping what fit");
      break;
    }
    items.push((mime, bytes));
  }
  items
}

fn restore_if_unchanged(previous: Vec<(String, Vec<u8>)>) {
  let still_ours = paste::get_mime_types(paste::ClipboardType::Regular, Seat::Unspecified)
    .is_ok_and(|types| types.contains(TRANSIENT_MARKER));
  if !still_ours {
    return;
  }
  if previous.is_empty() {
    let _ = copy::clear(copy::ClipboardType::Regular, copy::Seat::All);
    return;
  }
  let sources = previous
    .into_iter()
    .map(|(mime, bytes)| MimeSource {
      source: Source::Bytes(bytes.into()),
      mime_type: MimeType::Specific(mime),
    })
    .collect();
  let mut options = copy::Options::new();
  options.clipboard(copy::ClipboardType::Regular);
  if let Err(error) = options.copy_multi(sources) {
    tracing::warn!("could not restore the clipboard: {error}");
  }
}
