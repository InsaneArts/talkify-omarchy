//! Quiets the room for a session: pauses the media players that are playing
//! (MPRIS, over D-Bus) or lowers the output, and puts back exactly what it
//! changed when the session ends, a player paused by the user stays paused.
//!
//! D-Bus and `wpctl` calls can take a moment, so a worker thread does them
//! and the session never waits.

use std::process::Command;

use crossbeam_channel::Sender;
use zbus::blocking::{Connection, Proxy, fdo::DBusProxy};

const MPRIS_PREFIX: &str = "org.mpris.MediaPlayer2.";
const MPRIS_PATH: &str = "/org/mpris/MediaPlayer2";
const PLAYER: &str = "org.mpris.MediaPlayer2.Player";

enum Cmd {
  Quiet { mode: String, duck_to: f64 },
  Restore,
}

#[derive(Clone)]
pub struct Media {
  commands: Sender<Cmd>,
}

impl Media {
  pub fn spawn() -> Self {
    let (commands, rx) = crossbeam_channel::unbounded::<Cmd>();
    std::thread::Builder::new()
      .name("media".into())
      .spawn(move || {
        let mut paused: Vec<String> = Vec::new();
        let mut volume: Option<f64> = None;
        for command in rx {
          match command {
            Cmd::Quiet { mode, duck_to } => match mode.as_str() {
              "pause" => paused = pause_playing(),
              "duck" => volume = duck(duck_to),
              _ => {}
            },
            Cmd::Restore => {
              for name in paused.drain(..) {
                if let Err(error) = call(&name, "Play") {
                  tracing::debug!("resume {name}: {error}");
                }
              }
              if let Some(level) = volume.take() {
                set_volume(level);
              }
            }
          }
        }
      })
      .expect("spawn media thread");
    Self { commands }
  }

  pub fn quiet(&self, mode: &str, duck_to: f64) {
    if mode == "pause" || mode == "duck" {
      let _ = self.commands.send(Cmd::Quiet {
        mode: mode.into(),
        duck_to,
      });
    }
  }

  pub fn restore(&self) {
    let _ = self.commands.send(Cmd::Restore);
  }
}

/// Which bus names count as players. `TALKIFY_TEST_MPRIS_PREFIX` narrows it
/// to a fake player, so the end-to-end tests never pause the user's music.
fn player_prefix() -> String {
  std::env::var("TALKIFY_TEST_MPRIS_PREFIX").unwrap_or_else(|_| MPRIS_PREFIX.into())
}

fn players(connection: &Connection) -> zbus::Result<Vec<String>> {
  let prefix = player_prefix();
  Ok(
    DBusProxy::new(connection)?
      .list_names()?
      .into_iter()
      .map(|name| name.to_string())
      .filter(|name| name.starts_with(&prefix))
      .collect(),
  )
}

/// Pauses every player that is playing and returns their names.
fn pause_playing() -> Vec<String> {
  let Ok(connection) = Connection::session() else {
    return Vec::new();
  };
  let mut paused = Vec::new();
  for name in players(&connection).unwrap_or_default() {
    let Ok(proxy) = Proxy::new(&connection, name.as_str(), MPRIS_PATH, PLAYER) else {
      continue;
    };
    let playing = proxy
      .get_property::<String>("PlaybackStatus")
      .is_ok_and(|status| status == "Playing");
    if playing && proxy.call_method("Pause", &()).is_ok() {
      tracing::debug!("paused {name}");
      paused.push(name.clone());
    }
  }
  paused
}

fn call(name: &str, method: &str) -> zbus::Result<()> {
  let connection = Connection::session()?;
  let proxy = Proxy::new(&connection, name, MPRIS_PATH, PLAYER)?;
  proxy.call_method(method, &())?;
  Ok(())
}

/// Lowers the default output to `duck_to` of where it is, returning where
/// it was.
fn duck(duck_to: f64) -> Option<f64> {
  let output = Command::new("wpctl")
    .args(["get-volume", "@DEFAULT_AUDIO_SINK@"])
    .output()
    .ok()?;
  let text = String::from_utf8_lossy(&output.stdout);
  let level: f64 = text.split_whitespace().nth(1)?.parse().ok()?;
  set_volume(level * duck_to.clamp(0.0, 1.0));
  Some(level)
}

fn set_volume(level: f64) {
  let _ = Command::new("wpctl")
    .args(["set-volume", "@DEFAULT_AUDIO_SINK@", &format!("{level:.3}")])
    .status();
}
