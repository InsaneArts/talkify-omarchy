//! Where Talkify keeps things, following the XDG base directories.
//!
//! `TALKIFY_SOCKET`, `TALKIFY_CONFIG_DIR` and `TALKIFY_DATA_DIR` move a
//! daemon somewhere else entirely, which is how the end-to-end tests run a
//! second daemon beside the user's without touching it.

use std::path::PathBuf;

fn env_path(var: &str) -> Option<PathBuf> {
  std::env::var_os(var)
    .filter(|v| !v.is_empty())
    .map(PathBuf::from)
}

fn env_dir(var: &str, fallback: &str) -> PathBuf {
  env_path(var).unwrap_or_else(|| {
    let home = std::env::var_os("HOME")
      .map(PathBuf::from)
      .unwrap_or_default();
    home.join(fallback)
  })
}

pub fn socket() -> PathBuf {
  env_path("TALKIFY_SOCKET").unwrap_or_else(|| {
    let runtime = std::env::var_os("XDG_RUNTIME_DIR")
      .map(PathBuf::from)
      .unwrap_or_else(|| PathBuf::from(format!("/run/user/{}", current_uid())));
    runtime.join("talkify.sock")
  })
}

pub fn config_dir() -> PathBuf {
  env_path("TALKIFY_CONFIG_DIR")
    .unwrap_or_else(|| env_dir("XDG_CONFIG_HOME", ".config").join("talkify"))
}

pub fn config_file() -> PathBuf {
  config_dir().join("config.toml")
}

/// The vocabulary: preferred words, corrections, snippets.
pub fn words_file() -> PathBuf {
  config_dir().join("words.txt")
}

pub fn data_dir() -> PathBuf {
  env_path("TALKIFY_DATA_DIR")
    .unwrap_or_else(|| env_dir("XDG_DATA_HOME", ".local/share").join("talkify"))
}

pub fn models_dir() -> PathBuf {
  data_dir().join("models")
}

pub fn sounds_dir() -> PathBuf {
  data_dir().join("sounds")
}

/// Insights' daily aggregates.
pub fn usage_file() -> PathBuf {
  data_dir().join("usage.json")
}

/// Saved dictations, one file per day, when history saving is on.
pub fn history_dir() -> PathBuf {
  data_dir().join("history")
}

fn current_uid() -> u32 {
  std::fs::read_to_string("/proc/self/status")
    .ok()
    .and_then(|status| {
      status.lines().find_map(|line| {
        line
          .strip_prefix("Uid:")
          .and_then(|rest| rest.split_whitespace().next()?.parse().ok())
      })
    })
    .unwrap_or(1000)
}
