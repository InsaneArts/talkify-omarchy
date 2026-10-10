//! Watches every input device and reports each key and button going down or
//! up. The daemon decides what they mean: the Dictation Trigger, Escape, or
//! any other key (which makes a held trigger a chord).
//!
//! It only listens and never grabs, so every key still reaches the focused
//! app, and a chord like Super+C still works. That needs read access to
//! `/dev/input`, which on Arch means the `input` group; without it the
//! daemon falls back to `press`/`release`/`toggle` commands from compositor
//! binds.

use std::collections::HashSet;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::{Duration, Instant};

use crossbeam_channel::Sender;
use evdev::{EventSummary, KeyCode};
use talkify_core::protocol::TriggerSource;

use super::Msg;

/// KEY_ESC.
pub const ESCAPE: u16 = 1;

/// A Linux input key or button name (`KEY_RIGHTMETA`, `BTN_SIDE`) as its
/// code; None for "" or an unknown name.
pub fn key_code(name: &str) -> Option<u16> {
  if name.trim().is_empty() {
    return None;
  }
  name.trim().parse::<KeyCode>().ok().map(|key| key.code())
}

/// Mouse buttons are never chorded, so they need no chord guard.
pub fn is_button(name: &str) -> bool {
  name.trim().starts_with("BTN_")
}

pub fn start(tx: Sender<Msg>) -> TriggerSource {
  if !can_read_input() {
    tracing::warn!(
      "cannot read /dev/input (add yourself to the input group); the trigger needs \
       press/release/toggle commands"
    );
    return TriggerSource::Commands;
  }
  std::thread::Builder::new()
    .name("keyboard-scan".into())
    .spawn(move || scan_forever(tx))
    .expect("spawn keyboard scanner");
  TriggerSource::Keyboard
}

fn can_read_input() -> bool {
  let Ok(entries) = std::fs::read_dir("/dev/input") else {
    return false;
  };
  entries.flatten().any(|entry| {
    entry.file_name().to_string_lossy().starts_with("event")
      && std::fs::File::open(entry.path()).is_ok()
  })
}

/// Devices come and go (a keyboard plugged in, a mouse waking up), so the
/// scanner looks again every couple of seconds and starts a reader for
/// anything new. A reader that errors out drops its path so a replugged
/// device gets picked up again.
fn scan_forever(tx: Sender<Msg>) {
  let open: Arc<std::sync::Mutex<HashSet<PathBuf>>> = Default::default();
  loop {
    for (path, device) in evdev::enumerate() {
      let has_keys = device
        .supported_keys()
        .is_some_and(|keys| keys.iter().next().is_some());
      if !has_keys || !open.lock().unwrap().insert(path.clone()) {
        continue;
      }
      tracing::debug!(
        "listening to {} ({})",
        device.name().unwrap_or("?"),
        path.display()
      );
      let (tx, open) = (tx.clone(), open.clone());
      let spawned = std::thread::Builder::new()
        .name("keyboard".into())
        .spawn(move || {
          read_device(device, &tx);
          open.lock().unwrap().remove(&path);
        });
      if spawned.is_err() {
        tracing::warn!("could not start a keyboard reader");
      }
    }
    std::thread::sleep(Duration::from_secs(2));
  }
}

fn read_device(mut device: evdev::Device, tx: &Sender<Msg>) {
  loop {
    let Ok(events) = device.fetch_events() else {
      return;
    };
    for event in events {
      let EventSummary::Key(_, code, value) = event.destructure() else {
        continue;
      };
      // 2 is autorepeat: the key is still the same press.
      let down = match value {
        1 => true,
        0 => false,
        _ => continue,
      };
      if tx
        .send(Msg::Key {
          code: code.code(),
          down,
          at: Instant::now(),
        })
        .is_err()
      {
        return;
      }
    }
  }
}
