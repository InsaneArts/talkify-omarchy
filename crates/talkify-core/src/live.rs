//! Live insertion: text lands in the window while the user is still
//! speaking, a few words at a time.
//!
//! A paste cannot be taken back cleanly, so only text that will not change
//! is inserted. The Speech Model re-decodes the audio since the last cut on
//! every pass, and a word's spelling, punctuation and even existence can
//! change between passes, so a word is committed when two consecutive passes
//! agree on it, it ended at least `HOLDBACK` before the end of the audio,
//! and it is not the last agreed word (whose punctuation the next words
//! still decide). A pause commits everything heard so far: that is the
//! debounce that makes a phrase land the moment you stop to think.
//!
//! The audio is only ever cut inside silence: at a pause, or at a sentence
//! end followed by a gap. Cutting between words mid-speech, where word
//! timings are only accurate to a frame, repeats or clips the word at the
//! cut and takes away the context the model needs. Between cuts each pass
//! sees the whole phrase, and the words already inserted are found again in
//! the new hypothesis by matching their text.

/// 16 kHz samples per second.
const RATE: f32 = 16_000.0;
/// Words that end this close to the end of the audio may still change.
const HOLDBACK: f32 = 0.8;
/// How much silence after the last word a cut keeps on the decoded side.
const CUT_PADDING: f32 = 0.12;
/// A sentence end followed by at least this much silence is a safe cut.
const SENTENCE_GAP: f32 = 0.15;
/// Past this the stretch being decoded is cut at its widest committed gap,
/// even without a pause, so passes stay fast.
const LONGEST_STRETCH: f32 = 20.0;

/// A word with its place in the decoded stretch, in seconds from its start.
#[derive(Clone, Debug, PartialEq)]
pub struct Word {
  pub text: String,
  pub start: f32,
  pub end: f32,
}

impl Word {
  pub fn new(text: &str, start: f32, end: f32) -> Self {
    Self {
      text: text.into(),
      start,
      end,
    }
  }
}

/// Text to insert now, and how many samples to cut off the front of the
/// stretch being decoded (zero for none).
#[derive(Clone, Debug, PartialEq)]
pub struct Commit {
  pub text: String,
  pub cut: usize,
}

/// Standalone punctuation tokens ("." after a word) belong to that word, so
/// agreement and commits work on whole words. The word keeps its own end:
/// the model stamps a punctuation token where it emits it, often after the
/// pause that follows the word, and punctuation makes no sound.
pub fn merge_punctuation(words: &[Word]) -> Vec<Word> {
  let mut merged: Vec<Word> = Vec::with_capacity(words.len());
  for word in words {
    let text = word.text.trim();
    if text.is_empty() {
      continue;
    }
    let is_punctuation = text.chars().all(|c| !c.is_alphanumeric());
    match merged.last_mut() {
      Some(previous) if is_punctuation => previous.text.push_str(text),
      _ => merged.push(Word {
        text: text.into(),
        start: word.start,
        end: word.end,
      }),
    }
  }
  merged
}

fn normalized(word: &str) -> String {
  word
    .chars()
    .filter(|c| c.is_alphanumeric())
    .flat_map(char::to_lowercase)
    .collect()
}

fn agreed_prefix(previous: &[Word], current: &[Word]) -> usize {
  previous
    .iter()
    .zip(current)
    .take_while(|(a, b)| normalized(&a.text) == normalized(&b.text))
    .count()
}

fn ends_sentence(text: &str) -> bool {
  text.trim_end().ends_with(['.', '!', '?', '…'])
}

#[derive(Debug)]
pub struct LiveCommitter {
  pause: f32,
  /// The last pass's words, for agreement.
  previous: Vec<Word>,
  /// The words of the current stretch already inserted, normalized.
  committed: Vec<String>,
  /// The last inserted word as it was spelled, so punctuation the model adds
  /// to it later can still follow it in.
  last_word: String,
  /// True from a cut until the next insert: the new stretch's first word
  /// was capitalised by the model only because it was decoded alone.
  after_cut: bool,
  inserted: String,
}

