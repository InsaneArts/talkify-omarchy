import QtQuick

// The bar island (research Variant 3): the ghost in the Omarchy bar widens
// into a black pill inside the bar's own height for the session, and
// shrinks back to the ghost when it ends. No floating shape at all: the
// least intrusive HUD that is still seen, in the bar's own place.
//
// Inside: the ghost (eyes held open and a dot at the left end for a latched
// session, a pause mark there while paused), the voice visual in miniature,
// stepping dots for the finalize, and, when words are on or there is a
// status line, the last words on one line with the head scrolling off. At
// the right end: the App rules in force, and the ⏎ a spoken send presses.
Item {
  id: island

  property var stage: null
  property real barHeight: 35
  // The ghost's slot in the bar, where the island starts and ends.
  property real slotWidth: 27
  property real dpr: 1
  property string fontFamily: ""
  // Whether this island is the one holding the session.
  property bool active: false

  readonly property var cfg: stage.settings
  readonly property bool open: active && stage.mounted && stage.revealed
  readonly property string status: stage.statusText
  readonly property string shownText: status !== "" ? status : (cfg.showsWords ? stage.draft : "")
  readonly property bool hasText: shownText !== ""
  readonly property bool latched: stage.latched && stage.listening
  readonly property bool isMessage: stage.layoutKind === "message"

  readonly property real bodyHeight: Math.max(16, barHeight - 6)
  readonly property real k: bodyHeight / 29
  readonly property real pad: 11 * k
  readonly property real gap: 8 * k
  readonly property bool paused: stage.paused
  readonly property real lockRoom: latched ? (paused ? 7 : 5) * k + gap * 0.75 : 0
  // The right end: tags and the send key.
  readonly property real endRoom: endRow.implicitWidth > 0 ? endRow.implicitWidth + gap : 0
  readonly property real ghostWidth: 12 * k
  readonly property real visualWidth: isMessage ? 0 : (hasText ? 56 * k : 220 - 2 * pad - ghostWidth - gap - lockRoom)
  // Words keep to the last few that fit in 420; a status line or a message
  // gets the room to be read whole.
  readonly property real widest: status !== "" ? 900 : 420
  readonly property real textRoom: hasText
    ? Math.min(textMetrics.advanceWidth + 4, widest - 2 * pad - lockRoom - ghostWidth - gap - visualWidth - (visualWidth > 0 ? gap : 0) - endRoom)
    : 0
  readonly property real openWidth: hasText
    ? 2 * pad + lockRoom + ghostWidth + gap + (visualWidth > 0 ? visualWidth + gap : 0) + textRoom + endRoom
    : 220 + endRoom
  readonly property real targetWidth: open ? openWidth : slotWidth
  // 0 at the ghost's slot, 1 fully open: the body fades in as it widens.
  readonly property real morph: Math.max(0, Math.min(1, (widthSpring.value - slotWidth) / Math.max(1, openWidth - slotWidth)))

  implicitWidth: widthSpring.value
  implicitHeight: barHeight
  visible: widthSpring.value > slotWidth + 0.5 || open

  // Opening is the notch's reveal spring, closing its retract; a width change
  // while open (words arriving) is the shell's band spring.
  onTargetWidthChanged: {
    widthSpring.duration = !open ? 0.28 : (widthSpring.value <= slotWidth + 1 ? 0.4 : 0.25)
    widthSpring.target = targetWidth
  }
  Component.onCompleted: widthSpring.snap(slotWidth)

  SpringValue {
    id: widthSpring
  }

  TextMetrics {
    id: textMetrics
    font.family: island.fontFamily
    font.pixelSize: Math.max(1, 12 * island.k)
    font.weight: Font.Medium
    text: island.shownText
  }

  Item {
    id: body
    width: parent.width
    height: island.bodyHeight
    anchors.verticalCenter: parent.verticalCenter
    opacity: Math.min(1, island.morph * 1.6)

    CapsuleBody {
      bodyWidth: body.width
      bodyHeight: body.height
      cornerRadius: body.height / 2
      pad: 8
      hudScale: 0.4
      dpr: island.dpr
      edgeTint: island.stage.edge
      look: island.stage.look
    }

    // The content follows the shape, a beat behind it.
    Item {
      anchors.fill: parent
      opacity: Math.max(0, (island.morph - 0.55) / 0.45)
      clip: true

      Rectangle {
        visible: island.latched && !island.paused
        x: island.pad
        anchors.verticalCenter: parent.verticalCenter
        width: 5 * island.k
        height: width
        radius: width / 2
        color: island.stage.look.text
      }

      PauseMark {
        visible: island.latched && island.paused
        x: island.pad
        anchors.verticalCenter: parent.verticalCenter
        size: 7 * island.k
        color: island.stage.look.muted
      }

      HudGhost {
        id: ghost
        x: island.pad + island.lockRoom
        anchors.verticalCenter: parent.verticalCenter
        width: island.ghostWidth
        height: 14 * island.k
        color: island.stage.listening && !island.stage.voiceAlive ? Qt.rgba(1.0, 0.6, 0.16, 1) : island.stage.look.ghost
        level: island.stage.level
        live: island.stage.voiceLive
        eyesOpen: island.stage.latched
        nodEpoch: island.stage.nodEpoch
      }

      MiniVisual {
        visible: island.visualWidth > 0
        x: ghost.x + ghost.width + island.gap
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(1, island.visualWidth)
        height: 15 * island.k
        stage: island.stage
        dpr: island.dpr
        hudScale: island.k * 0.8
      }

      LiveDraft {
        id: words
        visible: island.hasText
        x: ghost.x + ghost.width + island.gap + (island.visualWidth > 0 ? island.visualWidth + island.gap : 0)
        width: island.textRoom
        anchors.verticalCenter: parent.verticalCenter
        textRgb: island.stage.look.textRgb
        accentRgb: island.stage.look.accentRgb
        draft: island.shownText
        committed: island.stage.committed
        solid: island.status !== "" || !island.cfg.twoTone
        leading: true
        longDraft: "tail-only"
        hudScale: island.k * 12 / 15
        fontFamily: island.fontFamily
        marks: island.status !== "" ? island.stage.statusMarks : island.stage.draftMarks
        fold: island.stage.fold
        paused: island.stage.paused
      }

      FinalizeSweep {
        x: words.x
        width: words.width
        height: parent.height
        tint: island.stage.look.sweep
        // As in the notch, a plain finalize keeps its dots; only a replay
        // sweeps the words.
        running: island.hasText && island.stage.replaying
      }

      Row {
        id: endRow
        anchors.right: parent.right
        anchors.rightMargin: island.pad
        anchors.verticalCenter: parent.verticalCenter
        spacing: 5 * island.k

        TagCapsule {
          anchors.verticalCenter: parent.verticalCenter
          text: island.stage.ruleTag
          textRgb: island.stage.look.textRgb
          hudScale: island.k
          fontFamily: island.fontFamily
        }

        SendKey {
          anchors.verticalCenter: parent.verticalCenter
          active: island.stage.sent
          pressEpoch: island.stage.sendEpoch
          textRgb: island.stage.look.textRgb
          accentRgb: island.stage.look.accentRgb
          hudScale: island.k * 0.8
        }
      }
    }
  }
}
