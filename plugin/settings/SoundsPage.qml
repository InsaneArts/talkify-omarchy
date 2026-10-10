import QtQuick
import qs.Commons

SettingsPage {
  id: page

  readonly property bool soundsOn: value("sounds.enabled", true) === true

  PageTitle {
    ctx: page.ctx
    text: "Sounds"
  }

  ToggleRow {
    ctx: page.ctx
    label: "Session sounds"
    description: "When the microphone opens, when speech ends, and when the text lands"
    key: "sounds.enabled"
    fallback: true
  }

  ChoiceRow {
    visible: page.soundsOn
    ctx: page.ctx
    title: "SOUND SET"
    key: "sounds.set"
    fallback: "synth8"
    options: [
      { value: "synth8", label: "Synth" },
      { value: "chime", label: "Chime" },
      { value: "click", label: "Click" }
    ]
  }

  SliderRow {
    visible: page.soundsOn
    ctx: page.ctx
    title: "VOLUME"
    key: "sounds.volume"
    fallback: 0.5
    minimum: 0
    maximum: 100
    step: 5
    suffix: "%"
    percent: true
  }
}