impl LiveCommitter {
  pub fn new(pause_seconds: f32) -> Self {
    Self {
      pause: pause_seconds,
      previous: Vec::new(),
      committed: Vec::new(),
      last_word: String::new(),
      after_cut: false,
      inserted: String::new(),
    }
  }

  /// Everything inserted so far this session.
  pub fn inserted(&self) -> &str {
    &self.inserted
  }

  /// A live pass over the stretch since the last cut: `words` as decoded,
  /// `seconds` the stretch's length, `trailing_silence` how long it has been
  /// quiet at its end.
  pub fn pass(&mut self, words: &[Word], seconds: f32, trailing_silence: f32) -> Option<Commit> {
    let words = merge_punctuation(words);
    let last = words.last()?.clone();
    let start = self.resume_index(&words);

    // The user paused after speaking: the phrase is done, and the cut lands
    // in the silence after it.
    if trailing_silence >= self.pause && last.end <= seconds - self.pause * 0.75 {
      let text = self.append(&words[start..]);
      self.previous.clear();
      self.committed.clear();
      self.after_cut = true;
      let cut_at = (last.end + CUT_PADDING).min(seconds);
      return Some(Commit {
        text,
        cut: (cut_at * RATE) as usize,
      });
    }

    let settled = words
      .iter()
      .take_while(|word| word.end <= seconds - HOLDBACK)
      .count();
    let upto = agreed_prefix(&self.previous, &words)
      .min(settled)
      .saturating_sub(1);
    self.previous = words.clone();
    if upto <= start {
      return None;
    }
    let text = self.append(&words[start..upto]);
    self
      .committed
      .extend(words[start..upto].iter().map(|word| normalized(&word.text)));

    let cut = self.safe_cut(&words, upto, seconds);
    Some(Commit {
      text,
      cut: (cut * RATE) as usize,
    })
  }

  /// The session's last pass over the stretch since the last cut: whatever
  /// is not in yet goes in.
  pub fn finish(&mut self, words: &[Word]) -> Option<String> {
    let words = merge_punctuation(words);
    let start = self.resume_index(&words);
    // The model often adds the closing period only once the audio ends,
    // after its word is already in.
    let mut text = match start.checked_sub(1).map(|index| &words[index].text) {
      Some(decoded)
        if decoded.len() > self.last_word.len() && decoded.starts_with(&self.last_word) =>
      {
        let suffix = &decoded[self.last_word.len()..];
        if suffix.chars().all(|c| !c.is_alphanumeric()) {
          self.inserted.push_str(suffix);
          suffix.to_string()
        } else {
          String::new()
        }
      }
      _ => String::new(),
    };
    self.previous.clear();
    self.committed.clear();
    text.push_str(&self.append(&words[start..]));
    (!text.is_empty()).then_some(text)
  }

  /// What the HUD shows for a pass: everything inserted, then the words of
  /// the pass that are not in yet.
  pub fn display(&self, words: &[Word]) -> String {
    let words = merge_punctuation(words);
    let start = self.resume_index(&words);
    let tail = words[start..]
      .iter()
      .map(|word| word.text.as_str())
      .collect::<Vec<_>>()
      .join(" ");
    match (self.inserted.is_empty(), tail.is_empty()) {
      (true, _) => tail,
      (false, true) => self.inserted.clone(),
      (false, false) => format!("{} {tail}", self.inserted),
    }
  }

  /// Where the uncommitted words start in a new hypothesis. Usually right
  /// after as many words as were committed, but a re-decode can split or
  /// merge a word, so the last committed word is looked for nearby.
  fn resume_index(&self, words: &[Word]) -> usize {
    let count = self.committed.len();
    let Some(last) = self.committed.last() else {
      return 0;
    };
    let matches_at =
      |end: usize| end >= 1 && end <= words.len() && normalized(&words[end - 1].text) == *last;
    [0isize, 1, -1, 2, -2]
      .iter()
      .map(|delta| count as isize + delta)
      .filter(|end| *end >= 0)
      .map(|end| end as usize)
      .find(|end| matches_at(*end))
      .unwrap_or(count.min(words.len()))
  }

