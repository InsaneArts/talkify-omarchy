//! The two things Talkify asks Hyprland: which window has focus, and to
//! press the paste shortcut in it.

use std::process::Command;

use anyhow::{Context, bail};
use serde::Deserialize;

/// The window a session will insert into, captured when it starts.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Target {
  pub address: String,
  pub class: String,
  /// Omarchy tags every terminal; they paste with Shift+Insert.
  pub is_terminal: bool,
}

#[derive(Deserialize)]
struct ActiveWindow {
  address: Option<String>,
  class: Option<String>,
  #[serde(default)]
  tags: Vec<String>,
}

/// In the end-to-end tests the file named by `TALKIFY_TEST_WINDOW_FILE`
/// stands in for the focused window (`class`, or `class terminal`), so they
/// never depend on where the user's focus happens to be.
fn test_window() -> Option<Option<Target>> {
  let path = std::env::var_os("TALKIFY_TEST_WINDOW_FILE")?;
  let text = std::fs::read_to_string(path).unwrap_or_default();
  let mut parts = text.split_whitespace();
  Some(parts.next().map(|class| Target {
    address: format!("0xtest-{class}"),
    class: class.to_string(),
    is_terminal: parts.next() == Some("terminal"),
  }))
}

pub fn active_window() -> Option<Target> {
  if let Some(window) = test_window() {
    return window;
  }
  let output = Command::new("hyprctl")
    .args(["activewindow", "-j"])
    .output()
    .ok()?;
  let window: ActiveWindow = serde_json::from_slice(&output.stdout).ok()?;
  Some(Target {
    address: window.address?,
    class: window.class.unwrap_or_default(),
    is_terminal: window
      .tags
      .iter()
      .any(|tag| tag.trim_end_matches('*') == "terminal"),
  })
}

/// Presses the paste shortcut in the focused window the way Omarchy's own
/// universal paste does: by keycode, because key names resolve against the
/// active layout (with Georgian active, "V" does not exist), and as a
/// separate down and up, because one `send_shortcut` can leave the synthetic
/// key stuck.
pub fn press_paste(is_terminal: bool) -> anyhow::Result<()> {
  // xkb keycodes: V is 55, Insert is 118.
  if is_terminal {
    press("SHIFT", 118)
  } else {
    press("CTRL", 55)
  }
}

/// Enter, for a spoken send. Return is xkb keycode 36.
pub fn press_enter() -> anyhow::Result<()> {
  press("", 36)
}

fn press(mods: &str, keycode: u32) -> anyhow::Result<()> {
  let key = format!("code:{keycode}");
  let lua = format!(
    r#"hl.dispatch(hl.dsp.send_key_state({{ mods = "{mods}", key = "{key}", state = "down" }}))
hl.timer(function()
  hl.dispatch(hl.dsp.send_key_state({{ mods = "{mods}", key = "{key}", state = "up" }}))
end, {{ timeout = 50, type = "oneshot" }})"#
  );
  let output = Command::new("hyprctl")
    .arg("eval")
    .arg(lua)
    .output()
    .context("run hyprctl")?;
  let reply = String::from_utf8_lossy(&output.stdout);
  if !output.status.success() || reply.to_lowercase().contains("error") {
    bail!("hyprctl eval: {}", reply.trim());
  }
  Ok(())
}
