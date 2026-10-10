//! The Direct Dictation session as a pure reducer: actions in, state
//! transition inside, effects out. No clocks (instants ride in on actions),
//! no audio, no threads — which is what makes the gesture and race rules
//! (quick-tap latching, finish-queued-while-starting, cancel-while-starting,
//! the no-speech policy) testable without a microphone.
//!
//! A port of Talkify's `DictationSessionMachine`. The daemon owns the impure
//! half: it turns trigger events into actions, runs the begin guards, and
//! executes the returned effects against audio, the engine, the HUD stream
//! and insertion. Async completions come back as new actions.

use std::time::{Duration, Instant};

/// Releasing the Dictation Trigger before this counts as a quick tap and
/// latches the session.
pub const TAP_THRESHOLD: Duration = Duration::from_millis(250);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Gesture {
  Held { started_at: Instant },
  Latched,
}

impl Gesture {
  pub fn is_latched(self) -> bool {
    matches!(self, Gesture::Latched)
  }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum State {
  Idle,
  Starting(Gesture),
  Recording(Gesture),
  Finishing,
  Cancelling,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Action {
  TriggerPressed {
    now: Instant,
  },
  TriggerReleased {
    now: Instant,
  },
  /// The bar widget or `talkify toggle`: starts a latched session, or
  /// finishes the one in flight.
  Toggled {
    now: Instant,
  },
  EscapePressed,
  /// The begin guards (model loaded, microphone available) passed and the
  /// target window is captured.
  BeginApproved,
  BeginRejected,
  RecognitionStarted {
    now: Instant,
  },
  /// Recognition failed while starting, finishing, or mid-session.
  /// `was_cancelled` covers the torn-down start.
  RecognitionFailed {
    was_cancelled: bool,
  },
  UpdateReceived {
    has_visible_text: bool,
  },
  NoSpeechTimedOut,
  /// The terminal reset after a finish inserted, a cancel completed, or a
  /// failure was shown.
  SessionEnded,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Effect {
  /// Run the begin guards; feed back `BeginApproved` or `BeginRejected`.
  CheckAndBegin,
  BeginRecognition,
  FinishRecognition {
    speaking_duration: Duration,
  },
  CancelRecognition,
  CancelStart,
  StartNoSpeechTimer,
  StopNoSpeechTimer,
  ShowListening {
    latched: bool,
  },
  ShowLatched,
  ShowLiveText,
  ShowFinalizing,
  HideHud,
  NotifyRecording(bool),
}

#[derive(Debug)]
pub struct SessionMachine {
  state: State,
  pending_gesture: Option<Gesture>,
  has_speech: bool,
  finish_when_started: bool,
  cancel_when_started: bool,
  recording_started_at: Option<Instant>,
}

impl Default for SessionMachine {
  fn default() -> Self {
    Self {
      state: State::Idle,
      pending_gesture: None,
      has_speech: false,
      finish_when_started: false,
      cancel_when_started: false,
      recording_started_at: None,
    }
  }
}

impl SessionMachine {
  pub fn state(&self) -> State {
    self.state
  }

  pub fn is_session_active(&self) -> bool {
    self.state != State::Idle
  }

  pub fn reduce(&mut self, action: Action) -> Vec<Effect> {
    match action {
      Action::TriggerPressed { now } => self.trigger_pressed(now),
      Action::TriggerReleased { now } => self.trigger_released(now),
      Action::Toggled { now } => self.toggled(now),
      Action::EscapePressed => self.cancel(),
      Action::BeginApproved => self.begin_approved(),
      Action::BeginRejected => {
        self.pending_gesture = None;
        vec![]
      }
      Action::RecognitionStarted { now } => self.recognition_started(now),
      Action::RecognitionFailed { was_cancelled } => self.recognition_failed(was_cancelled),
      Action::UpdateReceived { has_visible_text } => self.update_received(has_visible_text),
      Action::NoSpeechTimedOut => {
        if self.has_speech {
          vec![]
        } else {
          self.cancel()
        }
      }
      Action::SessionEnded => self.reset(),
    }
  }

  fn trigger_pressed(&mut self, now: Instant) -> Vec<Effect> {
    match self.state {
      State::Idle => {
        self.pending_gesture = Some(Gesture::Held { started_at: now });
        vec![Effect::CheckAndBegin]
      }
      State::Starting(Gesture::Latched) => {
        self.finish_when_started = true;
        vec![]
      }
      State::Recording(Gesture::Latched) => self.finish(now),
      State::Starting(Gesture::Held { .. })
      | State::Recording(Gesture::Held { .. })
      | State::Finishing
      | State::Cancelling => vec![],
    }
  }

  fn trigger_released(&mut self, now: Instant) -> Vec<Effect> {
    match self.state {
      State::Starting(Gesture::Held { started_at }) => {
        if now.duration_since(started_at) < TAP_THRESHOLD {
          self.state = State::Starting(Gesture::Latched);
          return vec![Effect::ShowLatched];
        }
        self.finish_when_started = true;
        vec![]
      }
      State::Recording(Gesture::Held { started_at }) => {
        if now.duration_since(started_at) < TAP_THRESHOLD {
          self.state = State::Recording(Gesture::Latched);
          return vec![Effect::ShowLatched];
        }
        self.finish(now)
      }
      State::Idle
      | State::Starting(Gesture::Latched)
      | State::Recording(Gesture::Latched)
      | State::Finishing
      | State::Cancelling => vec![],
    }
  }

  fn toggled(&mut self, now: Instant) -> Vec<Effect> {
    match self.state {
      State::Idle => {
        self.pending_gesture = Some(Gesture::Latched);
        vec![Effect::CheckAndBegin]
      }
      State::Starting(_) => {
        self.finish_when_started = true;
        vec![]
      }
      State::Recording(_) => self.finish(now),
      State::Finishing | State::Cancelling => vec![],
    }
  }

  fn begin_approved(&mut self) -> Vec<Effect> {
    let (State::Idle, Some(gesture)) = (self.state, self.pending_gesture) else {
      return vec![];
    };
    self.pending_gesture = None;
    self.state = State::Starting(gesture);
    self.has_speech = false;
    self.finish_when_started = false;
    self.cancel_when_started = false;
    self.recording_started_at = None;
    vec![
      Effect::ShowListening {
        latched: gesture.is_latched(),
      },
      Effect::NotifyRecording(true),
      Effect::BeginRecognition,
    ]
  }

  fn recognition_started(&mut self, now: Instant) -> Vec<Effect> {
    if self.cancel_when_started {
      // Escape landed while the microphone was still opening; the session
      // is already cancelling and the HUD already hidden.
      return vec![Effect::CancelRecognition];
    }
    let State::Starting(gesture) = self.state else {
      return vec![];
    };
    self.state = State::Recording(gesture);
    self.recording_started_at = Some(now);
    let mut effects = vec![Effect::StartNoSpeechTimer];
    if self.finish_when_started {
      effects.extend(self.finish(now));
    }
    effects
  }

  fn recognition_failed(&mut self, was_cancelled: bool) -> Vec<Effect> {
    if was_cancelled || self.cancel_when_started {
      return self.reset();
    }
    if !self.is_session_active() {
      return vec![];
    }
    self.state = State::Cancelling;
    vec![Effect::StopNoSpeechTimer, Effect::CancelRecognition]
  }

  fn update_received(&mut self, has_visible_text: bool) -> Vec<Effect> {
    if !self.is_session_active() {
      return vec![];
    }
    let mut effects = vec![];
    if has_visible_text {
      self.has_speech = true;
      effects.push(Effect::StopNoSpeechTimer);
    }
    // The engine's last pass lands while the session finishes; the HUD
    // already says "Finalizing" and must not flash the draft.
    if self.state != State::Finishing {
      effects.push(Effect::ShowLiveText);
    }
    effects
  }

  fn finish(&mut self, now: Instant) -> Vec<Effect> {
    let State::Recording(_) = self.state else {
      return vec![];
    };
    let speaking_duration = self
      .recording_started_at
      .map(|start| now.duration_since(start))
      .unwrap_or_default();
    self.state = State::Finishing;
    vec![
      Effect::StopNoSpeechTimer,
      Effect::ShowFinalizing,
      Effect::FinishRecognition { speaking_duration },
    ]
  }

  fn cancel(&mut self) -> Vec<Effect> {
    match self.state {
      State::Idle | State::Finishing | State::Cancelling => vec![],
      State::Starting(_) => {
        // The start tears itself down and reports back as a cancelled
        // recognition failure.
        self.cancel_when_started = true;
        self.state = State::Cancelling;
        vec![
          Effect::CancelStart,
          Effect::StopNoSpeechTimer,
          Effect::HideHud,
        ]
      }
      State::Recording(_) => {
        self.state = State::Cancelling;
        vec![
          Effect::StopNoSpeechTimer,
          Effect::HideHud,
          Effect::CancelRecognition,
        ]
      }
    }
  }

  fn reset(&mut self) -> Vec<Effect> {
    *self = Self::default();
    vec![Effect::StopNoSpeechTimer, Effect::NotifyRecording(false)]
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  fn ms(base: Instant, millis: u64) -> Instant {
    base + Duration::from_millis(millis)
  }

  fn started(machine: &mut SessionMachine, at: Instant) {
    assert_eq!(
      machine.reduce(Action::TriggerPressed { now: at }),
      vec![Effect::CheckAndBegin]
    );
    machine.reduce(Action::BeginApproved);
    machine.reduce(Action::RecognitionStarted { now: at });
  }

  #[test]
  fn holding_past_the_tap_threshold_finishes_on_release() {
    let t = Instant::now();
    let mut m = SessionMachine::default();
    started(&mut m, t);
    assert_eq!(m.state(), State::Recording(Gesture::Held { started_at: t }));
    let effects = m.reduce(Action::TriggerReleased { now: ms(t, 900) });
    assert_eq!(m.state(), State::Finishing);
    assert!(effects.contains(&Effect::FinishRecognition {
      speaking_duration: Duration::from_millis(900)
    }));
  }

  #[test]
  fn a_quick_tap_latches_and_the_next_press_finishes() {
    let t = Instant::now();
    let mut m = SessionMachine::default();
    started(&mut m, t);
    assert_eq!(
      m.reduce(Action::TriggerReleased { now: ms(t, 120) }),
      vec![Effect::ShowLatched]
    );
    assert_eq!(m.state(), State::Recording(Gesture::Latched));
    let effects = m.reduce(Action::TriggerPressed { now: ms(t, 3000) });
    assert_eq!(m.state(), State::Finishing);
    assert!(matches!(
      effects.last(),
      Some(Effect::FinishRecognition { .. })
    ));
  }

  #[test]
  fn a_tap_while_still_starting_latches() {
    let t = Instant::now();
    let mut m = SessionMachine::default();
    m.reduce(Action::TriggerPressed { now: t });
    m.reduce(Action::BeginApproved);
    assert_eq!(
      m.reduce(Action::TriggerReleased { now: ms(t, 80) }),
      vec![Effect::ShowLatched]
    );
    m.reduce(Action::RecognitionStarted { now: ms(t, 100) });
    assert_eq!(m.state(), State::Recording(Gesture::Latched));
  }

  #[test]
  fn a_long_release_while_starting_finishes_as_soon_as_recording_starts() {
    let t = Instant::now();
    let mut m = SessionMachine::default();
    m.reduce(Action::TriggerPressed { now: t });
    m.reduce(Action::BeginApproved);
    assert!(
      m.reduce(Action::TriggerReleased { now: ms(t, 400) })
        .is_empty()
    );
    let effects = m.reduce(Action::RecognitionStarted { now: ms(t, 450) });
    assert_eq!(m.state(), State::Finishing);
    assert!(matches!(
      effects.last(),
      Some(Effect::FinishRecognition { .. })
    ));
  }

  #[test]
  fn escape_while_starting_cancels_once_the_start_reports_back() {
    let t = Instant::now();
    let mut m = SessionMachine::default();
    m.reduce(Action::TriggerPressed { now: t });
    m.reduce(Action::BeginApproved);
    let effects = m.reduce(Action::EscapePressed);
    assert!(effects.contains(&Effect::CancelStart));
    assert!(effects.contains(&Effect::HideHud));
    assert_eq!(
      m.reduce(Action::RecognitionStarted { now: ms(t, 50) }),
      vec![Effect::CancelRecognition]
    );
    m.reduce(Action::RecognitionFailed {
      was_cancelled: true,
    });
    assert_eq!(m.state(), State::Idle);
  }

  #[test]
  fn escape_while_recording_cancels_and_hides() {
    let t = Instant::now();
    let mut m = SessionMachine::default();
    started(&mut m, t);
    let effects = m.reduce(Action::EscapePressed);
    assert_eq!(m.state(), State::Cancelling);
    assert!(effects.contains(&Effect::HideHud));
    assert!(effects.contains(&Effect::CancelRecognition));
  }

  #[test]
  fn no_speech_timeout_cancels_only_a_silent_session() {
    let t = Instant::now();
    let mut silent = SessionMachine::default();
    started(&mut silent, t);
    silent.reduce(Action::NoSpeechTimedOut);
    assert_eq!(silent.state(), State::Cancelling);

    let mut spoken = SessionMachine::default();
    started(&mut spoken, t);
    spoken.reduce(Action::UpdateReceived {
      has_visible_text: true,
    });
    assert!(spoken.reduce(Action::NoSpeechTimedOut).is_empty());
    assert!(matches!(spoken.state(), State::Recording(_)));
  }

  #[test]
  fn live_text_is_not_shown_while_finalizing() {
    let t = Instant::now();
    let mut m = SessionMachine::default();
    started(&mut m, t);
    m.reduce(Action::TriggerReleased { now: ms(t, 1000) });
    let effects = m.reduce(Action::UpdateReceived {
      has_visible_text: true,
    });
    assert!(!effects.contains(&Effect::ShowLiveText));
  }

  #[test]
  fn toggle_starts_latched_and_toggles_again_to_finish() {
    let t = Instant::now();
    let mut m = SessionMachine::default();
    assert_eq!(
      m.reduce(Action::Toggled { now: t }),
      vec![Effect::CheckAndBegin]
    );
    let effects = m.reduce(Action::BeginApproved);
    assert!(effects.contains(&Effect::ShowListening { latched: true }));
    m.reduce(Action::RecognitionStarted { now: t });
    m.reduce(Action::Toggled { now: ms(t, 2000) });
    assert_eq!(m.state(), State::Finishing);
  }

  #[test]
  fn a_rejected_begin_leaves_the_machine_idle() {
    let t = Instant::now();
    let mut m = SessionMachine::default();
    m.reduce(Action::TriggerPressed { now: t });
    m.reduce(Action::BeginRejected);
    assert!(m.reduce(Action::BeginApproved).is_empty());
    assert_eq!(m.state(), State::Idle);
  }

  #[test]
  fn session_end_returns_to_idle_and_reports_not_recording() {
    let t = Instant::now();
    let mut m = SessionMachine::default();
    started(&mut m, t);
    m.reduce(Action::TriggerReleased { now: ms(t, 1000) });
    let effects = m.reduce(Action::SessionEnded);
    assert_eq!(m.state(), State::Idle);
    assert!(effects.contains(&Effect::NotifyRecording(false)));
  }
}
