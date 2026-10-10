//! Tells a Dictation Trigger gesture apart from a chord that merely starts
//! with the same key.
//!
//! On the Mac, Talkify's trigger is Fn, which nobody chords, so a press is a
//! press. Here the trigger is usually Right Super, which is also Cmd: every
//! Super+C goes through the same key. So a press is held back until either
//! the key has been down alone for `guard`, or it comes back up alone (a
//! tap). Any other key or button going down in between makes it a chord,
//! and the session never hears about it.
//!
//! Pure like the session machine: instants ride in on calls, and the daemon
//! asks `deadline()` when to call `tick`.

use std::time::{Duration, Instant};

/// How long a modifier trigger must be held alone before dictation starts.
pub const DEFAULT_GUARD: Duration = Duration::from_millis(150);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum KeyInput {
  TriggerDown,
  TriggerUp,
  /// Any other key or button going down. Autorepeat never reaches here.
  OtherKeyDown,
  EscapeDown,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum GuardOutput {
  /// The trigger was pressed at `at`, which is when the key went down, not
  /// when the guard let it through, so the tap threshold measures the real
  /// hold.
  Pressed {
    at: Instant,
  },
  Released {
    at: Instant,
  },
  Escape,
  /// A chord broke a hold that had already started a session.
  ChordCancel,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Phase {
  Up,
  Pending { since: Instant },
  Held,
  Chorded,
}

#[derive(Debug)]
pub struct ChordGuard {
  phase: Phase,
  guard: Duration,
}

impl ChordGuard {
  pub fn new(guard: Duration) -> Self {
    Self {
      phase: Phase::Up,
      guard,
    }
  }

  /// When `tick` should run next, if a press is waiting on the guard.
  pub fn deadline(&self) -> Option<Instant> {
    match self.phase {
      Phase::Pending { since } => Some(since + self.guard),
      _ => None,
    }
  }

  pub fn tick(&mut self, now: Instant) -> Vec<GuardOutput> {
    match self.phase {
      Phase::Pending { since } if now >= since + self.guard => {
        self.phase = Phase::Held;
        vec![GuardOutput::Pressed { at: since }]
      }
      _ => vec![],
    }
  }

  pub fn key(&mut self, input: KeyInput, now: Instant) -> Vec<GuardOutput> {
    match (input, self.phase) {
      (KeyInput::TriggerDown, Phase::Up) => {
        if self.guard.is_zero() {
          self.phase = Phase::Held;
          return vec![GuardOutput::Pressed { at: now }];
        }
        self.phase = Phase::Pending { since: now };
        vec![]
      }
      (KeyInput::TriggerDown, _) => vec![],

      (KeyInput::TriggerUp, Phase::Pending { since }) => {
        self.phase = Phase::Up;
        vec![
          GuardOutput::Pressed { at: since },
          GuardOutput::Released { at: now },
        ]
      }
      (KeyInput::TriggerUp, Phase::Held) => {
        self.phase = Phase::Up;
        vec![GuardOutput::Released { at: now }]
      }
      (KeyInput::TriggerUp, _) => {
        self.phase = Phase::Up;
        vec![]
      }

      (KeyInput::OtherKeyDown, Phase::Pending { .. }) => {
        self.phase = Phase::Chorded;
        vec![]
      }
      (KeyInput::OtherKeyDown, Phase::Held) => {
        self.phase = Phase::Chorded;
        vec![GuardOutput::ChordCancel]
      }
      (KeyInput::OtherKeyDown, _) => vec![],

      (KeyInput::EscapeDown, Phase::Pending { .. } | Phase::Held) => {
        self.phase = Phase::Chorded;
        vec![GuardOutput::Escape]
      }
      (KeyInput::EscapeDown, _) => vec![GuardOutput::Escape],
    }
  }
}

impl Default for ChordGuard {
  fn default() -> Self {
    Self::new(DEFAULT_GUARD)
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  fn ms(base: Instant, millis: u64) -> Instant {
    base + Duration::from_millis(millis)
  }

  #[test]
  fn a_lone_hold_presses_once_the_guard_passes_and_releases_on_key_up() {
    let t = Instant::now();
    let mut g = ChordGuard::default();
    assert!(g.key(KeyInput::TriggerDown, t).is_empty());
    assert_eq!(g.deadline(), Some(ms(t, 150)));
    assert!(g.tick(ms(t, 100)).is_empty());
    assert_eq!(g.tick(ms(t, 150)), vec![GuardOutput::Pressed { at: t }]);
    assert_eq!(g.deadline(), None);
    assert_eq!(
      g.key(KeyInput::TriggerUp, ms(t, 2000)),
      vec![GuardOutput::Released { at: ms(t, 2000) }]
    );
  }

  #[test]
  fn a_lone_tap_presses_and_releases_together() {
    let t = Instant::now();
    let mut g = ChordGuard::default();
    g.key(KeyInput::TriggerDown, t);
    assert_eq!(
      g.key(KeyInput::TriggerUp, ms(t, 90)),
      vec![
        GuardOutput::Pressed { at: t },
        GuardOutput::Released { at: ms(t, 90) }
      ]
    );
  }

  #[test]
  fn a_chord_inside_the_guard_never_reaches_the_session() {
    let t = Instant::now();
    let mut g = ChordGuard::default();
    g.key(KeyInput::TriggerDown, t);
    assert!(g.key(KeyInput::OtherKeyDown, ms(t, 60)).is_empty());
    assert!(g.tick(ms(t, 500)).is_empty());
    assert!(g.key(KeyInput::TriggerUp, ms(t, 600)).is_empty());
  }

  #[test]
  fn a_chord_after_the_guard_cancels_the_session_it_started() {
    let t = Instant::now();
    let mut g = ChordGuard::default();
    g.key(KeyInput::TriggerDown, t);
    g.tick(ms(t, 150));
    assert_eq!(
      g.key(KeyInput::OtherKeyDown, ms(t, 400)),
      vec![GuardOutput::ChordCancel]
    );
    assert!(g.key(KeyInput::TriggerUp, ms(t, 500)).is_empty());
  }

  #[test]
  fn escape_cancels_from_anywhere_and_swallows_the_pending_press() {
    let t = Instant::now();
    let mut g = ChordGuard::default();
    assert_eq!(g.key(KeyInput::EscapeDown, t), vec![GuardOutput::Escape]);
    g.key(KeyInput::TriggerDown, ms(t, 10));
    assert_eq!(
      g.key(KeyInput::EscapeDown, ms(t, 20)),
      vec![GuardOutput::Escape]
    );
    assert!(g.key(KeyInput::TriggerUp, ms(t, 30)).is_empty());
  }

  #[test]
  fn other_keys_with_the_trigger_up_change_nothing() {
    let t = Instant::now();
    let mut g = ChordGuard::default();
    assert!(g.key(KeyInput::OtherKeyDown, t).is_empty());
    assert!(g.key(KeyInput::TriggerUp, t).is_empty());
    g.key(KeyInput::TriggerDown, ms(t, 10));
    assert_eq!(
      g.key(KeyInput::TriggerUp, ms(t, 50)),
      vec![
        GuardOutput::Pressed { at: ms(t, 10) },
        GuardOutput::Released { at: ms(t, 50) }
      ]
    );
  }

  #[test]
  fn a_zero_guard_presses_immediately_for_non_modifier_triggers() {
    let t = Instant::now();
    let mut g = ChordGuard::new(Duration::ZERO);
    assert_eq!(
      g.key(KeyInput::TriggerDown, t),
      vec![GuardOutput::Pressed { at: t }]
    );
    assert_eq!(g.deadline(), None);
  }
}
