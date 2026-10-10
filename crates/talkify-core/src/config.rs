//! Every user preference, in one TOML file (`~/.config/talkify/config.toml`).
//! The daemon owns the file; the Settings panel changes it through
//! `config-set` and hears the result back as a `config` event. HUD-only
//! values are stored here too so there is one source of truth, even though
//! only the shell plugin reads them.
//!
//! Outside `[hud]`, whose unknown keys are the plugin's own settings, keys
//! the daemon does not know (those of features since dropped) are ignored
//! when the file is read and left out when it is next written.

use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Config {
  pub trigger: TriggerConfig,
  pub engine: EngineConfig,
  pub insertion: InsertionConfig,
  pub tidy: TidyConfig,
  pub vocab: VocabConfig,
  pub media: MediaConfig,
  pub history: HistoryConfig,
  pub insights: InsightsConfig,
  pub sounds: SoundConfig,
  pub hud: HudConfig,
  /// App rules by window class. `terminal` is a pseudo-class for every
  /// window Omarchy tags as a terminal.
  pub apps: std::collections::BTreeMap<String, AppRule>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct TriggerConfig {
  /// A Linux input key name, e.g. `KEY_RIGHTMETA` (Right Super).
  pub key: String,
  /// How long a modifier trigger must be held alone before dictation
  /// starts. Zero for keys nobody chords, like F13. Mouse buttons
  /// (`BTN_SIDE`, `BTN_EXTRA`) never wait.
  pub chord_guard_ms: u64,
  /// Open the microphone the moment the trigger goes down, while the chord
  /// guard decides, so the first word is never lost; the audio is thrown
  /// away if the press turns out to be a shortcut.
  pub preroll: bool,
}

/// The Tidy pass: rule-based cleanup of what the Speech Model heard. It only
/// removes and punctuates; it never writes a word that was not spoken.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct TidyConfig {
  pub enabled: bool,
  /// Drop um, uh, er and the like.
  pub fillers: bool,
  /// Collapse a word said three or more times in a row.
  pub stutters: bool,
  /// "comma", "period", "new line" between pauses become marks.
  pub spoken_punctuation: bool,
  /// "scratch that" / "delete that" removes the phrase before it.
  pub scratch: bool,
  /// Comma-separated phrases that, said last after a pause, press Enter
  /// where App rules allow it.
  pub send_phrases: String,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct VocabConfig {
  pub enabled: bool,
  /// Match preferred words by sound as well as spelling.
  pub fuzzy: bool,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct MediaConfig {
  /// `pause` pauses playing media for the session and resumes it after;
  /// `duck` lowers the output; `off` leaves it alone.
  pub mode: String,
  /// How far `duck` lowers the output, 0–1.
  pub duck_to: f64,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct HistoryConfig {
  /// How many recent dictations Paste again and Retry can reach.
  pub size: u64,
  /// Also write each day's dictations to a text file. Off by default.
  pub save: bool,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct InsightsConfig {
  pub enabled: bool,
  /// The typing speed "time saved" compares against, words per minute.
  pub typing_wpm: u64,
}

/// What changes in one app. Every field is optional; unset inherits the
/// global setting.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct AppRule {
  #[serde(skip_serializing_if = "Option::is_none")]
  pub tidy: Option<bool>,
  /// Keep the sentence-ending period the model adds to the last sentence.
  #[serde(skip_serializing_if = "Option::is_none")]
  pub final_period: Option<bool>,
  /// `sentence` keeps the model's capitals, `lower` lowercases everything.
  #[serde(skip_serializing_if = "Option::is_none")]
  pub case: Option<String>,
  #[serde(skip_serializing_if = "Option::is_none")]
  pub trailing_space: Option<bool>,
  /// `never`, `spoken` (a send phrase said last presses Enter) or `always`.
  #[serde(skip_serializing_if = "Option::is_none")]
  pub send: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct EngineConfig {
  pub model: String,
  /// Re-decode the growing recording while speaking to show a live draft.
  pub live_draft: bool,
  /// Cancel a session that hears no words for this long. Zero disables it.
  pub no_speech_timeout_ms: u64,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct InsertionConfig {
  /// `insert` pastes into the window and restores the clipboard after;
  /// `clipboard` only copies, for deciding where it lands yourself; `both`
  /// pastes and leaves the text on the clipboard.
  pub destination: String,
  /// `paste` puts the text on the clipboard and sends the paste shortcut;
  /// `type` types it with a virtual keyboard.
  pub method: String,
  /// Insert while speaking: words land as soon as they stop changing, and
  /// a pause puts the whole phrase in.
  pub live: bool,
  /// How long a pause has to be before the phrase before it is inserted.
  pub live_pause_ms: u64,
  /// Append a space so the next dictation does not glue onto this one.
  pub trailing_space: bool,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct SoundConfig {
  pub enabled: bool,
  /// `synth8`, `chime` or `click`: the file name prefix in `sounds/`.
  pub set: String,
  pub volume: f64,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct HudConfig {
  /// `waveform`, `glow`, `glow-draft` or `compact`.
  pub visual: String,
  /// `chart-line`, `capsules`, `dots`, `filled` or `curve`.
  pub waveform_style: String,
  /// `slide`, `unfurl`, `bloom` or `drift`.
  pub reveal: String,
  /// `grow-down`, `tail-only` or `shrink-to-fit`.
  pub long_draft: String,
  pub scale: f64,
  /// Where the HUD appears: `notch` (from the top edge) is Talkify's own;
  /// the plugin defines the rest.
  pub placement: String,
  /// Whether the HUD shows the words: `auto` keeps each visual's own
  /// choice, `on` and `off` override it.
  pub words: String,
  /// Edge Glow's palette.
  pub glow_palette: String,
  /// Concave corners where the shape meets the screen edge.
  pub fillets: bool,
  /// Opacity of the hairline around the shape, 0 for none.
  pub edge: f64,
  /// HUD font family; empty uses the Omarchy font.
  pub font: String,
  /// Settings the shell plugin adds for its own visuals. The daemon stores
  /// and reports them without knowing what they mean, so a new HUD option
  /// needs no daemon change.
  #[serde(flatten)]
  pub extra: std::collections::BTreeMap<String, serde_json::Value>,
}

impl Default for TriggerConfig {
  fn default() -> Self {
    Self {
      key: "KEY_RIGHTMETA".into(),
      chord_guard_ms: 150,
      preroll: true,
    }
  }
}

impl Default for TidyConfig {
  fn default() -> Self {
    Self {
      enabled: true,
      fillers: true,
      stutters: true,
      spoken_punctuation: true,
      scratch: true,
      send_phrases: "send it, press enter".into(),
    }
  }
}

impl Default for VocabConfig {
  fn default() -> Self {
    Self {
      enabled: true,
      fuzzy: true,
    }
  }
}

impl Default for MediaConfig {
  fn default() -> Self {
    Self {
      mode: "pause".into(),
      duck_to: 0.3,
    }
  }
}

impl Default for HistoryConfig {
  fn default() -> Self {
    Self {
      size: 20,
      save: false,
    }
  }
}

impl Default for InsightsConfig {
  fn default() -> Self {
    Self {
      enabled: true,
      typing_wpm: 40,
    }
  }
}

/// Terminals take commands, not prose: no closing period, and "send it"
/// presses Enter, so "run the tests, send it" lands in a coding agent and
/// submits.
pub fn default_apps() -> std::collections::BTreeMap<String, AppRule> {
  let mut apps = std::collections::BTreeMap::new();
  apps.insert(
    "terminal".into(),
    AppRule {
      final_period: Some(false),
      send: Some("spoken".into()),
      ..AppRule::default()
    },
  );
  apps
}

impl Default for EngineConfig {
  fn default() -> Self {
    Self {
      model: "parakeet-tdt-0.6b-v3-int8".into(),
      live_draft: true,
      no_speech_timeout_ms: 0,
    }
  }
}

impl Default for InsertionConfig {
  fn default() -> Self {
    Self {
      destination: "insert".into(),
      method: "paste".into(),
      live: false,
      live_pause_ms: 600,
      trailing_space: true,
    }
  }
}

impl Default for SoundConfig {
  fn default() -> Self {
    Self {
      enabled: true,
      set: "synth8".into(),
      volume: 0.5,
    }
  }
}

impl Default for HudConfig {
  fn default() -> Self {
    Self {
      visual: "waveform".into(),
      waveform_style: "chart-line".into(),
      reveal: "slide".into(),
      long_draft: "grow-down".into(),
      scale: 1.0,
      placement: "pill".into(),
      words: "auto".into(),
      glow_palette: "spectrum".into(),
      fillets: true,
      edge: 0.09,
      font: String::new(),
      extra: Default::default(),
    }
  }
}

impl Default for Config {
  fn default() -> Self {
    Self {
      trigger: TriggerConfig::default(),
      engine: EngineConfig::default(),
      insertion: InsertionConfig::default(),
      tidy: TidyConfig::default(),
      vocab: VocabConfig::default(),
      media: MediaConfig::default(),
      history: HistoryConfig::default(),
      insights: InsightsConfig::default(),
      sounds: SoundConfig::default(),
      hud: HudConfig::default(),
      apps: default_apps(),
    }
  }
}

#[derive(Debug, PartialEq, Eq)]
pub enum SetError {
  UnknownKey(String),
  BadValue { key: String, value: String },
}

impl std::fmt::Display for SetError {
  fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
    match self {
      SetError::UnknownKey(key) => write!(f, "unknown setting {key}"),
      SetError::BadValue { key, value } => write!(f, "{value:?} is not a valid {key}"),
    }
  }
}

impl Config {
  pub fn from_toml(text: &str) -> Result<Self, toml::de::Error> {
    let mut config: Self = toml::from_str(text)?;
    // A rule whose only fields were dropped keys is empty now; kept, it
    // would still name itself on the HUD while changing nothing.
    config.apps.retain(|_, rule| *rule != AppRule::default());
    Ok(config)
  }

  pub fn to_toml(&self) -> String {
    toml::to_string_pretty(self).expect("config always serializes")
  }

  pub fn to_json(&self) -> serde_json::Value {
    serde_json::to_value(self).expect("config always serializes")
  }

  /// Sets one value by its dotted key (`hud.visual`), parsing `value` to the
  /// field's type. The whole config goes through serde so a new field needs
  /// no code here.
  pub fn set(&mut self, key: &str, value: &str) -> Result<(), SetError> {
    if let Some(rest) = key.strip_prefix("apps.") {
      return self.set_app(key, rest, value);
    }
    let mut json = self.to_json();
    let mut path = key.split('.');
    let (Some(section), Some(field), None) = (path.next(), path.next(), path.next()) else {
      return Err(SetError::UnknownKey(key.into()));
    };
    let bad = || SetError::BadValue {
      key: key.into(),
      value: value.into(),
    };
    if section == "hud"
      && let Some(hud) = json.get_mut("hud").and_then(|hud| hud.as_object_mut())
      && !hud.contains_key(field)
    {
      hud.insert(field.into(), inferred(value));
      *self = serde_json::from_value(json).map_err(|_| bad())?;
      return Ok(());
    }
    let slot = json
      .get_mut(section)
      .and_then(|s| s.get_mut(field))
      .ok_or_else(|| SetError::UnknownKey(key.into()))?;
    *slot = match slot {
      serde_json::Value::Bool(_) => serde_json::Value::Bool(value.parse().map_err(|_| bad())?),
      serde_json::Value::Number(n) if n.is_u64() => {
        serde_json::Value::from(value.parse::<u64>().map_err(|_| bad())?)
      }
      serde_json::Value::Number(_) => {
        let number = value.parse::<f64>().map_err(|_| bad())?;
        serde_json::Number::from_f64(number)
          .map(serde_json::Value::Number)
          .ok_or_else(bad)?
      }
      _ => serde_json::Value::String(value.into()),
    };
    *self = serde_json::from_value(json).map_err(|_| bad())?;
    Ok(())
  }
}

impl Config {
  /// `apps.<class>.<field>`: classes contain dots (`com.mitchellh.ghostty`),
  /// so the field is the last segment and the class everything before it.
  /// `apps.<class>.<field>` set to "" clears that field; a rule left with no
  /// fields is removed.
  fn set_app(&mut self, key: &str, rest: &str, value: &str) -> Result<(), SetError> {
    let Some((class, field)) = rest.rsplit_once('.') else {
      return Err(SetError::UnknownKey(key.into()));
    };
    if class.is_empty() {
      return Err(SetError::UnknownKey(key.into()));
    }
    let bad = || SetError::BadValue {
      key: key.into(),
      value: value.into(),
    };
    let flag = |value: &str| -> Result<Option<bool>, SetError> {
      if value.is_empty() {
        Ok(None)
      } else {
        value.parse().map(Some).map_err(|_| bad())
      }
    };
    let choice = |value: &str, allowed: &[&str]| -> Result<Option<String>, SetError> {
      if value.is_empty() {
        Ok(None)
      } else if allowed.contains(&value) {
        Ok(Some(value.into()))
      } else {
        Err(bad())
      }
    };
    let mut rule = self.apps.get(class).cloned().unwrap_or_default();
    match field {
      "tidy" => rule.tidy = flag(value)?,
      "final_period" => rule.final_period = flag(value)?,
      "trailing_space" => rule.trailing_space = flag(value)?,
      "case" => rule.case = choice(value, &["sentence", "lower"])?,
      "send" => rule.send = choice(value, &["never", "spoken", "always"])?,
      _ => return Err(SetError::UnknownKey(key.into())),
    }
    if rule == AppRule::default() {
      self.apps.remove(class);
    } else {
      self.apps.insert(class.into(), rule);
    }
    Ok(())
  }
}

/// A plugin-defined HUD setting has no declared type, so the value says what
/// it is.
fn inferred(value: &str) -> serde_json::Value {
  if let Ok(flag) = value.parse::<bool>() {
    return serde_json::Value::Bool(flag);
  }
  if let Ok(number) = value.parse::<f64>()
    && let Some(number) = serde_json::Number::from_f64(number)
  {
    return serde_json::Value::Number(number);
  }
  serde_json::Value::String(value.into())
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn an_empty_file_is_the_defaults() {
    assert_eq!(Config::from_toml("").unwrap(), Config::default());
  }

  #[test]
  fn a_partial_file_keeps_defaults_for_the_rest() {
    let config = Config::from_toml("[hud]\nvisual = \"glow\"\n").unwrap();
    assert_eq!(config.hud.visual, "glow");
    assert_eq!(config.hud.reveal, "slide");
    assert_eq!(config.trigger.key, "KEY_RIGHTMETA");
  }

  #[test]
  fn defaults_survive_a_toml_round_trip() {
    let config = Config::default();
    assert_eq!(Config::from_toml(&config.to_toml()).unwrap(), config);
  }

  #[test]
  fn set_parses_by_field_type() {
    let mut config = Config::default();
    config.set("hud.visual", "glow").unwrap();
    config.set("sounds.enabled", "false").unwrap();
    config.set("sounds.volume", "0.25").unwrap();
    config.set("trigger.chord_guard_ms", "0").unwrap();
    assert_eq!(config.hud.visual, "glow");
    assert!(!config.sounds.enabled);
    assert_eq!(config.sounds.volume, 0.25);
    assert_eq!(config.trigger.chord_guard_ms, 0);
  }

  #[test]
  fn plugin_hud_settings_are_kept_typed_and_survive_the_file() {
    let mut config = Config::default();
    config.set("hud.pill_offset", "24").unwrap();
    config.set("hud.ghost_eyes", "true").unwrap();
    config.set("hud.caption_font", "Iosevka").unwrap();
    let json = config.to_json();
    assert_eq!(json["hud"]["pill_offset"], serde_json::json!(24.0));
    assert_eq!(json["hud"]["ghost_eyes"], serde_json::json!(true));
    assert_eq!(json["hud"]["caption_font"], serde_json::json!("Iosevka"));
    let reread = Config::from_toml(&config.to_toml()).unwrap();
    assert_eq!(reread.hud.extra, config.hud.extra);
    // Once known, the type sticks.
    assert!(config.set("hud.ghost_eyes", "maybe").is_err());
  }

  #[test]
  fn app_rules_are_set_by_class_even_with_dots_in_it() {
    let mut config = Config::default();
    config
      .set("apps.com.mitchellh.ghostty.send", "always")
      .unwrap();
    config
      .set("apps.com.mitchellh.ghostty.final_period", "false")
      .unwrap();
    let rule = &config.apps["com.mitchellh.ghostty"];
    assert_eq!(rule.send.as_deref(), Some("always"));
    assert_eq!(rule.final_period, Some(false));
    assert_eq!(rule.tidy, None);
    assert!(config.set("apps.slack.send", "sometimes").is_err());
    assert!(config.set("apps.slack.colour", "red").is_err());
    // Clearing every field removes the rule.
    config.set("apps.com.mitchellh.ghostty.send", "").unwrap();
    config
      .set("apps.com.mitchellh.ghostty.final_period", "")
      .unwrap();
    assert!(!config.apps.contains_key("com.mitchellh.ghostty"));
  }

  #[test]
  fn terminals_get_their_rule_by_default_and_it_survives_the_file() {
    let config = Config::default();
    assert_eq!(config.apps["terminal"].send.as_deref(), Some("spoken"));
    let reread = Config::from_toml(&config.to_toml()).unwrap();
    assert_eq!(reread, config);
  }

  /// A file written before Prompt Shaping and Edit by voice were dropped:
  /// their keys are ignored, a rule left empty by them goes, and the next
  /// save writes none of them.
  #[test]
  fn a_config_with_the_dropped_shaping_and_edit_keys_still_loads() {
    let legacy = r#"
[trigger]
key = "KEY_RIGHTMETA"
chord_guard_ms = 120
preroll = true
edit_key = "KEY_RIGHTALT"

[shaping]
enabled = true
server = "http://127.0.0.1:11434"
model = "qwen3:1.7b"
prompt = "tighten-grammar"
budget_ms = 1500
min_words = 4

[hud]
visual = "glow"

[apps.terminal]
final_period = false
send = "spoken"
shaping = false

[apps.thunderbird]
prompt = "bullet-lists"
shaping = true
"#;
    let config = Config::from_toml(legacy).unwrap();
    assert_eq!(config.trigger.key, "KEY_RIGHTMETA");
    assert_eq!(config.trigger.chord_guard_ms, 120);
    assert_eq!(config.hud.visual, "glow");
    assert_eq!(config.apps["terminal"].send.as_deref(), Some("spoken"));
    assert_eq!(config.apps["terminal"].final_period, Some(false));
    assert!(!config.apps.contains_key("thunderbird"));
    let saved = config.to_toml();
    for dropped in ["shaping", "edit_key", "prompt", "thunderbird"] {
      assert!(
        !saved.contains(dropped),
        "{dropped} survived the save:\n{saved}"
      );
    }
    assert_eq!(Config::from_toml(&saved).unwrap(), config);
    assert!(matches!(
      config.clone().set("shaping.enabled", "true"),
      Err(SetError::UnknownKey(_))
    ));
    assert!(config.clone().set("apps.Slack.shaping", "true").is_err());
  }

  #[test]
  fn set_rejects_unknown_keys_and_bad_values() {
    let mut config = Config::default();
    assert!(matches!(
      config.set("engine.nope", "1"),
      Err(SetError::UnknownKey(_))
    ));
    assert!(matches!(
      config.set("hud", "1"),
      Err(SetError::UnknownKey(_))
    ));
    assert!(matches!(
      config.set("sounds.enabled", "maybe"),
      Err(SetError::BadValue { .. })
    ));
    assert!(matches!(
      config.set("trigger.chord_guard_ms", "-5"),
      Err(SetError::BadValue { .. })
    ));
    assert_eq!(config, Config::default());
  }
}
