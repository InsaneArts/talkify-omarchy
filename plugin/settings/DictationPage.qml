import QtQuick
import qs.Commons
import qs.Ui

// Where the text goes and what happens to it on the way: insertion, the
// Tidy pass, the send phrases, media while dictating, and the history that
// Paste again and Retry reach.
SettingsPage {
  id: page

  readonly property bool toClipboardOnly: value("insertion.destination", "insert") === "clipboard"
  readonly property bool tidy: value("tidy.enabled", true) === true

  PageTitle {
    ctx: page.ctx
    text: "Dictation"
  }

  ChoiceRow {
    ctx: page.ctx
    title: "WHERE THE TEXT GOES"
    key: "insertion.destination"
    fallback: "insert"
    options: [
      { value: "insert", label: "Insert into the app" },
      { value: "clipboard", label: "Copy to the clipboard" },
      { value: "both", label: "Insert and copy" }
    ]
  }

  ChoiceRow {
    visible: !page.toClipboardOnly
    ctx: page.ctx
    title: "HOW IT IS INSERTED"
    key: "insertion.method"
    fallback: "paste"
    options: [
      { value: "paste", label: "Paste" },
      { value: "type", label: "Type it out" }
    ]
  }

  ToggleRow {
    visible: !page.toClipboardOnly
    ctx: page.ctx
    label: "Insert while speaking"
    description: page.value("insertion.live", false)
      ? "Words land in the window as soon as they stop changing; a pause puts the whole phrase in"
      : "Off: the text lands when you finish"
    key: "insertion.live"
  }

  SliderRow {
    visible: page.value("insertion.live", false) === true && !page.toClipboardOnly
    ctx: page.ctx
    title: "PAUSE BEFORE A PHRASE GOES IN"
    key: "insertion.live_pause_ms"
    fallback: 600
    minimum: 300
    maximum: 1500
    step: 50
    suffix: " ms"
    description: "Shorter feels quicker; longer waits out a breath in the middle of a sentence."
  }

  ToggleRow {
    ctx: page.ctx
    label: "Live draft"
    description: "Show the words on the HUD while you speak"
    key: "engine.live_draft"
    fallback: true
  }

  ToggleRow {
    ctx: page.ctx
    label: "Add a space after"
    description: "So the next dictation does not glue onto this one"
    key: "insertion.trailing_space"
    fallback: true
  }

  Heading {
    ctx: page.ctx
    text: "TIDY PASS"
    topPadding: Style.space(6)
  }

  ToggleRow {
    ctx: page.ctx
    label: "Tidy what the Speech Model heard"
    description: "Removes and punctuates by rule, with no model and no wait. It never writes a word you did not say."
    key: "tidy.enabled"
    fallback: true
  }

  // The four passes as one indented block, so it reads as what the switch
  // above turns on.
  Column {
    visible: page.tidy
    width: parent.width
    leftPadding: Style.space(14)
    spacing: Style.space(8)

    TidyToggle {
      label: "Filler words"
      description: "um, so the plan is… → so the plan is…"
      key: "tidy.fillers"
    }
    TidyToggle {
      label: "Stutters"
      description: "the the the plan → the plan"
      key: "tidy.stutters"
    }
    TidyToggle {
      label: "Spoken punctuation"
      description: "comma / new line become , and ↵ when you pause around them"
      key: "tidy.spoken_punctuation"
    }
    TidyToggle {
      label: "Scratch that"
      description: "“scratch that” removes the phrase before it"
      key: "tidy.scratch"
    }
  }

  Column {
    width: parent.width
    spacing: Style.space(8)

    Heading {
      ctx: page.ctx
      text: "SEND PHRASES"
    }

    TextField {
      id: sendPhrases
      width: parent.width
      text: String(page.value("tidy.send_phrases", "send it, press enter"))
      placeholderText: "send it, press enter"
      foreground: page.fg
      font.family: page.fontFamily
      font.pixelSize: Style.font.bodySmall
      onEditingFinished: {
        var next = text.split(",").map(function(p) { return p.trim() }).filter(function(p) { return p !== "" }).join(", ")
        if (next !== String(page.value("tidy.send_phrases", ""))) page.set("tidy.send_phrases", next)
      }
    }

    Caption {
      ctx: page.ctx
      strength: 0.6
      text: "Said last, after a pause, one of these presses Enter once the text lands, where the App rules let it: in terminals by default, so “run the tests, send it” submits."
    }
  }

  ChoiceRow {
    ctx: page.ctx
    title: "MEDIA WHILE DICTATING"
    key: "media.mode"
    fallback: "pause"
    options: [
      { value: "pause", label: "Pause it" },
      { value: "duck", label: "Turn it down" },
      { value: "off", label: "Leave it" }
    ]
  }

  Caption {
    ctx: page.ctx
    strength: 0.6
    text: page.value("media.mode", "pause") === "pause"
      ? "Players that are playing pause when you start and resume when you finish; the ones you had paused stay paused."
      : page.value("media.mode", "pause") === "duck"
        ? "The speakers drop while you talk and come back after."
        : "Nothing changes; the microphone may hear what is playing."
  }

  SliderRow {
    visible: page.value("media.mode", "pause") === "duck"
    ctx: page.ctx
    title: "TURN IT DOWN TO"
    key: "media.duck_to"
    fallback: 0.3
    minimum: 0
    maximum: 100
    step: 5
    suffix: "%"
    percent: true
  }

  ChoiceRow {
    ctx: page.ctx
    title: "CANCEL A SESSION THAT HEARS NOTHING"
    key: "engine.no_speech_timeout_ms"
    fallback: 0
    options: [
      { value: 0, label: "Never" },
      { value: 8000, label: "After 8 s" },
      { value: 15000, label: "After 15 s" }
    ]
  }

  Heading {
    ctx: page.ctx
    text: "HISTORY"
    topPadding: Style.space(6)
  }

  SliderRow {
    ctx: page.ctx
    title: "RECENT DICTATIONS KEPT"
    key: "history.size"
    fallback: 20
    minimum: 5
    maximum: 100
    step: 5
    description: "How far back Recent, Paste again and Retry reach. Retry also needs a dictation's audio, which only the newest few keep."
  }

  ToggleRow {
    ctx: page.ctx
    label: "Save to disk"
    description: page.value("history.save", false)
      ? "Each day's dictations also go into a text file that names the app they went to"
      : "Off: the history lives in memory and is gone when Talkify restarts"
    key: "history.save"
  }

  component TidyToggle: ToggleRow {
    ctx: page.ctx
    fallback: true
    width: parent ? parent.width - Style.space(14) : 0
  }
}
