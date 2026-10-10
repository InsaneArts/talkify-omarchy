//! The microphone's level for the HUD, and the watchdog that tells a dead
//! microphone apart from a quiet room. Silence and a dead microphone must
//! look different: silence still delivers buffers with a noise floor, a dead
//! microphone stops delivering them.

use std::time::{Duration, Instant};

/// Levels stopping for this long while listening means the microphone died.
pub const DEAD_MICROPHONE_AFTER: Duration = Duration::from_millis(600);

/// How long a session waits for its first buffer before calling the
/// microphone dead. A Bluetooth headset switching to its hands-free profile
/// takes over a second before the first buffer arrives.
pub const FIRST_AUDIO_AFTER: Duration = Duration::from_millis(2500);

/// RMS of a buffer mapped to 0–1 over a 50 dB window: a quiet room sits near
/// zero and normal speech fills the upper half. Same mapping as Talkify.
pub fn normalized_level(samples: &[f32]) -> f32 {
  if samples.is_empty() {
    return 0.0;
  }
  let mean_square = samples.iter().map(|s| s * s).sum::<f32>() / samples.len() as f32;
  let rms = mean_square.sqrt().max(f32::MIN_POSITIVE);
  let db = 20.0 * rms.log10();
  ((db + 50.0) / 50.0).clamp(0.0, 1.0)
}

/// Below this normalized level a 20 ms window counts as silence: about
/// -40 dB, under speech and over a quiet room's floor.
pub const SILENCE_LEVEL: f32 = 0.2;

/// How long the end of a 16 kHz recording has been quiet, in seconds.
pub fn trailing_silence(samples: &[f32]) -> f32 {
  let window = 16_000 / 50;
  let quiet = samples
    .rchunks(window)
    .take_while(|chunk| normalized_level(chunk) < SILENCE_LEVEL)
    .count();
  (quiet * window).min(samples.len()) as f32 / 16_000.0
}

#[derive(Debug)]
pub struct MicWatchdog {
  armed_at: Instant,
  last_buffer_at: Option<Instant>,
}

impl MicWatchdog {
  pub fn new(now: Instant) -> Self {
    Self {
      armed_at: now,
      last_buffer_at: None,
    }
  }

  pub fn buffer_arrived(&mut self, now: Instant) {
    self.last_buffer_at = Some(now);
  }

  pub fn is_alive(&self, now: Instant) -> bool {
    match self.last_buffer_at {
      Some(last) => now.duration_since(last) <= DEAD_MICROPHONE_AFTER,
      None => now.duration_since(self.armed_at) <= FIRST_AUDIO_AFTER,
    }
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn digital_silence_reads_zero_and_full_scale_reads_one() {
    assert_eq!(normalized_level(&[0.0; 160]), 0.0);
    assert_eq!(normalized_level(&[1.0, -1.0, 1.0, -1.0]), 1.0);
    assert_eq!(normalized_level(&[]), 0.0);
  }

  #[test]
  fn minus_25_db_sits_mid_scale() {
    let amplitude = 10f32.powf(-25.0 / 20.0);
    let level = normalized_level(&[amplitude, -amplitude]);
    assert!((level - 0.5).abs() < 0.001, "{level}");
  }

  #[test]
  fn trailing_silence_counts_quiet_windows_from_the_end() {
    let mut samples = vec![0.3; 16_000];
    samples.extend(vec![0.0001; 8_000]);
    assert!((trailing_silence(&samples) - 0.5).abs() < 0.021);
    assert_eq!(trailing_silence(&vec![0.3; 16_000]), 0.0);
    assert_eq!(trailing_silence(&[]), 0.0);
  }

  #[test]
  fn an_opening_microphone_gets_the_long_budget() {
    let t = Instant::now();
    let w = MicWatchdog::new(t);
    assert!(w.is_alive(t + Duration::from_millis(2000)));
    assert!(!w.is_alive(t + Duration::from_millis(2600)));
  }

  #[test]
  fn a_microphone_that_stops_delivering_dies_after_the_short_budget() {
    let t = Instant::now();
    let mut w = MicWatchdog::new(t);
    w.buffer_arrived(t + Duration::from_millis(100));
    assert!(w.is_alive(t + Duration::from_millis(650)));
    assert!(!w.is_alive(t + Duration::from_millis(800)));
    w.buffer_arrived(t + Duration::from_millis(900));
    assert!(w.is_alive(t + Duration::from_millis(1000)));
  }
}