  /// Where to cut after committing `words[..upto]`: at a sentence end
  /// followed by silence, or at the widest committed gap once the stretch
  /// grows long. Returns seconds, zero for no cut. Shifts what is kept onto
  /// the new stretch.
  fn safe_cut(&mut self, words: &[Word], upto: usize, seconds: f32) -> f32 {
    let gap_after = |index: usize| words[index + 1].start - words[index].end;
    let sentence_end = (0..upto)
      .rev()
      .find(|&index| ends_sentence(&words[index].text) && gap_after(index) >= SENTENCE_GAP);
    let boundary = sentence_end.or_else(|| {
      (seconds > LONGEST_STRETCH)
        .then(|| (0..upto).max_by(|&a, &b| gap_after(a).total_cmp(&gap_after(b))))
        .flatten()
    });
    let Some(index) = boundary else {
      return 0.0;
    };
    let cut_at = (words[index].end + words[index + 1].start) / 2.0;
    let kept = index + 1;
    // Only a cut before an uninserted word gives that word a fresh start.
    self.after_cut = kept == upto;
    self.committed.drain(..kept.min(self.committed.len()));
    self.previous = words[kept..]
      .iter()
      .map(|word| Word {
        text: word.text.clone(),
        start: word.start - cut_at,
        end: word.end - cut_at,
      })
      .collect();
    cut_at
  }

  /// Joins `words` onto what is already inserted and returns exactly the
  /// text to insert now, leading space included.
  fn append(&mut self, words: &[Word]) -> String {
    let mut text = crate::tidy::join_words(words);
    if text.is_empty() {
      return text;
    }
    if !self.inserted.is_empty() {
      // Each stretch is decoded on its own, so the model capitalises its
      // first word. Mid-sentence that word is not a sentence start. Inside a
      // stretch the model's own capitals are right ("Americans").
      if self.after_cut && !ends_sentence(&self.inserted) {
        text = lowercase_sentence_start(&text);
      }
      if !self.inserted.ends_with(char::is_whitespace) {
        text.insert(0, ' ');
      }
    }
    self.after_cut = false;
    self.last_word = words
      .last()
      .map(|word| word.text.clone())
      .unwrap_or_default();
    self.inserted.push_str(&text);
    text
  }
}

/// Lowercases a capitalised first word, leaving "I", "I'm" and acronyms
/// like "NASA" alone.
fn lowercase_sentence_start(text: &str) -> String {
  let first = text.split_whitespace().next().unwrap_or("");
  let letters: Vec<char> = first.chars().filter(|c| c.is_alphabetic()).collect();
  let is_pronoun_i = letters.first() == Some(&'I')
    && (letters.len() == 1 || first.starts_with("I'") || first.starts_with("I’"));
  let is_capitalised = letters.len() > 1
    && letters[0].is_uppercase()
    && letters.iter().skip(1).all(|c| c.is_lowercase());
  if is_pronoun_i || !is_capitalised {
    return text.to_string();
  }
  let mut chars = text.chars();
  let head = chars
    .next()
    .map(|c| c.to_lowercase().collect::<String>())
    .unwrap_or_default();
  head + chars.as_str()
}

#[cfg(test)]
mod tests {
  use super::*;

  fn words(spec: &[(&str, f32, f32)]) -> Vec<Word> {
    spec
      .iter()
      .map(|(text, start, end)| Word::new(text, *start, *end))
      .collect()
  }

  #[test]
  fn standalone_punctuation_joins_the_word_before_it() {
    let merged = merge_punctuation(&words(&[
      ("Hello", 0.0, 0.4),
      (",", 0.4, 0.45),
      ("world", 0.5, 0.9),
      (".", 0.9, 0.95),
    ]));
    assert_eq!(merged, words(&[("Hello,", 0.0, 0.4), ("world.", 0.5, 0.9)]));
  }

