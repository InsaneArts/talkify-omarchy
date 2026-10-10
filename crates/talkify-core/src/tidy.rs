//! The Tidy pass: rule-based cleanup of what the Speech Model heard.
//!
//! It removes and punctuates, and never writes a word that was not spoken,
//! which is why it can run on every dictation without the over-editing users
//! hold against rewriting models. Everything that depends on how the words
//! were said (spoken punctuation, "scratch that", the send phrase) is gated
//! on pauses read from the words' timestamps, so "a comma-separated list" or
//! "I'll scratch that itch" stay as spoken.
//!
//! `tidy` returns the clean text and, for each input word, what became of
//! it, so the HUD can show a filler fading or a scratched phrase struck
//! through before the text lands.

use crate::live::{Word, merge_punctuation};
use crate::protocol::{MarkKind, TextMark, utf16_len};

/// Fillers nobody means. Removed wherever they appear.
const ALWAYS_FILLERS: &[&str] = &["uh", "uhm", "umm", "uhh", "erm", "hmm", "mhm", "mm"];
/// Fillers that are also words somewhere ("um" is "one" in Portuguese, "er"
/// is "he" in German): removed only when a pause or the model's own comma
/// sets them apart.
const GATED_FILLERS: &[&str] = &["um", "er", "ah", "eh"];
/// A gated filler, spoken punctuation or a scratch needs at least this much
/// silence beside it.
const PAUSE: f32 = 0.15;
/// The send phrase must follow at least this much silence.
const SEND_PAUSE: f32 = 0.25;
/// A scratch removes back to a sentence end or a pause at least this long.
const PHRASE_PAUSE: f32 = 0.5;

const SPOKEN_MARKS: &[(&[&str], &str)] = &[
  (&["new", "paragraph"], "\n\n"),
  (&["new", "line"], "\n"),
  (&["question", "mark"], "?"),
  (&["exclamation", "mark"], "!"),
  (&["exclamation", "point"], "!"),
  (&["full", "stop"], "."),
  (&["period"], "."),
  (&["comma"], ","),
  (&["colon"], ":"),
  (&["semicolon"], ";"),
];

const SCRATCH: &[&[&str]] = &[
  &["scratch", "that"],
  &["delete", "that"],
  &["strike", "that"],
];
/// "that" said quickly or with an accent often comes back as "at". Between
/// two pauses "delete at" means nothing else, so these count too, but only
/// set apart on both sides.
const SCRATCH_MISHEARD: &[&[&str]] = &[&["scratch", "at"], &["delete", "at"], &["strike", "at"]];

#[derive(Clone, Debug, PartialEq)]
pub struct TidyOptions {
  pub fillers: bool,
  pub stutters: bool,
  pub spoken_punctuation: bool,
  pub scratch: bool,
  /// Normalized send phrases, each a list of words.
  pub send_phrases: Vec<Vec<String>>,
}

impl TidyOptions {
  pub fn all(send_phrases: &str) -> Self {
    Self {
      fillers: true,
      stutters: true,
      spoken_punctuation: true,
      scratch: true,
      send_phrases: parse_phrases(send_phrases),
    }
  }

  pub fn none() -> Self {
    Self {
      fillers: false,
      stutters: false,
      spoken_punctuation: false,
      scratch: false,
      send_phrases: Vec::new(),
    }
  }
}

/// "send it, press enter" → [["send","it"], ["press","enter"]].
pub fn parse_phrases(list: &str) -> Vec<Vec<String>> {
  list
    .split(',')
    .map(|phrase| {
      phrase
        .split_whitespace()
        .map(normalized)
        .collect::<Vec<_>>()
    })
    .filter(|phrase| !phrase.is_empty())
    .collect()
}

