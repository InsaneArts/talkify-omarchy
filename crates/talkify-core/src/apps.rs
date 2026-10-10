//! App rules: what changes when the text is for one app. The window class
//! comes from Hyprland when the session starts; `terminal` is a pseudo-class
//! for every window Omarchy tags as a terminal. A class's own rule wins over
//! the terminal rule, which wins over the global settings.

use crate::config::{AppRule, Config};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Send {
  Never,
  /// A send phrase said last presses Enter.
  Spoken,
  Always,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Rules {
  /// The rule set in force by name: the class, "terminal", or "" for none.
  pub name: String,
  pub tidy: bool,
  pub final_period: bool,
  pub lowercase: bool,
  pub trailing_space: bool,
  pub send: Send,
}

pub fn resolve(config: &Config, class: &str, is_terminal: bool) -> Rules {
  let mut rules = Rules {
    name: String::new(),
    tidy: config.tidy.enabled,
    final_period: true,
    lowercase: false,
    trailing_space: config.insertion.trailing_space,
    send: Send::Never,
  };
  let mut layer = |name: &str, rule: &AppRule| {
    rules.name = name.to_string();
    if let Some(tidy) = rule.tidy {
      rules.tidy = tidy;
    }
    if let Some(period) = rule.final_period {
      rules.final_period = period;
    }
    if let Some(case) = &rule.case {
      rules.lowercase = case == "lower";
    }
    if let Some(space) = rule.trailing_space {
      rules.trailing_space = space;
    }
    if let Some(send) = &rule.send {
      rules.send = match send.as_str() {
        "spoken" => Send::Spoken,
        "always" => Send::Always,
        _ => Send::Never,
      };
    }
  };
  if is_terminal && let Some(rule) = config.apps.get("terminal") {
    layer("terminal", rule);
  }
  if !class.is_empty()
    && let Some(rule) = config.apps.get(class)
  {
    layer(class, rule);
  }
  rules
}

impl Rules {
  /// The finishing touches App rules make to text about to land.
  pub fn format(&self, text: &str) -> String {
    let mut text = text.trim_end().to_string();
    if !self.final_period && text.ends_with('.') && !text.ends_with("...") {
      text.pop();
    }
    if self.lowercase {
      text = text.to_lowercase();
    }
    text
  }

  /// For a chunk live insertion lands mid-dictation: case only. The final
  /// period belongs to the end of the dictation; applied to every chunk it
  /// would strip each sentence end that happens to close one.
  pub fn format_chunk(&self, text: &str) -> String {
    if self.lowercase {
      text.to_lowercase()
    } else {
      text.to_string()
    }
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn without_rules_the_global_settings_apply() {
    let config = Config::default();
    let rules = resolve(&config, "org.mozilla.firefox", false);
    assert_eq!(rules.name, "");
    assert!(rules.final_period && rules.tidy && rules.trailing_space);
    assert_eq!(rules.send, Send::Never);
    assert_eq!(rules.format("Hello there."), "Hello there.");
  }

  #[test]
  fn terminals_drop_the_final_period_and_send_on_the_spoken_phrase() {
    let config = Config::default();
    let rules = resolve(&config, "com.mitchellh.ghostty", true);
    assert_eq!(rules.name, "terminal");
    assert_eq!(rules.send, Send::Spoken);
    assert_eq!(rules.format("run the tests."), "run the tests");
    assert_eq!(rules.format("wait..."), "wait...");
  }

  #[test]
  fn a_live_chunk_keeps_its_periods_even_where_the_end_would_drop_one() {
    let rules = resolve(&Config::default(), "foot", true);
    assert_eq!(rules.format_chunk("Done. Next step."), "Done. Next step.");
    assert_eq!(rules.format("Done. Next step."), "Done. Next step");
  }

  #[test]
  fn a_class_rule_wins_over_the_terminal_rule() {
    let mut config = Config::default();
    config
      .set("apps.com.mitchellh.ghostty.send", "always")
      .unwrap();
    config
      .set("apps.com.mitchellh.ghostty.case", "lower")
      .unwrap();
    let rules = resolve(&config, "com.mitchellh.ghostty", true);
    assert_eq!(rules.name, "com.mitchellh.ghostty");
    assert_eq!(rules.send, Send::Always);
    // Inherited from the terminal rule underneath.
    assert!(!rules.final_period);
    assert_eq!(rules.format("Git Status."), "git status");
  }
}