  #[test]
  fn nothing_is_committed_until_two_passes_agree() {
    let mut live = LiveCommitter::new(0.6);
    let first = words(&[
      ("ask", 0.0, 0.3),
      ("not", 0.4, 0.6),
      ("what", 0.7, 0.9),
      ("your", 1.0, 1.2),
    ]);
    assert_eq!(live.pass(&first, 3.0, 0.0), None);
    let second = words(&[
      ("Ask", 0.0, 0.3),
      ("not", 0.4, 0.6),
      ("what", 0.7, 0.9),
      ("your", 1.0, 1.2),
      ("country", 1.3, 1.8),
    ]);
    // "your" is agreed and settled but it is the last agreed word: held
    // back. No sentence end, no long stretch: no cut.
    let commit = live.pass(&second, 3.2, 0.0).unwrap();
    assert_eq!(
      commit,
      Commit {
        text: "Ask not what".into(),
        cut: 0
      }
    );
  }

  #[test]
  fn words_near_the_end_of_the_audio_wait() {
    let mut live = LiveCommitter::new(0.6);
    let pass = words(&[("one", 0.0, 0.3), ("two", 0.4, 0.7), ("three", 0.8, 1.1)]);
    live.pass(&pass, 1.3, 0.0);
    assert_eq!(live.pass(&pass, 1.3, 0.0), None);
    let commit = live.pass(&pass, 2.0, 0.0).unwrap();
    assert_eq!(commit.text, "one two");
  }

  #[test]
  fn later_passes_resume_after_the_committed_words_without_repeating_them() {
    let mut live = LiveCommitter::new(0.6);
    let early = words(&[
      ("one", 0.0, 0.3),
      ("two", 0.4, 0.7),
      ("three", 0.8, 1.1),
      ("four", 1.2, 1.5),
    ]);
    live.pass(&early, 3.0, 0.0);
    assert_eq!(live.pass(&early, 3.0, 0.0).unwrap().text, "one two three");
    // The same stretch, decoded again with more audio.
    let later = words(&[
      ("one", 0.0, 0.3),
      ("two", 0.4, 0.7),
      ("three", 0.8, 1.1),
      ("four", 1.2, 1.5),
      ("five", 1.6, 1.9),
      ("six", 2.0, 2.2),
    ]);
    // "four" agrees with the last pass but is its last agreed word.
    assert_eq!(live.pass(&later, 4.0, 0.0), None);
    assert_eq!(live.pass(&later, 4.0, 0.0).unwrap().text, " four five");
    assert_eq!(live.inserted(), "one two three four five");
  }

  #[test]
  fn a_redecode_that_splits_a_committed_word_still_resumes_after_it() {
    let mut live = LiveCommitter::new(0.6);
    let early = words(&[
      ("hello", 0.0, 0.3),
      ("world", 0.4, 0.7),
      ("again", 0.8, 1.1),
    ]);
    live.pass(&early, 3.0, 0.0);
    assert_eq!(live.pass(&early, 3.0, 0.0).unwrap().text, "hello world");
    // "hello" came back as two words this time.
    let later = words(&[
      ("hel", 0.0, 0.15),
      ("lo", 0.15, 0.3),
      ("world", 0.4, 0.7),
      ("again", 0.8, 1.1),
      ("today", 1.2, 1.5),
    ]);
    assert_eq!(live.display(&later), "hello world again today");
  }

