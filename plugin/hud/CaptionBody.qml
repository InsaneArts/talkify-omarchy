import QtQuick

// A caption pill (research Variant 1): the ghost at the left end, the live
// draft beside it, and at the right the App rules in force, the ⏎ key a
// spoken send presses, and a latched session's clock. Until the first words
// arrive it is compact and shows the voice visual in miniature, so a silent
// session still looks alive; with words it widens to its full width and
// grows to a second line under Grow Down. Placed by its parent.
Item {
  id: caption

  property var stage: null
  property real dpr: 1
  property string fontFamily: ""
  property real hudScale: 1
  property real maxWidth: 560
  property bool wordsOn: true

  readonly property var cfg: stage.settings
  readonly property real s: hudScale
  readonly property string status: stage.statusText
  readonly property string words: wordsOn ? stage.draft : ""
  readonly property string shownText: status !== "" ? status : words
  readonly property bool hasText: shownText !== ""
  readonly property bool latchedClock: stage.latched && stage.listening
  // A status line is read whole, whatever the long-draft pick.
  readonly property string textStyle: status !== "" ? "grow-down" : cfg.longDraft
  readonly property bool twoLines: hasText && textStyle === "grow-down"
    && Math.max(measure.lineCount, body.rich ? body.lineCount : 0) > 1

  readonly property real pad: 13 * s
  readonly property real gap: 10 * s
  readonly property real ghostWidth: 14 * s
  readonly property real ghostHeight: 16 * s
  // The right end: tags, the send key, the clock.
  readonly property real clockRoom: endRow.implicitWidth > 0 ? endRow.implicitWidth + gap : 0
  readonly property real compactWidth: 200 * s + clockRoom
  readonly property real targetWidth: hasText ? Math.max(compactWidth, maxWidth) : compactWidth
  readonly property real targetHeight: (twoLines ? 58 : 36) * s
  readonly property real textWidth: Math.max(1, targetWidth - pad * 2 - ghostWidth - gap - clockRoom)

  implicitWidth: widthSpring.value
  implicitHeight: heightSpring.value

  function settle() {
    // Only the value: the targets are bindings.
    widthSpring.snap(targetWidth)
    heightSpring.snap(targetHeight)
  }

  Component.onCompleted: settle()

  SpringValue {
    id: widthSpring
    duration: 0.25
    target: caption.targetWidth
  }
  SpringValue {
    id: heightSpring
    duration: 0.18
    target: caption.targetHeight
  }

  DraftText {

    textRgb: caption.stage.look.textRgb
    id: measure
    visible: false
    width: caption.textWidth
    draft: caption.shownText
    solid: true
    longDraft: caption.textStyle
    lines: 2
    hudScale: caption.s * 14 / 15
    fontFamily: caption.fontFamily
  }

  CapsuleBody {
    bodyWidth: caption.width
    bodyHeight: caption.height
    cornerRadius: Math.min(18 * caption.s, caption.height / 2)
    hudScale: caption.s
    dpr: caption.dpr
    edgeTint: caption.stage.edge
    look: caption.stage.look
  }

  HudGhost {
    x: caption.pad
    y: Math.round((caption.height - height) / 2)
    width: caption.ghostWidth
    height: caption.ghostHeight
    color: caption.stage.listening && !caption.stage.voiceAlive ? Qt.rgba(1.0, 0.6, 0.16, 1) : caption.stage.look.ghost
    level: caption.stage.level
    live: caption.stage.voiceLive
    eyesOpen: caption.stage.latched
    nodEpoch: caption.stage.nodEpoch
  }

  Item {
    id: textArea
    x: caption.pad + caption.ghostWidth + caption.gap
    width: Math.max(1, caption.width - x - caption.pad - caption.clockRoom)
    height: caption.height
    clip: true

    MiniVisual {
      anchors.centerIn: parent
      width: parent.width
      height: 18 * caption.s
      visible: !caption.hasText && caption.stage.layoutKind === "session"
      stage: caption.stage
      dpr: caption.dpr
      hudScale: caption.s
    }

    Item {
      width: caption.textWidth
      height: body.implicitHeight
      anchors.verticalCenter: parent.verticalCenter
      visible: caption.hasText
      opacity: caption.width >= caption.targetWidth - 2 ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 120 } }

      LiveDraft {
        id: body
        width: parent.width
        textRgb: caption.stage.look.textRgb
        accentRgb: caption.stage.look.accentRgb
        draft: caption.shownText
        committed: caption.stage.committed
        solid: caption.status !== "" || !caption.cfg.twoTone
        leading: true
        longDraft: caption.textStyle
        lines: 2
        hudScale: caption.s * 14 / 15
        fontFamily: caption.fontFamily
        marks: caption.status !== "" ? caption.stage.statusMarks : caption.stage.draftMarks
        fold: caption.stage.fold
        paused: caption.stage.paused
      }
    }

    FinalizeSweep {
      tint: caption.stage.look.sweep
      anchors.fill: parent
      // The finalize over the words, and a replayed dictation landing again.
      running: (caption.stage.finalizing && caption.words !== "") || (caption.stage.replaying && caption.hasText)
    }
  }

  Row {
    id: endRow
    anchors.right: parent.right
    anchors.rightMargin: caption.pad
    anchors.verticalCenter: parent.verticalCenter
    spacing: 6 * caption.s

    TagCapsule {
      anchors.verticalCenter: parent.verticalCenter
      text: caption.stage.ruleTag
      textRgb: caption.stage.look.textRgb
      hudScale: caption.s
      fontFamily: caption.fontFamily
    }

    SendKey {
      anchors.verticalCenter: parent.verticalCenter
      active: caption.stage.sent
      pressEpoch: caption.stage.sendEpoch
      textRgb: caption.stage.look.textRgb
      accentRgb: caption.stage.look.accentRgb
      hudScale: caption.s * 0.9
    }

    ElapsedLabel {
      id: clock
      anchors.verticalCenter: parent.verticalCenter
      color: caption.stage.look.text
      visible: caption.latchedClock
      startedAt: caption.stage.startedAt
      running: caption.latchedClock
      paused: caption.stage.paused
      pausedColor: caption.stage.look.muted
      fontFamily: caption.fontFamily
      pointSize: 12 * caption.s
    }
  }
}
