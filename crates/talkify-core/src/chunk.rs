//! Splits a long recording into pieces the Speech Model handles well.
//!
//! Parakeet decodes a minute of speech in well under a second, but its
//! memory grows with the length of what it sees at once, so a long latched
//! session is decoded in pieces. Each cut lands at the quietest moment near
//! the target length, so it falls between words rather than through one.

/// 16 kHz samples per second.
const RATE: usize = 16_000;
/// The quietest stretch is measured over windows this long.
const WINDOW: usize = RATE / 50;

/// Ranges covering all of `samples`, each at most `max_seconds` long, cut
/// at the quietest 20 ms window in the last `search_seconds` before the
/// limit.
pub fn split(
  samples: &[f32],
  max_seconds: usize,
  search_seconds: usize,
) -> Vec<std::ops::Range<usize>> {
  let max = max_seconds * RATE;
  let search = (search_seconds * RATE).min(max / 2);
  let mut ranges = vec![];
  let mut start = 0;
  while samples.len() - start > max {
    let limit = start + max;
    let cut = quietest_window(samples, limit - search, limit).unwrap_or(limit);
    ranges.push(start..cut);
    start = cut;
  }
  ranges.push(start..samples.len());
  ranges
}

/// The start of the lowest-energy window inside `from..to`.
fn quietest_window(samples: &[f32], from: usize, to: usize) -> Option<usize> {
  (from..to.saturating_sub(WINDOW))
    .step_by(WINDOW)
    .map(|at| {
      let energy: f32 = samples[at..at + WINDOW].iter().map(|s| s * s).sum();
      (at, energy)
    })
    .min_by(|a, b| a.1.total_cmp(&b.1))
    .map(|(at, _)| at + WINDOW / 2)
}

#[cfg(test)]
mod tests {
  use super::*;

  fn speech(seconds: usize) -> Vec<f32> {
    vec![0.3; seconds * RATE]
  }

  #[test]
  fn a_short_recording_is_one_piece() {
    let samples = speech(30);
    assert_eq!(split(&samples, 60, 10), vec![0..samples.len()]);
  }

  #[test]
  fn pieces_cover_everything_without_overlap_and_respect_the_limit() {
    let samples = speech(200);
    let ranges = split(&samples, 60, 10);
    assert_eq!(ranges.first().unwrap().start, 0);
    assert_eq!(ranges.last().unwrap().end, samples.len());
    for pair in ranges.windows(2) {
      assert_eq!(pair[0].end, pair[1].start);
    }
    assert!(ranges.iter().all(|r| r.len() <= 60 * RATE));
  }

  #[test]
  fn the_cut_lands_in_the_pause() {
    let mut samples = speech(90);
    let pause = 55 * RATE..55 * RATE + RATE / 2;
    samples[pause.clone()].fill(0.0);
    let ranges = split(&samples, 60, 10);
    assert_eq!(ranges.len(), 2);
    assert!(pause.contains(&ranges[0].end), "cut at {}", ranges[0].end);
  }
}