  #[test]
  fn a_sentence_end_followed_by_silence_is_cut_after() {
    let mut live = LiveCommitter::new(0.6);
    let pass = words(&[
      ("Done", 0.0, 0.3),
      (".", 0.3, 0.32),
      ("Next", 0.7, 1.0),
      ("one", 1.1, 1.4),
      ("here", 1.5, 1.8),
    ]);
    live.pass(&pass, 3.5, 0.0);
    let commit = live.pass(&pass, 3.5, 0.0).unwrap();
    assert_eq!(commit.text, "Done. Next one");
    let shift: f32 = (0.3 + 0.7) / 2.0;
    assert_eq!(commit.cut, (shift * RATE) as usize);
    // After the cut the stretch starts at "Next"; its committed words are
    // still known, so they are not inserted again.
    let after = words(&[
      ("Next", 0.7 - shift, 1.0 - shift),
      ("one", 1.1 - shift, 1.4 - shift),
      ("here", 1.5 - shift, 1.8 - shift),
      ("now", 1.9 - shift, 2.1 - shift),
    ]);
    assert_eq!(live.pass(&after, 4.0 - shift, 0.0), None);
    assert_eq!(live.pass(&after, 4.0 - shift, 0.0).unwrap().text, " here");
  }

  #[test]
  fn a_sentence_end_run_straight_into_the_next_word_is_not_cut() {
    let mut live = LiveCommitter::new(0.6);
    let pass = words(&[
      ("Done", 0.0, 0.3),
      (".", 0.3, 0.32),
      ("Next", 0.36, 0.6),
      ("one", 0.7, 1.0),
      ("more", 1.1, 1.3),
    ]);
    live.pass(&pass, 3.0, 0.0);
    assert_eq!(live.pass(&pass, 3.0, 0.0).unwrap().cut, 0);
  }

  #[test]
  fn a_pause_commits_the_whole_phrase_and_cuts_in_the_silence() {
    let mut live = LiveCommitter::new(0.6);
    let pass = words(&[("Hello", 0.0, 0.4), ("world", 0.5, 0.9), (".", 0.9, 0.95)]);
    let commit = live.pass(&pass, 1.8, 0.8).unwrap();
    assert_eq!(commit.text, "Hello world.");
    assert_eq!(commit.cut, ((0.9 + CUT_PADDING) * RATE) as usize);
  }

  #[test]
  fn a_pause_after_partly_committed_words_inserts_only_the_rest() {
    let mut live = LiveCommitter::new(0.6);
    let pass = words(&[("one", 0.0, 0.3), ("two", 0.4, 0.7), ("three", 0.8, 1.1)]);
    live.pass(&pass, 2.0, 0.0);
    assert_eq!(live.pass(&pass, 2.0, 0.0).unwrap().text, "one two");
    let commit = live.pass(&pass, 2.4, 1.0).unwrap();
    assert_eq!(commit.text, " three");
    assert_eq!(live.inserted(), "one two three");
  }

  #[test]
  fn a_long_stretch_without_pauses_is_cut_at_its_widest_committed_gap() {
    let mut live = LiveCommitter::new(0.6);
    let mut spec = vec![];
    for i in 0..40 {
      let start = i as f32 * 0.5 + if i >= 20 { 0.3 } else { 0.0 };
      spec.push(("word", start, start + 0.4));
    }
    let pass = words(&spec);
    live.pass(&pass, 22.0, 0.0);
    let commit = live.pass(&pass, 22.0, 0.0).unwrap();
    // Word 19 ends at 9.9, word 20 starts at 10.3: the widest gap.
    let expected: f32 = (9.9 + 10.3) / 2.0;
    assert_eq!(commit.cut, (expected * RATE) as usize);
  }

  #[test]
  fn silence_before_any_word_commits_nothing() {
    let mut live = LiveCommitter::new(0.6);
    assert_eq!(live.pass(&[], 2.0, 2.0), None);
    assert_eq!(live.finish(&[]), None);
    assert_eq!(live.inserted(), "");
  }

  #[test]
  fn finish_inserts_only_what_is_not_in_yet() {
    let mut live = LiveCommitter::new(0.6);
    let pass = words(&[("one", 0.0, 0.3), ("two", 0.4, 0.7), ("three", 0.8, 1.1)]);
    live.pass(&pass, 2.0, 0.0);
    live.pass(&pass, 2.0, 0.0);
    assert_eq!(live.finish(&pass).unwrap(), " three");
    assert_eq!(live.inserted(), "one two three");
  }

