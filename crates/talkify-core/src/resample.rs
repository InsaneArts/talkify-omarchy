//! Turns whatever the microphone delivers into the 16 kHz mono the Speech
//! Model wants. PipeWire usually hands over 16 kHz when asked, so this is
//! the fallback path, and speech recognition does not need studio quality:
//! downsampling averages the input samples each output sample covers (a box
//! filter that keeps the worst aliasing out), upsampling interpolates.

pub const TARGET_RATE: u32 = 16_000;

#[derive(Debug)]
pub struct Resampler {
  /// Input samples per output sample.
  step: f64,
  channels: usize,
  phase: f64,
  sum: f32,
  count: u32,
  previous: f32,
  primed: bool,
}

impl Resampler {
  pub fn new(input_rate: u32, channels: u16) -> Self {
    Self {
      step: f64::from(input_rate) / f64::from(TARGET_RATE),
      channels: usize::from(channels.max(1)),
      phase: 0.0,
      sum: 0.0,
      count: 0,
      previous: 0.0,
      primed: false,
    }
  }

  /// Interleaved frames in, mono 16 kHz samples appended to `out`.
  pub fn process(&mut self, interleaved: &[f32], out: &mut Vec<f32>) {
    let mono = interleaved
      .chunks_exact(self.channels)
      .map(|frame| frame.iter().sum::<f32>() / self.channels as f32);

    if (self.step - 1.0).abs() < f64::EPSILON {
      out.extend(mono);
    } else if self.step > 1.0 {
      for sample in mono {
        self.sum += sample;
        self.count += 1;
        self.phase += 1.0;
        if self.phase >= self.step {
          out.push(self.sum / self.count as f32);
          self.sum = 0.0;
          self.count = 0;
          self.phase -= self.step;
        }
      }
    } else {
      for sample in mono {
        if !self.primed {
          self.previous = sample;
          self.primed = true;
        }
        while self.phase < 1.0 {
          let t = self.phase as f32;
          out.push(self.previous + (sample - self.previous) * t);
          self.phase += self.step;
        }
        self.phase -= 1.0;
        self.previous = sample;
      }
    }
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  fn run(rate: u32, channels: u16, input: &[f32]) -> Vec<f32> {
    let mut out = vec![];
    Resampler::new(rate, channels).process(input, &mut out);
    out
  }

  #[test]
  fn sixteen_kilohertz_mono_passes_through() {
    let input: Vec<f32> = (0..100).map(|i| i as f32).collect();
    assert_eq!(run(16_000, 1, &input), input);
  }

  #[test]
  fn forty_eight_kilohertz_averages_each_triple() {
    assert_eq!(
      run(48_000, 1, &[1.0, 2.0, 3.0, 4.0, 5.0, 6.0]),
      vec![2.0, 5.0]
    );
  }

  #[test]
  fn stereo_is_downmixed_before_resampling() {
    assert_eq!(run(16_000, 2, &[1.0, 3.0, -1.0, 1.0]), vec![2.0, 0.0]);
  }

  #[test]
  fn one_second_of_any_common_rate_makes_one_second_out() {
    for rate in [8_000, 22_050, 44_100, 48_000, 96_000] {
      let out = run(rate, 1, &vec![0.5; rate as usize]);
      assert!(
        (out.len() as i64 - 16_000).abs() <= 1,
        "{rate}: {}",
        out.len()
      );
      assert!(out.iter().all(|s| (s - 0.5).abs() < 1e-5), "{rate}");
    }
  }

  #[test]
  fn state_carries_across_calls() {
    let mut resampler = Resampler::new(48_000, 1);
    let mut out = vec![];
    resampler.process(&[1.0, 2.0], &mut out);
    assert!(out.is_empty());
    resampler.process(&[3.0, 4.0, 5.0, 6.0], &mut out);
    assert_eq!(out, vec![2.0, 5.0]);
  }
}
