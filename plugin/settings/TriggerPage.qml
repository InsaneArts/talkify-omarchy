import QtQuick
import qs.Commons
import qs.Ui

// The Dictation Trigger, and how to pause a hands-free session.
SettingsPage {
  id: page

  readonly property string key: String(value("trigger.key", "KEY_RIGHTMETA"))
  readonly property bool mouseTrigger: key.indexOf("BTN_") === 0

  PageTitle {
    ctx: page.ctx
    text: "Dictation Trigger"
  }

  Caption {
    ctx: page.ctx
    text: "Hold the key to talk and let go to insert. Tap it once to keep listening hands-free, and tap again to finish. Escape cancels."
  }

  ChoiceRow {
    ctx: page.ctx
    title: "KEY"
    key: "trigger.key"
    fallback: "KEY_RIGHTMETA"
    options: page.ctx.triggerKeys
  }

  SliderRow {
    visible: !page.mouseTrigger
    ctx: page.ctx
    title: "HOLD BEFORE LISTENING"
    key: "trigger.chord_guard_ms"
    fallback: 150
    minimum: 0
    maximum: 400
    step: 10
    suffix: " ms"
    description: "A shortcut like Super+C never starts dictation: the key has to be held alone this long first."
  }

  Caption {
    visible: page.mouseTrigger
    ctx: page.ctx
    strength: 0.6
    text: "A mouse button is never the start of a shortcut, so it starts listening at once."
  }

  ToggleRow {
    ctx: page.ctx
    label: "Catch the first word"
    description: "Start listening the moment the key goes down, so the first word is never lost. If the press turns out to be a shortcut, what was heard is thrown away."
    key: "trigger.preroll"
    fallback: true
  }

  Heading {
    ctx: page.ctx
    text: "PAUSE"
    topPadding: Style.space(6)
  }

  Caption {
    ctx: page.ctx
    text: "In a hands-free session, talkify pause stops keeping what the microphone hears and keeps the draft; run it again to carry on. Bind it to a key for a phone call or a cough."
  }

  CommandChip {
    ctx: page.ctx
    command: "talkify pause"
  }

  Callout {
    visible: !!page.svc && page.svc.trigger === "commands"
    ctx: page.ctx
    urgent: true
    text: "Talkify cannot read the keyboard, so holding the key does nothing yet; only the tap bound in Hyprland works, and mouse buttons need the same access. Run  sudo usermod -aG input $USER  and log out and back in."
  }
}