  #[test]
  fn a_new_stretch_mid_sentence_loses_its_capital() {
    let mut live = LiveCommitter::new(0.6);
    live.pass(
      &words(&[
        ("my", 0.0, 0.2),
        ("fellow", 0.3, 0.6),
        ("Americans", 0.7, 1.2),
      ]),
      2.0,
      0.8,
    );
    let text = live
      .finish(&words(&[("Ask", 0.0, 0.3), ("not", 0.4, 0.6)]))
      .unwrap();
    assert_eq!(text, " ask not");
    assert_eq!(live.inserted(), "my fellow Americans ask not");
  }

  #[test]
  fn sentence_starts_pronoun_i_and_acronyms_keep_their_capitals() {
    let mut live = LiveCommitter::new(0.6);
    live.pass(&words(&[("Done", 0.0, 0.3), (".", 0.3, 0.35)]), 1.5, 0.8);
    assert_eq!(live.finish(&words(&[("Next", 0.0, 0.3)])).unwrap(), " Next");

    let mut live = LiveCommitter::new(0.6);
    live.pass(&words(&[("so", 0.0, 0.3)]), 1.5, 0.8);
    assert_eq!(
      live
        .finish(&words(&[("I'm", 0.0, 0.3), ("here", 0.4, 0.6)]))
        .unwrap(),
      " I'm here"
    );

    let mut live = LiveCommitter::new(0.6);
    live.pass(&words(&[("ask", 0.0, 0.3)]), 1.5, 0.8);
    assert_eq!(live.finish(&words(&[("NASA", 0.0, 0.3)])).unwrap(), " NASA");
  }

  #[test]
  fn capitals_inside_a_stretch_are_kept() {
    let mut live = LiveCommitter::new(0.6);
    let pass = words(&[
      ("my", 0.0, 0.2),
      ("fellow", 0.3, 0.6),
      ("Americans", 0.7, 1.0),
      ("ask", 1.1, 1.3),
      ("not", 1.4, 1.6),
    ]);
    live.pass(
      &words(&[
        ("my", 0.0, 0.2),
        ("fellow", 0.3, 0.6),
        ("Americans", 0.7, 1.0),
      ]),
      3.0,
      0.0,
    );
    live.pass(
      &words(&[
        ("my", 0.0, 0.2),
        ("fellow", 0.3, 0.6),
        ("Americans", 0.7, 1.0),
      ]),
      3.0,
      0.0,
    );
    live.pass(&pass, 3.0, 0.0);
    assert_eq!(live.pass(&pass, 3.0, 0.0).unwrap().text, " Americans ask");
  }

  #[test]
  fn a_period_the_model_adds_at_the_end_follows_its_word_in() {
    let mut live = LiveCommitter::new(0.6);
    let pass = words(&[
      ("the", 0.0, 0.2),
      ("new", 0.3, 0.5),
      ("engine", 0.6, 0.9),
      ("today", 1.0, 1.3),
    ]);
    live.pass(&pass, 3.0, 0.0);
    live.pass(&pass, 3.0, 0.0);
    assert_eq!(live.inserted(), "the new engine");
    let last = words(&[("the", 0.0, 0.2), ("new", 0.3, 0.5), ("engine.", 0.6, 0.9)]);
    assert_eq!(live.finish(&last).unwrap(), ".");
    assert_eq!(live.inserted(), "the new engine.");
  }

  #[test]
  fn display_puts_pending_words_after_the_inserted_text() {
    let mut live = LiveCommitter::new(0.6);
    assert_eq!(live.display(&words(&[("hello", 0.0, 0.3)])), "hello");
    live.pass(&words(&[("Hello", 0.0, 0.3)]), 1.5, 0.8);
    assert_eq!(
      live.display(&words(&[("there", 0.0, 0.3), (".", 0.3, 0.35)])),
      "Hello there."
    );
    assert_eq!(live.display(&[]), "Hello");
  }
}
