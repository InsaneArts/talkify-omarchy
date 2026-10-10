//! Insights: local usage metrics, a port of the Mac app's `UsageMetrics`
//! with its rules and its tests.
//!
//! Only aggregates are kept: per day, words, speaking time and sessions.
//! Never text, never app names. Weeks start on Monday.

use chrono::{Datelike, Duration, NaiveDate};
use serde::{Deserialize, Serialize};

const WORD_MILESTONES: &[u64] = &[
  100, 1_000, 5_000, 10_000, 25_000, 50_000, 100_000, 250_000, 500_000, 1_000_000,
];
const STREAK_MILESTONES: &[u64] = &[3, 7, 14, 30, 60, 100, 200, 365];
const SESSION_MILESTONES: &[u64] = &[10, 50, 100, 500, 1_000, 5_000, 10_000];

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct DailyUsage {
  /// `YYYY-MM-DD`, local time.
  pub day: String,
  pub words: u64,
  pub seconds: f64,
  pub sessions: u64,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Milestone {
  pub kind: String,
  pub value: u64,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct UsageDocument {
  pub version: u32,
  pub days: Vec<DailyUsage>,
  /// Milestones already celebrated, so each one is celebrated once.
  #[serde(default)]
  pub milestones: Vec<Milestone>,
}

impl Default for UsageDocument {
  fn default() -> Self {
    Self {
      version: 1,
      days: Vec::new(),
      milestones: Vec::new(),
    }
  }
}

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Summary {
  pub total_words: u64,
  pub sessions: u64,
  pub speaking_seconds: f64,
  /// Weighted: all words over all speaking time, not a mean of means.
  pub wpm: f64,
  pub words_per_session: f64,
  pub current_streak: u64,
  pub longest_streak: u64,
}

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Momentum {
  pub current_words: u64,
  pub previous_words: u64,
  pub active_days: u64,
  pub sessions: u64,
  /// Relative change, None when the previous week had no words.
  pub change: Option<f64>,
}

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct HeatDay {
  pub day: String,
  pub words: u64,
  pub future: bool,
}

/// Words in a text: runs of characters with a letter or digit, so
/// punctuation and whitespace never count.
pub fn word_count(text: &str) -> u64 {
  text
    .split(|c: char| c.is_whitespace())
    .filter(|token| token.chars().any(char::is_alphanumeric))
    .count() as u64
}

fn parse(day: &str) -> Option<NaiveDate> {
  NaiveDate::parse_from_str(day, "%Y-%m-%d").ok()
}

pub fn key(day: NaiveDate) -> String {
  day.format("%Y-%m-%d").to_string()
}

impl UsageDocument {
  fn totals(&self) -> std::collections::BTreeMap<NaiveDate, (u64, u64)> {
    let mut totals = std::collections::BTreeMap::new();
    for usage in &self.days {
      if let Some(day) = parse(&usage.day) {
        let entry = totals.entry(day).or_insert((0, 0));
        entry.0 += usage.words;
        entry.1 += usage.sessions;
      }
    }
    totals
  }

  /// Adds one finished session and returns the milestones it reached for
  /// the first time (the highest of each kind).
  pub fn record(&mut self, today: NaiveDate, words: u64, seconds: f64) -> Vec<Milestone> {
    let day = key(today);
    match self.days.iter_mut().find(|usage| usage.day == day) {
      Some(usage) => {
        usage.words += words;
        usage.seconds += seconds.max(0.0);
        usage.sessions += 1;
      }
      None => self.days.push(DailyUsage {
        day,
        words,
        seconds: seconds.max(0.0),
        sessions: 1,
      }),
    }
    let summary = self.summary(today);
    let mut reached = Vec::new();
    for (kind, value, thresholds) in [
      ("words", summary.total_words, WORD_MILESTONES),
      ("streak", summary.current_streak, STREAK_MILESTONES),
      ("sessions", summary.sessions, SESSION_MILESTONES),
    ] {
      let newly = thresholds
        .iter()
        .copied()
        .filter(|threshold| value >= *threshold)
        .filter(|threshold| {
          !self
            .milestones
            .iter()
            .any(|milestone| milestone.kind == kind && milestone.value == *threshold)
        })
        .collect::<Vec<_>>();
      for threshold in &newly {
        self.milestones.push(Milestone {
          kind: kind.into(),
          value: *threshold,
        });
      }
      if let Some(highest) = newly.last() {
        reached.push(Milestone {
          kind: kind.into(),
          value: *highest,
        });
      }
    }
    reached
  }

  pub fn summary(&self, today: NaiveDate) -> Summary {
    let total_words: u64 = self.days.iter().map(|usage| usage.words).sum();
    let sessions: u64 = self.days.iter().map(|usage| usage.sessions).sum();
    let speaking_seconds: f64 = self.days.iter().map(|usage| usage.seconds.max(0.0)).sum();
    let (current_streak, longest_streak) = self.streaks(today);
    Summary {
      total_words,
      sessions,
      speaking_seconds,
      wpm: if speaking_seconds > 0.0 {
        total_words as f64 / (speaking_seconds / 60.0)
      } else {
        0.0
      },
      words_per_session: if sessions > 0 {
        total_words as f64 / sessions as f64
      } else {
        0.0
      },
      current_streak,
      longest_streak,
    }
  }

  /// The last `count` days through today, inactive ones included.
  pub fn timeline(&self, today: NaiveDate, count: i64) -> Vec<(NaiveDate, u64, u64)> {
    let totals = self.totals();
    (0..count)
      .map(|index| {
        let day = today - Duration::days(count - 1 - index);
        let (words, sessions) = totals.get(&day).copied().unwrap_or((0, 0));
        (day, words, sessions)
      })
      .collect()
  }

  /// This rolling week against the one before it.
  pub fn momentum(&self, today: NaiveDate) -> Momentum {
    let days = self.timeline(today, 14);
    let (previous, current) = days.split_at(7);
    let current_words = current.iter().map(|day| day.1).sum();
    let previous_words: u64 = previous.iter().map(|day| day.1).sum();
    Momentum {
      current_words,
      previous_words,
      active_days: current.iter().filter(|day| day.1 > 0).count() as u64,
      sessions: current.iter().map(|day| day.2).sum(),
      change: (previous_words > 0)
        .then(|| (current_words as f64 - previous_words as f64) / previous_words as f64),
    }
  }

  /// `weeks` calendar weeks ending with this one, Monday first.
  pub fn heatmap(&self, today: NaiveDate, weeks: i64) -> Vec<HeatDay> {
    let totals = self.totals();
    let this_monday = today - Duration::days(today.weekday().num_days_from_monday() as i64);
    let first = this_monday - Duration::weeks(weeks - 1);
    (0..weeks * 7)
      .map(|offset| {
        let day = first + Duration::days(offset);
        HeatDay {
          day: key(day),
          words: totals.get(&day).map_or(0, |total| total.0),
          future: day > today,
        }
      })
      .collect()
  }

  fn streaks(&self, today: NaiveDate) -> (u64, u64) {
    let active: std::collections::BTreeSet<NaiveDate> = self
      .days
      .iter()
      .filter(|usage| usage.sessions > 0 && usage.words > 0)
      .filter_map(|usage| parse(&usage.day))
      .collect();
    if active.is_empty() {
      return (0, 0);
    }
    let mut longest = 1;
    let mut run = 1;
    let mut previous: Option<NaiveDate> = None;
    for day in &active {
      if let Some(before) = previous {
        if *day == before + Duration::days(1) {
          run += 1;
          longest = longest.max(run);
        } else {
          run = 1;
        }
      }
      previous = Some(*day);
    }
    // A streak survives today until it is over: yesterday still counts.
    let start = if active.contains(&today) {
      Some(today)
    } else if active.contains(&(today - Duration::days(1))) {
      Some(today - Duration::days(1))
    } else {
      None
    };
    let mut current = 0;
    let mut cursor = start;
    while let Some(day) = cursor.filter(|day| active.contains(day)) {
      current += 1;
      cursor = Some(day - Duration::days(1));
    }
    (current, longest)
  }

  /// The `insights` event's payload (docs/protocol.md).
  pub fn snapshot(&self, today: NaiveDate, typing_wpm: u64) -> serde_json::Value {
    let summary = self.summary(today);
    let today_words = self
      .days
      .iter()
      .filter(|usage| usage.day == key(today))
      .map(|usage| usage.words)
      .sum::<u64>();
    // Time saved assumes the words would otherwise be typed at typing_wpm;
    // the UI states that assumption wherever it shows the number.
    let minutes_saved = if typing_wpm > 0 {
      (summary.total_words as f64 / typing_wpm as f64 - summary.speaking_seconds / 60.0).max(0.0)
    } else {
      0.0
    };
    serde_json::json!({
      "total_words": summary.total_words,
      "sessions": summary.sessions,
      "speaking_seconds": summary.speaking_seconds,
      "wpm": summary.wpm,
      "words_per_session": summary.words_per_session,
      "current_streak": summary.current_streak,
      "longest_streak": summary.longest_streak,
      "today_words": today_words,
      "momentum": self.momentum(today),
      "heatmap": self.heatmap(today, 16),
      "typing_wpm": typing_wpm,
      "minutes_saved": minutes_saved,
      "milestones": self.milestones,
    })
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  fn date(y: i32, m: u32, d: u32) -> NaiveDate {
    NaiveDate::from_ymd_opt(y, m, d).unwrap()
  }

  fn usage(day: NaiveDate, words: u64, seconds: f64, sessions: u64) -> DailyUsage {
    DailyUsage {
      day: key(day),
      words,
      seconds,
      sessions,
    }
  }

  fn document(days: Vec<DailyUsage>) -> UsageDocument {
    UsageDocument {
      days,
      ..UsageDocument::default()
    }
  }

  #[test]
  fn counts_words_without_counting_punctuation_or_whitespace() {
    assert_eq!(word_count("  Hello, world. Talkify works!  "), 4);
    assert_eq!(word_count(" \n\t "), 0);
    assert_eq!(word_count("well — fine"), 2);
  }

  #[test]
  fn summarizes_totals_and_weighted_speaking_speed() {
    let first = date(2026, 8, 8);
    let second = date(2026, 8, 9);
    let doc = document(vec![
      usage(first, 300, 120.0, 2),
      usage(second, 150, 60.0, 1),
    ]);
    let summary = doc.summary(second);
    assert_eq!(summary.total_words, 450);
    assert_eq!(summary.sessions, 3);
    assert_eq!(summary.speaking_seconds, 180.0);
    assert!((summary.wpm - 150.0).abs() < 0.001);
    assert!((summary.words_per_session - 150.0).abs() < 0.001);
  }

  #[test]
  fn calculates_current_and_longest_streaks() {
    let today = date(2026, 8, 9);
    let days = [-8, -7, -6, -5, -2, -1, 0]
      .iter()
      .map(|offset| usage(today + Duration::days(*offset), 20, 10.0, 1))
      .collect();
    let summary = document(days).summary(today);
    assert_eq!(summary.current_streak, 3);
    assert_eq!(summary.longest_streak, 4);
  }

  #[test]
  fn current_streak_expires_after_one_inactive_day() {
    let today = date(2026, 8, 9);
    let summary = document(vec![usage(today - Duration::days(2), 20, 10.0, 1)]).summary(today);
    assert_eq!(summary.current_streak, 0);
    assert_eq!(summary.longest_streak, 1);
  }

  #[test]
  fn heatmap_contains_sixteen_calendar_weeks_monday_first() {
    // Wednesday 12 August 2026.
    let today = date(2026, 8, 12);
    let heatmap = document(vec![usage(today, 25, 12.0, 1)]).heatmap(today, 16);
    assert_eq!(heatmap.len(), 112);
    assert_eq!(
      parse(&heatmap[0].day).unwrap().weekday(),
      chrono::Weekday::Mon
    );
    assert!(
      heatmap
        .iter()
        .any(|day| day.day == key(today) && day.words == 25 && !day.future)
    );
    assert_eq!(heatmap.iter().filter(|day| day.future).count(), 4);
  }

  #[test]
  fn timeline_includes_inactive_days_through_today() {
    let today = date(2026, 8, 14);
    let doc = document(vec![
      usage(today - Duration::days(3), 40, 20.0, 1),
      usage(today, 100, 40.0, 2),
    ]);
    let timeline = doc.timeline(today, 5);
    assert_eq!(
      timeline.iter().map(|day| day.1).collect::<Vec<_>>(),
      vec![0, 40, 0, 0, 100]
    );
    assert_eq!(
      timeline.iter().map(|day| day.2).collect::<Vec<_>>(),
      vec![0, 1, 0, 0, 2]
    );
    assert_eq!(timeline.last().unwrap().0, today);
  }

  #[test]
  fn momentum_compares_two_rolling_seven_day_periods() {
    let today = date(2026, 8, 14);
    let days = [(-9, 80), (-8, 20), (-2, 120), (0, 80)]
      .iter()
      .map(|(offset, words)| usage(today + Duration::days(*offset), *words, 30.0, 1))
      .collect();
    let momentum = document(days).momentum(today);
    assert_eq!(momentum.current_words, 200);
    assert_eq!(momentum.previous_words, 100);
    assert_eq!(momentum.active_days, 2);
    assert_eq!(momentum.sessions, 2);
    assert!((momentum.change.unwrap() - 1.0).abs() < 0.001);
  }

  #[test]
  fn recording_merges_into_the_day_and_reaches_milestones_once() {
    let today = date(2026, 8, 14);
    let mut doc = UsageDocument::default();
    assert!(doc.record(today, 40, 20.0).is_empty());
    let reached = doc.record(today, 70, 30.0);
    assert_eq!(
      reached,
      vec![Milestone {
        kind: "words".into(),
        value: 100
      }]
    );
    assert_eq!(doc.days.len(), 1);
    assert_eq!(doc.days[0].sessions, 2);
    // Already celebrated: not again.
    assert!(doc.record(today, 5, 2.0).is_empty());
  }

  #[test]
  fn a_jump_past_several_thresholds_celebrates_only_the_highest() {
    let mut doc = UsageDocument::default();
    let reached = doc.record(date(2026, 8, 14), 6_000, 2_400.0);
    assert_eq!(
      reached,
      vec![Milestone {
        kind: "words".into(),
        value: 5_000
      }]
    );
    assert_eq!(doc.milestones.len(), 3);
  }

  #[test]
  fn streak_milestones_follow_consecutive_days() {
    let mut doc = UsageDocument::default();
    let start = date(2026, 8, 1);
    doc.record(start, 10, 5.0);
    doc.record(start + Duration::days(1), 10, 5.0);
    let reached = doc.record(start + Duration::days(2), 10, 5.0);
    assert!(reached.contains(&Milestone {
      kind: "streak".into(),
      value: 3
    }));
  }

  #[test]
  fn the_snapshot_states_time_saved_against_its_typing_speed() {
    let today = date(2026, 8, 14);
    let doc = document(vec![usage(today, 400, 120.0, 4)]);
    let snapshot = doc.snapshot(today, 40);
    // 400 words typed at 40 wpm is 10 minutes; spoken in 2.
    assert!((snapshot["minutes_saved"].as_f64().unwrap() - 8.0).abs() < 0.001);
    assert_eq!(snapshot["today_words"], 400);
    assert_eq!(snapshot["heatmap"].as_array().unwrap().len(), 112);
  }
}
