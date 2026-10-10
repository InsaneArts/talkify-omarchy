import QtQuick
import qs.Commons
import qs.Ui
import ".."
import "Format.js" as Format

// The last dictations, newest first, with the ways back to each: paste it
// again into the window focused now, copy it, decode its kept audio again,
// or paste what the Speech Model heard before the Tidy pass and the
// vocabulary touched it.
SettingsPage {
  id: page

  readonly property var items: (svc && svc.history) || []
  // Per dictation id: showing the raw words instead of what landed.
  property var rawShown: ({})
  // For "4 min ago": refreshed while the menu is open, never animated.
  property real now: Date.now()
  readonly property string keyName: ctx.keyLabel(value("trigger.key", "KEY_RIGHTMETA"))

  function showRaw(id, on) {
    var next = {}
    for (var k in rawShown) next[k] = rawShown[k]
    next[id] = on
    rawShown = next
  }

  // Paste and Retry insert into the focused window, which is this menu while
  // it is open, so they wait for it to hand the keyboard back.
  function paste(index, raw) { ctx.afterClose(function() { page.svc.pasteLast(index, raw) }) }
  function retry(index) { ctx.afterClose(function() { page.svc.retry(index) }) }

  Connections {
    target: page.ctx
    function onActiveChanged() { if (page.ctx.active) page.now = Date.now() }
  }

  Timer {
    interval: 30000
    repeat: true
    running: page.ctx.active
    onTriggered: page.now = Date.now()
  }

  Item {
    width: parent.width
    implicitHeight: Math.max(title.implicitHeight, clear.implicitHeight)

    PageTitle {
      id: title
      ctx: page.ctx
      anchors.verticalCenter: parent.verticalCenter
      text: "Recent"
    }

    Button {
      id: clear
      visible: page.items.length > 0
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: "Clear history"
      bordered: true
      focusable: true
      foreground: page.fg
      fontFamily: page.fontFamily
      fontSize: Style.font.bodySmall
      onClicked: page.ctx.confirm("Forget the recent dictations and their kept audio?", "Clear",
        function() { page.svc.clearHistory() })
    }
  }

  Caption {
    visible: page.items.length > 0
    ctx: page.ctx
    text: "Paste puts a dictation into the window you are in now; Retry decodes its audio again, for a release that came too early or a session cancelled by accident."
  }

  Repeater {
    model: page.items

    delegate: Card {
      id: entry
      required property var modelData
      required property int index
      readonly property bool hasRaw: !!modelData.raw && modelData.raw !== modelData.text
      readonly property bool raw: hasRaw && page.rawShown[modelData.id] === true

      ctx: page.ctx
      spacing: Style.space(6)

      Item {
        width: parent.width
        implicitHeight: Math.max(meta.implicitHeight, rawToggle.implicitHeight)

        Text {
          id: meta
          anchors.left: parent.left
          anchors.right: rawToggle.visible ? rawToggle.left : parent.right
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          elide: Text.ElideRight
          textFormat: Text.PlainText
          text: {
            var parts = [Format.timeAgo(entry.modelData.at, page.now), Format.appLabel(entry.modelData.app)]
            var rule = String(entry.modelData.rule || "")
            if (rule === "terminal") parts.push("terminal rules")
            else if (rule !== "" && rule === entry.modelData.app) parts.push("its App rules")
            else if (rule !== "") parts.push(Format.appLabel(rule) + " rules")
            if (entry.modelData.words > 0) parts.push(Format.count(entry.modelData.words, "word"))
            if (!entry.modelData.inserted) parts.push("on the clipboard")
            return parts.join("  ·  ")
          }
          color: page.fg
          opacity: 0.6
          font.family: page.fontFamily
          font.pixelSize: Style.font.caption
        }

        // What the Speech Model heard, before any cleanup: dim, because it
        // is the exception you look at, not the thing that landed.
        Button {
          id: rawToggle
          visible: entry.hasRaw
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: "raw"
          tooltipText: entry.raw ? "Show what landed" : "Show what the Speech Model heard"
          selected: entry.raw
          opacity: entry.raw ? 1 : 0.6
          focusable: true
          verticalPadding: Style.space(2)
          horizontalPadding: Style.space(8)
          foreground: page.fg
          fontFamily: page.fontFamily
          fontSize: Style.font.caption
          onClicked: page.showRaw(entry.modelData.id, !entry.raw)
        }
      }

      Text {
        width: parent.width
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: (entry.raw ? entry.modelData.raw : entry.modelData.text) || "(nothing was heard)"
        color: page.fg
        opacity: entry.raw ? 0.75 : 1
        font.family: page.fontFamily
        font.pixelSize: Style.font.body
        font.italic: entry.raw
      }

      Flow {
        width: parent.width
        spacing: Style.space(6)

        ActionButton {
          text: "Paste"
          tooltipText: "Insert it again into the window you were in"
          onClicked: page.paste(entry.index, false)
        }
        ActionButton {
          id: copy
          property bool done: false
          text: done ? "Copied" : "Copy"
          onClicked: {
            page.svc.copyLast(entry.index, entry.raw)
            done = true
            copyReset.restart()
          }
          Timer {
            id: copyReset
            interval: 1400
            onTriggered: copy.done = false
          }
        }
        ActionButton {
          visible: !!entry.modelData.retryable
          text: "Retry"
          tooltipText: "Decode the kept audio again and insert the result"
          onClicked: page.retry(entry.index)
        }
        ActionButton {
          visible: entry.hasRaw
          text: "Paste original"
          tooltipText: "Insert what the Speech Model heard, before the Tidy pass and the vocabulary"
          onClicked: page.paste(entry.index, true)
        }
      }
    }
  }

  Card {
    visible: page.items.length === 0
    ctx: page.ctx
    inset: Style.space(18)
    spacing: Style.space(10)

    Ghost {
      width: Style.space(24)
      height: Style.space(28)
      color: page.fg
      opacity: 0.5
    }

    Text {
      textFormat: Text.PlainText
      text: "Nothing dictated yet"
      color: page.fg
      font.family: page.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
    }

    Caption {
      ctx: page.ctx
      text: page.svc && page.svc.trigger === "commands"
        ? "Tap " + page.keyName + ", speak, and tap it again: the words land in the window you were typing in. Escape cancels. Holding the key to talk needs Talkify to read the keyboard; the Trigger page says how."
        : "Hold " + page.keyName + ", speak, and let go: the words land in the window you were typing in. Tap it once to keep listening hands-free, and tap again to finish. Escape cancels."
    }

    Caption {
      ctx: page.ctx
      strength: 0.55
      text: "Each dictation shows up here, so a word that landed in the wrong window is one click from the right one."
    }
  }

  Caption {
    visible: page.items.length > 0
    ctx: page.ctx
    strength: 0.55
    text: "Keeps the last " + page.value("history.size", 20) + " dictations in memory"
      + (page.value("history.save", false) === true ? " and a daily text file on disk." : "; nothing is written to disk.")
      + " Both are on the Dictation page."
  }

  Card {
    ctx: page.ctx
    spacing: Style.space(8)

    Heading {
      ctx: page.ctx
      text: "TEACH"
    }

    Caption {
      ctx: page.ctx
      text: "Fixed a misheard word? Select your correction and run talkify teach (bind it to a key). Talkify finds the word it heard wrong and spells it your way from then on."
    }

    Flow {
      width: parent.width
      spacing: Style.space(8)

      CommandChip {
        ctx: page.ctx
        command: "talkify teach"
      }

      Button {
        text: "Vocabulary"
        bordered: true
        focusable: true
        foreground: page.fg
        fontFamily: page.fontFamily
        fontSize: Style.font.bodySmall
        onClicked: page.ctx.show("vocabulary")
      }
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

  component ActionButton: Button {
    bordered: true
    focusable: true
    verticalPadding: Style.space(4)
    foreground: page.fg
    fontFamily: page.fontFamily
    fontSize: Style.font.caption
  }
}
