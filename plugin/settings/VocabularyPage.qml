import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Format.js" as Format

// The vocabulary file: words to prefer, replacements and snippets, how often
// each one fired, and Teach, which adds to it from a correction.
SettingsPage {
  id: page

  readonly property var entries: (svc && svc.vocab) || []
  readonly property string path: (svc && svc.vocabPath) || ""
  readonly property bool fuzzy: value("vocab.fuzzy", true) === true
  readonly property var hint: Format.vocabHint(field.text, fuzzy)
  // Lines are shown as typed: a coding font's ligatures would draw "->" and
  // "=>" as arrows, and the file needs the characters.
  readonly property var literal: ({ "calt": 0, "liga": 0 })

  function add() {
    if (!hint.ok) return
    svc.vocabAdd(field.text.trim())
    field.text = ""
  }

  function kindLabel(kind) {
    switch (kind) {
    case "replacement": return "replace"
    case "snippet": return "snippet"
    default: return "word"
    }
  }

  PageTitle {
    ctx: page.ctx
    text: "Vocabulary"
  }

  Caption {
    ctx: page.ctx
    text: "Words Talkify should spell your way. One line each, in three forms:"
  }

  Column {
    width: parent.width
    spacing: Style.space(6)

    Repeater {
      model: [
        { line: "Hyprland", what: "a word to prefer over whatever sounds or looks like it" },
        { line: "omachi -> Omarchy", what: "what Talkify hears, and how to write it" },
        { line: "my email => tornike@…", what: "a snippet: say the left, get the right" }
      ]
      delegate: Row {
        id: form
        required property var modelData
        width: parent.width
        spacing: Style.space(12)

        Text {
          width: Style.space(170)
          textFormat: Text.PlainText
          text: form.modelData.line
          color: page.fg
          font.family: page.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          font.features: page.literal
        }

        Text {
          width: parent.width - Style.space(182)
          wrapMode: Text.Wrap
          textFormat: Text.PlainText
          text: form.modelData.what
          color: page.fg
          opacity: 0.7
          font.family: page.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  Item {
    width: parent.width
    implicitHeight: Math.max(field.implicitHeight, addButton.implicitHeight)

    TextField {
      id: field
      anchors.left: parent.left
      anchors.right: addButton.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      placeholderText: "Add a word, a heard -> written pair, or a snippet"
      foreground: page.fg
      font.family: page.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.features: page.literal
      onAccepted: page.add()
    }

    Button {
      id: addButton
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: "Add"
      bordered: true
      focusable: true
      enabled: page.hint.ok
      opacity: enabled ? 1 : 0.45
      foreground: page.fg
      fontFamily: page.fontFamily
      fontSize: Style.font.bodySmall
      onClicked: page.add()
    }
  }

  Caption {
    visible: page.hint.text !== ""
    ctx: page.ctx
    strength: page.hint.ok ? 0.8 : 1
    color: page.hint.ok ? page.fg : Color.urgent
    text: page.hint.text
  }

  ToggleRow {
    ctx: page.ctx
    label: "Use the vocabulary"
    description: "Off: dictations land as the Speech Model and the Tidy pass leave them"
    key: "vocab.enabled"
    fallback: true
  }

  ToggleRow {
    visible: page.value("vocab.enabled", true) === true
    ctx: page.ctx
    label: "Match by sound"
    description: "A preferred word also replaces words that sound like it, not only near-spellings: “omachi” finds Omarchy"
    key: "vocab.fuzzy"
    fallback: true
  }

  Heading {
    ctx: page.ctx
    topPadding: Style.space(6)
    text: page.entries.length === 0 ? "ENTRIES" : Format.count(page.entries.length, "ENTRY", "ENTRIES")
  }

  Caption {
    visible: page.entries.length === 0
    ctx: page.ctx
    strength: 0.6
    text: "Nothing here yet. Add a line above, or teach one from a correction."
  }

  Repeater {
    model: page.entries

    delegate: Item {
      id: entry
      required property var modelData
      width: page.width
      implicitHeight: Math.max(badge.implicitHeight, remove.implicitHeight, line.implicitHeight) + Style.space(4)

      Rectangle {
        id: badge
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(64)
        implicitHeight: badgeText.implicitHeight + Style.space(6)
        radius: Style.cornerRadius
        color: entry.modelData.kind === "word" ? "transparent" : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, entry.modelData.kind === "snippet" ? 0.28 : 0.14)
        border.width: 1
        border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.55)

        Text {
          id: badgeText
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: page.kindLabel(entry.modelData.kind)
          color: page.fg
          font.family: page.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Text {
        id: line
        anchors.left: badge.right
        anchors.leftMargin: Style.space(10)
        anchors.right: hits.left
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: entry.modelData.line
        color: page.fg
        font.family: page.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.features: page.literal
      }

      // A line that never fires is a candidate to remove: a long list costs
      // accuracy, so the count is what tells you which.
      Text {
        id: hits
        anchors.right: remove.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: entry.modelData.hits > 0 ? Format.count(entry.modelData.hits, "hit") : "unused"
        color: page.fg
        opacity: entry.modelData.hits > 0 ? 0.7 : 0.4
        font.family: page.fontFamily
        font.pixelSize: Style.font.caption
      }

      Button {
        id: remove
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: "Remove"
        focusable: true
        verticalPadding: Style.space(3)
        foreground: page.fg
        fontFamily: page.fontFamily
        fontSize: Style.font.caption
        onClicked: page.svc.vocabRemove(entry.modelData.line)
      }
    }
  }

  Item {
    visible: page.path !== ""
    width: parent.width
    implicitHeight: Math.max(pathText.implicitHeight, openFile.implicitHeight)

    Text {
      id: pathText
      anchors.left: parent.left
      anchors.right: openFile.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideMiddle
      textFormat: Text.PlainText
      text: page.path.replace(Quickshell.env("HOME"), "~")
      color: page.fg
      opacity: 0.6
      font.family: page.fontFamily
      font.pixelSize: Style.font.caption
    }

    Button {
      id: openFile
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: "Open file"
      bordered: true
      focusable: true
      foreground: page.fg
      fontFamily: page.fontFamily
      fontSize: Style.font.bodySmall
      onClicked: {
        Quickshell.execDetached(["xdg-open", page.path])
        page.ctx.closeRequested()
      }
    }
  }

  Card {
    ctx: page.ctx

    Heading {
      ctx: page.ctx
      text: "TEACH"
    }

    Caption {
      ctx: page.ctx
      text: "After a wrong word lands, fix it in the app, select your correction and run talkify teach (bind it to a key). Talkify finds the word it misheard and adds a heard -> written line here."
    }

    CommandChip {
      ctx: page.ctx
      command: "talkify teach"
    }

    Caption {
      visible: !!(page.svc && page.svc.taught)
      ctx: page.ctx
      strength: 0.6
      text: page.svc && page.svc.taught
        ? "Last taught: " + page.svc.taught.heard + " → " + page.svc.taught.written
        : ""
    }
  }
}