/// What became of one (punctuation-merged) word.
#[derive(Clone, Debug, PartialEq)]
pub enum Fate {
  Keep,
  Filler,
  Stutter,
  Scratched,
  /// Spoken punctuation; the mark it becomes.
  Punctuation(&'static str),
  Send,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Tidied {
  pub text: String,
  /// The words that land, with spoken punctuation and capitals applied and
  /// their timings kept, for live insertion to commit.
  pub kept: Vec<Word>,
  /// The send phrase was said last, after a pause.
  pub send: bool,
  /// The words as `tidy` read them (punctuation merged), with their fates.
  pub words: Vec<Word>,
  pub fates: Vec<Fate>,
}

impl Tidied {
  /// How many words were dropped (fillers, stutters, scratched).
  pub fn removed(&self) -> usize {
    self
      .fates
      .iter()
      .filter(|fate| matches!(fate, Fate::Filler | Fate::Stutter | Fate::Scratched))
      .count()
  }

  /// The words joined as they were heard, and marks over that text for
  /// everything the pass changes. This is what the HUD shows as the draft.
  pub fn draft_with_marks(&self) -> (String, Vec<TextMark>) {
    let mut text = String::new();
    let mut marks: Vec<TextMark> = Vec::new();
    for (word, fate) in self.words.iter().zip(&self.fates) {
      if !text.is_empty() {
        text.push(' ');
      }
      let start = utf16_len(&text);
      text.push_str(&word.text);
      let kind = match fate {
        Fate::Keep => None,
        Fate::Filler | Fate::Stutter => Some(MarkKind::Filler),
        Fate::Scratched => Some(MarkKind::Scratched),
        Fate::Punctuation(_) => Some(MarkKind::Punctuation),
        Fate::Send => Some(MarkKind::Send),
      };
      if let Some(kind) = kind {
        let end = utf16_len(&text);
        // Neighbouring words of one kind ("scratch that", "new line") read
        // as one mark.
        match marks.last_mut() {
          Some(last) if last.kind == kind && last.end + 1 == start => last.end = end,
          _ => marks.push(TextMark {
            start,
            end,
            kind,
            replacement: String::new(),
          }),
        }
      }
    }
    (text, marks)
  }
}

pub fn normalized(word: &str) -> String {
  word
    .chars()
    .filter(|c| c.is_alphanumeric() || *c == '\'')
    .flat_map(char::to_lowercase)
    .collect()
}

fn trailing_punctuation(word: &str) -> &str {
  let cut = word
    .char_indices()
    .rev()
    .take_while(|(_, c)| !c.is_alphanumeric())
    .last()
    .map_or(word.len(), |(index, _)| index);
  &word[cut..]
}

fn strip_trailing_punctuation(word: &str) -> &str {
  &word[..word.len() - trailing_punctuation(word).len()]
}

fn ends_sentence(word: &str) -> bool {
  word.trim_end().ends_with(['.', '!', '?', '…'])
}

pub fn tidy(raw: &[Word], options: &TidyOptions) -> Tidied {
  let words = merge_punctuation(raw);
  let keys: Vec<String> = words.iter().map(|word| normalized(&word.text)).collect();
  let mut fates = vec![Fate::Keep; words.len()];
  let gap_before = |index: usize| -> f32 {
    if index == 0 {
      f32::INFINITY
    } else {
      words[index].start - words[index - 1].end
    }
  };
  let gap_after = |index: usize| -> f32 {
    if index + 1 >= words.len() {
      f32::INFINITY
    } else {
      words[index + 1].start - words[index].end
    }
  };
  let phrase_at = |index: usize, phrase: &[&str]| -> bool {
    phrase.len() + index <= words.len()
      && phrase
        .iter()
        .enumerate()
        .all(|(offset, part)| keys[index + offset] == *part)
  };

  // The send phrase, said last after a pause.
  let mut send = false;
  for phrase in &options.send_phrases {
    if phrase.is_empty() || phrase.len() > words.len() {
      continue;
    }
    let start = words.len() - phrase.len();
    let parts: Vec<&str> = phrase.iter().map(String::as_str).collect();
    if phrase_at(start, &parts) && (start == 0 || gap_before(start) >= SEND_PAUSE) {
      for fate in &mut fates[start..] {
        *fate = Fate::Send;
      }
      send = true;
      break;
    }
  }

  if options.scratch {
    let mut index = 0;
    while index < words.len() {
      let exact = SCRATCH.iter().find(|phrase| phrase_at(index, phrase));
      let misheard = SCRATCH_MISHEARD
        .iter()
        .find(|phrase| phrase_at(index, phrase));
      let Some(phrase) = exact.or(misheard) else {
        index += 1;
        continue;
      };
      let end = index + phrase.len() - 1;
      let before = index > 0 && gap_before(index) >= PAUSE;
      let after = end + 1 == words.len() || gap_after(end) >= PAUSE;
      let set_apart = if exact.is_some() {
        before || after
      } else {
        before && after
      };
      if fates[index] != Fate::Keep || !set_apart {
        index += 1;
        continue;
      }
      // Back to the last sentence end or long pause before the scratch.
      let mut from = index;
      while from > 0 {
        let previous = from - 1;
        if fates[previous] != Fate::Keep && fates[previous] != Fate::Filler {
          break;
        }
        // The word right before the scratch is always part of what it
        // removes, even with a period: the model closes a sentence at every
        // pause, so "Lunch at noon. Scratch that." scratches that sentence.
        let boundary = ends_sentence(&words[previous].text) || gap_before(from) >= PHRASE_PAUSE;
        if from != index && boundary {
          break;
        }
        from = previous;
      }
      for fate in &mut fates[from..=end] {
        *fate = Fate::Scratched;
      }
      index = end + 1;
    }
  }

  if options.spoken_punctuation {
    let mut index = 0;
    while index < words.len() {
      let found = SPOKEN_MARKS
        .iter()
        .find(|(phrase, _)| fates[index] == Fate::Keep && phrase_at(index, phrase));
      let Some((phrase, mark)) = found else {
        index += 1;
        continue;
      };
      let end = index + phrase.len() - 1;
      if index > 0 && gap_before(index) >= PAUSE && gap_after(end) >= PAUSE {
        for fate in &mut fates[index..=end] {
          *fate = Fate::Punctuation(mark);
        }
      }
      index = end + 1;
    }
  }

  if options.fillers {
    for (index, key) in keys.iter().enumerate() {
      if fates[index] != Fate::Keep {
        continue;
      }
      // The edge of the dictation is not a pause: German "Er geht" starts
      // with "Er" and nothing before it.
      let pause_before = index > 0 && gap_before(index) >= PAUSE;
      let pause_after = index + 1 < words.len() && gap_after(index) >= PAUSE;
      let gated = GATED_FILLERS.contains(&key.as_str())
        && (words[index].text.ends_with(',') || pause_before || pause_after);
      if ALWAYS_FILLERS.contains(&key.as_str()) || gated {
        fates[index] = Fate::Filler;
      }
    }
  }

  if options.stutters {
    let mut index = 0;
    while index < words.len() {
      let mut run = index + 1;
      while run < words.len() && keys[run] == keys[index] && fates[run] == Fate::Keep {
        run += 1;
      }
      if run - index >= 3 && fates[index] == Fate::Keep && !keys[index].is_empty() {
        for fate in &mut fates[index + 1..run] {
          *fate = Fate::Stutter;
        }
      }
      index = run;
    }
  }

  let kept = assemble(&words, &fates);
  Tidied {
    text: join_words(&kept),
    kept,
    send,
    words,
    fates,
  }
}

/// Words joined for the text: a space between words, none after a line
/// break.
pub fn join_words(words: &[Word]) -> String {
  let mut out = String::new();
  for word in words {
    if !out.is_empty() && !out.ends_with('\n') {
      out.push(' ');
    }
    out.push_str(&word.text);
  }
  out
}

/// The kept words, with spoken punctuation turned into marks and the
/// capitals a removed sentence start leaves behind put right.
fn assemble(words: &[Word], fates: &[Fate]) -> Vec<Word> {
  let mut out: Vec<Word> = Vec::new();
  // Whether the next kept word starts a sentence: at the start, after a
  // sentence end, and after a spoken period or new line.
  let mut sentence_start = true;
  let mut capitalise_next = false;
  for (word, fate) in words.iter().zip(fates) {
    match fate {
      Fate::Keep => {
        let mut kept = word.clone();
        if capitalise_next {
          kept.text = capitalised(&kept.text);
        }
        sentence_start = ends_sentence(&kept.text);
        capitalise_next = false;
        out.push(kept);
      }
      Fate::Punctuation(mark) => {
        // The mark replaces whatever the model put after the last word.
        if let Some(last) = out.last_mut() {
          let trimmed = strip_trailing_punctuation(&last.text).len();
          last.text.truncate(trimmed);
          last.text.push_str(mark);
          last.end = last.end.max(word.end);
        }
        capitalise_next = mark.starts_with('\n') || matches!(*mark, "." | "?" | "!");
        sentence_start = capitalise_next;
      }
      Fate::Filler | Fate::Stutter | Fate::Scratched | Fate::Send => {
        // A removed first word leaves the next one to start the sentence.
        if sentence_start {
          capitalise_next = true;
        }
      }
    }
  }
  // A send phrase or a scratch at the end leaves a dangling comma.
  if let Some(last) = out.last_mut() {
    let trimmed = last.text.trim_end_matches([',', ';', ':']).len();
    last.text.truncate(trimmed);
    if last.text.is_empty() {
      out.pop();
    }
  }
  out
}

fn capitalised(word: &str) -> String {
  let mut chars = word.chars();
  match chars.next() {
    Some(first) if first.is_lowercase() => {
      first.to_uppercase().collect::<String>() + chars.as_str()
    }
    Some(first) => first.to_string() + chars.as_str(),
    None => String::new(),
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  /// Words spaced 0.1 s apart; "|" in the spec marks a 0.4 s pause.
  fn said(spec: &str) -> Vec<Word> {
    let mut words = Vec::new();
    let mut at = 0.0;
    for token in spec.split(' ') {
      if token == "|" {
        at += 0.4;
        continue;
      }
      words.push(Word::new(token, at, at + 0.3));
      at += 0.4;
    }
    words
  }

  fn tidied(spec: &str) -> String {
    tidy(&said(spec), &TidyOptions::all("send it, press enter")).text
  }

  #[test]
  fn plain_speech_passes_through_untouched() {
    assert_eq!(tidied("The plan is fine."), "The plan is fine.");
  }

  #[test]
  fn fillers_go_and_the_sentence_start_moves_to_the_next_word() {
    assert_eq!(
      tidied("Um, so the plan uh is fine."),
      "So the plan is fine."
    );
    assert_eq!(tidied("Hmm let me think."), "Let me think.");
  }

  #[test]
  fn a_gated_filler_run_into_its_neighbours_stays() {
    // Portuguese "um" (one) spoken straight into its noun.
    let words = vec![
      Word::new("Tenho", 0.0, 0.3),
      Word::new("um", 0.31, 0.4),
      Word::new("carro.", 0.41, 0.8),
    ];
    assert_eq!(tidy(&words, &TidyOptions::all("")).text, "Tenho um carro.");
  }

  #[test]
  fn a_gated_filler_opening_the_dictation_is_still_a_word() {
    assert_eq!(tidied("Er geht nach Hause."), "Er geht nach Hause.");
    assert_eq!(tidied("Er, | I mean yes."), "I mean yes.");
  }

  #[test]
  fn three_or_more_repeats_collapse_but_two_stay() {
    assert_eq!(tidied("I I I think so."), "I think so.");
    assert_eq!(
      tidied("I said that that is fine."),
      "I said that that is fine."
    );
  }

  #[test]
  fn spoken_punctuation_needs_a_pause_on_both_sides() {
    assert_eq!(tidied("Hello | comma | world"), "Hello, world");
    assert_eq!(tidied("Is it ready | question mark"), "Is it ready?");
    assert_eq!(tidied("a comma separated list"), "a comma separated list");
  }

  #[test]
  fn a_spoken_mark_replaces_the_models_own_and_capitalises_after_a_period() {
    assert_eq!(tidied("Done, | period | next step"), "Done. Next step");
    assert_eq!(
      tidied("First line | new line | second line"),
      "First line\nSecond line"
    );
  }

  #[test]
  fn scratch_that_removes_the_phrase_before_it() {
    assert_eq!(
      tidied("See you at five. Meet at noon | scratch that | at one."),
      "See you at five. At one."
    );
    assert_eq!(tidied("I'll scratch that itch"), "I'll scratch that itch");
  }

  #[test]
  fn a_scratch_right_after_a_closed_sentence_removes_that_sentence() {
    assert_eq!(
      tidied("Done today. Lunch at noon. | scratch that | at one."),
      "Done today. At one."
    );
  }

  #[test]
  fn a_misheard_scratch_counts_only_between_two_pauses() {
    assert_eq!(
      tidied("Lunch is at noon. | Delete at | Lunch is at one."),
      "Lunch is at one."
    );
    assert_eq!(tidied("Please delete at once."), "Please delete at once.");
  }

  #[test]
  fn the_send_phrase_said_last_after_a_pause_is_found_and_dropped() {
    let result = tidy(
      &said("run the tests, | send it."),
      &TidyOptions::all("send it, press enter"),
    );
    assert!(result.send);
    assert_eq!(result.text, "run the tests");
    let mid = tidy(
      &said("send it to Anna please"),
      &TidyOptions::all("send it"),
    );
    assert!(!mid.send);
    assert_eq!(mid.text, "send it to Anna please");
  }

  #[test]
  fn options_off_changes_nothing() {
    let result = tidy(
      &said("um I I I | comma | scratch that"),
      &TidyOptions::none(),
    );
    assert_eq!(result.text, "um I I I comma scratch that");
    assert_eq!(result.removed(), 0);
  }

  #[test]
  fn marks_point_at_what_will_change_in_the_draft() {
    let result = tidy(
      &said("Um, hello | comma | world | send it"),
      &TidyOptions::all("send it"),
    );
    let (draft, marks) = result.draft_with_marks();
    assert_eq!(draft, "Um, hello comma world send it");
    let kinds: Vec<(&str, MarkKind)> = marks
      .iter()
      .map(|mark| (&draft[mark.start..mark.end], mark.kind))
      .collect();
    assert_eq!(
      kinds,
      vec![
        ("Um,", MarkKind::Filler),
        ("comma", MarkKind::Punctuation),
        ("send it", MarkKind::Send),
      ]
    );
    assert_eq!(result.text, "Hello, world");
  }

  #[test]
  fn a_period_stamped_after_the_pause_does_not_hide_it() {
    // Parakeet stamps "." where it emits it: after the pause, at "Send".
    let words = vec![
      Word::new("Run", 0.0, 0.2),
      Word::new("the", 0.3, 0.4),
      Word::new("test", 0.5, 0.8),
      Word::new(".", 1.55, 1.6),
      Word::new("Send", 1.6, 1.8),
      Word::new("it", 1.9, 2.0),
      Word::new(".", 2.0, 2.05),
    ];
    let result = tidy(&words, &TidyOptions::all("send it"));
    assert!(result.send);
    assert_eq!(result.text, "Run the test.");
  }

  #[test]
  fn kept_words_carry_the_marks_and_their_timings() {
    let result = tidy(
      &said("Hello | comma | world | new line | next"),
      &TidyOptions::all(""),
    );
    let kept: Vec<&str> = result.kept.iter().map(|word| word.text.as_str()).collect();
    assert_eq!(kept, vec!["Hello,", "world\n", "Next"]);
    assert_eq!(result.text, "Hello, world\nNext");
    assert!(result.kept[0].end > 0.3);
  }

  #[test]
  fn removed_counts_only_what_was_dropped() {
    let result = tidy(&said("uh the the the plan"), &TidyOptions::all(""));
    assert_eq!(result.text, "The plan");
    assert_eq!(result.removed(), 3);
  }
}
