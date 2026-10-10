//! The recent dictations Paste again and Retry reach. Kept in memory; only
//! the newest few keep their audio, about 700 KB per eleven seconds.

use std::collections::VecDeque;

use crate::protocol::HistoryItem;

/// How many of the newest dictations keep their audio for Retry.
pub const KEEP_AUDIO: usize = 5;

#[derive(Debug)]
pub struct Entry {
  pub item: HistoryItem,
  pub audio: Option<Vec<f32>>,
}

#[derive(Debug)]
pub struct History {
  entries: VecDeque<Entry>,
  next_id: u64,
  size: usize,
}

/// What a finished session leaves behind.
pub struct Record {
  pub at: i64,
  pub app: String,
  pub text: String,
  pub raw: String,
  pub seconds: f32,
  pub inserted: bool,
  pub rule: String,
  pub audio: Option<Vec<f32>>,
}

impl History {
  pub fn new(size: usize) -> Self {
    Self {
      entries: VecDeque::new(),
      next_id: 1,
      size: size.max(1),
    }
  }

  pub fn resize(&mut self, size: usize) {
    self.size = size.max(1);
    self.entries.truncate(self.size);
  }

  pub fn push(&mut self, record: Record) -> u64 {
    let id = self.next_id;
    self.next_id += 1;
    let words = crate::insights::word_count(&record.text) as usize;
    self.entries.push_front(Entry {
      item: HistoryItem {
        id,
        at: record.at,
        app: record.app,
        text: record.text,
        raw: record.raw,
        words,
        seconds: record.seconds,
        inserted: record.inserted,
        retryable: record.audio.is_some(),
        rule: record.rule,
      },
      audio: record.audio,
    });
    for entry in self.entries.iter_mut().skip(KEEP_AUDIO) {
      entry.audio = None;
      entry.item.retryable = false;
    }
    self.entries.truncate(self.size);
    id
  }

  pub fn get(&self, index: usize) -> Option<&Entry> {
    self.entries.get(index)
  }

  pub fn latest(&self) -> Option<&Entry> {
    self.entries.front()
  }

  pub fn items(&self) -> Vec<HistoryItem> {
    self
      .entries
      .iter()
      .map(|entry| entry.item.clone())
      .collect()
  }

  pub fn clear(&mut self) {
    self.entries.clear();
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  fn record(text: &str, audio: bool) -> Record {
    Record {
      at: 0,
      app: "foot".into(),
      text: text.into(),
      raw: text.into(),
      seconds: 1.0,
      inserted: true,
      rule: String::new(),
      audio: audio.then(|| vec![0.0; 16]),
    }
  }

  #[test]
  fn newest_first_with_stable_ids_and_word_counts() {
    let mut history = History::new(10);
    history.push(record("first one", true));
    let id = history.push(record("second, longer one.", true));
    let items = history.items();
    assert_eq!(items[0].id, id);
    assert_eq!(items[0].text, "second, longer one.");
    assert_eq!(items[0].words, 3);
    assert_eq!(items[1].text, "first one");
  }

  #[test]
  fn only_the_newest_keep_their_audio_and_the_size_is_capped() {
    let mut history = History::new(7);
    for index in 0..9 {
      history.push(record(&format!("dictation {index}"), true));
    }
    let items = history.items();
    assert_eq!(items.len(), 7);
    assert_eq!(
      items.iter().filter(|item| item.retryable).count(),
      KEEP_AUDIO
    );
    assert!(items[0].retryable && !items[6].retryable);
    assert!(history.get(KEEP_AUDIO).unwrap().audio.is_none());
  }

  #[test]
  fn resizing_and_clearing() {
    let mut history = History::new(5);
    for index in 0..5 {
      history.push(record(&format!("d{index}"), false));
    }
    history.resize(2);
    assert_eq!(history.items().len(), 2);
    history.clear();
    assert!(history.latest().is_none());
  }
}
