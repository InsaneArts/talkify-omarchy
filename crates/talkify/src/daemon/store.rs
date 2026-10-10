//! The daemon's files: the config, the vocabulary, Insights' aggregates,
//! and saved dictations. Every write goes to a temporary file first and is
//! renamed into place, so a crash never leaves half a file.

use std::path::Path;
use std::time::SystemTime;

use anyhow::Context;
use talkify_core::config::Config;
use talkify_core::insights::UsageDocument;
use talkify_core::vocab::Vocabulary;

use crate::paths;

fn write_atomically(path: &Path, contents: &str) -> anyhow::Result<()> {
  std::fs::create_dir_all(path.parent().context("path has a parent")?)?;
  let partial = path.with_extension("partial");
  std::fs::write(&partial, contents)?;
  std::fs::rename(&partial, path)?;
  Ok(())
}

pub fn load_config() -> Config {
  let path = paths::config_file();
  match std::fs::read_to_string(&path) {
    Ok(text) => Config::from_toml(&text).unwrap_or_else(|error| {
      tracing::error!("{}: {error}; using defaults", path.display());
      Config::default()
    }),
    Err(_) => {
      let config = Config::default();
      if let Err(error) = save_config(&config) {
        tracing::warn!("could not write {}: {error:#}", path.display());
      }
      config
    }
  }
}

pub fn save_config(config: &Config) -> anyhow::Result<()> {
  write_atomically(&paths::config_file(), &config.to_toml())
}

/// A few words Omarchy users say every day, so a fresh vocabulary already
/// gets them right.
const SEED_VOCABULARY: &str = "\
# Talkify vocabulary. One entry per line:
#   Hyprland                 a word to prefer, matched by sound and spelling
#   omachi -> Omarchy        a correction: heard, then written
#   my email => me@x.dev     a snippet: say the trigger, get the expansion
# `talkify teach` adds corrections here from a selected fix.
Omarchy
Hyprland
Quickshell
Walker
";

pub struct VocabFile {
  pub vocabulary: Vocabulary,
  pub hits: Vec<u32>,
  modified: Option<SystemTime>,
}

impl VocabFile {
  pub fn load() -> Self {
    let path = paths::words_file();
    if !path.exists()
      && let Err(error) = write_atomically(&path, SEED_VOCABULARY)
    {
      tracing::warn!("could not seed {}: {error:#}", path.display());
    }
    let text = std::fs::read_to_string(&path).unwrap_or_default();
    let vocabulary = Vocabulary::parse(&text);
    Self {
      hits: vec![0; vocabulary.entries.len()],
      vocabulary,
      modified: modified(&path),
    }
  }

  /// Reloads when the file changed on disk (edited by hand), keeping hit
  /// counts for lines that survived. True when it reloaded.
  pub fn refresh(&mut self) -> bool {
    if modified(&paths::words_file()) == self.modified {
      return false;
    }
    let old: Vec<(String, u32)> = self
      .vocabulary
      .entries
      .iter()
      .map(|entry| entry.line.clone())
      .zip(self.hits.iter().copied())
      .collect();
    *self = Self::load();
    for (entry, hits) in self.vocabulary.entries.iter().zip(self.hits.iter_mut()) {
      if let Some((_, count)) = old.iter().find(|(line, _)| *line == entry.line) {
        *hits = *count;
      }
    }
    true
  }

  pub fn record_hits(&mut self, indices: &[usize]) {
    for index in indices {
      if let Some(count) = self.hits.get_mut(*index) {
        *count += 1;
      }
    }
  }

  pub fn add(&mut self, line: &str) -> anyhow::Result<()> {
    let line = line.trim();
    anyhow::ensure!(!line.is_empty(), "empty line");
    let path = paths::words_file();
    let mut text = std::fs::read_to_string(&path).unwrap_or_default();
    if text.lines().any(|existing| existing.trim() == line) {
      return Ok(());
    }
    if !text.is_empty() && !text.ends_with('\n') {
      text.push('\n');
    }
    text.push_str(line);
    text.push('\n');
    write_atomically(&path, &text)?;
    self.refresh();
    Ok(())
  }

  pub fn remove(&mut self, line: &str) -> anyhow::Result<()> {
    let path = paths::words_file();
    let text = std::fs::read_to_string(&path).unwrap_or_default();
    let kept: Vec<&str> = text
      .lines()
      .filter(|existing| existing.trim() != line.trim())
      .collect();
    write_atomically(&path, &(kept.join("\n") + "\n"))?;
    self.refresh();
    Ok(())
  }
}

fn modified(path: &Path) -> Option<SystemTime> {
  std::fs::metadata(path)
    .and_then(|meta| meta.modified())
    .ok()
}

pub fn load_usage() -> UsageDocument {
  std::fs::read_to_string(paths::usage_file())
    .ok()
    .and_then(|text| serde_json::from_str(&text).ok())
    .unwrap_or_default()
}

pub fn save_usage(usage: &UsageDocument) -> anyhow::Result<()> {
  write_atomically(&paths::usage_file(), &serde_json::to_string(usage)?)
}

/// Appends a dictation to today's history file, when saving is on.
pub fn save_dictation(app: &str, text: &str) {
  let now = chrono::Local::now();
  let path = paths::history_dir().join(format!("{}.txt", now.format("%Y-%m-%d")));
  let line = format!(
    "{}\t{}\t{}\n",
    now.format("%H:%M:%S"),
    if app.is_empty() { "-" } else { app },
    text.replace('\n', " ")
  );
  let result = std::fs::create_dir_all(paths::history_dir()).and_then(|()| {
    use std::io::Write;
    std::fs::OpenOptions::new()
      .create(true)
      .append(true)
      .open(&path)?
      .write_all(line.as_bytes())
  });
  if let Err(error) = result {
    tracing::warn!("could not save to {}: {error}", path.display());
  }
}
