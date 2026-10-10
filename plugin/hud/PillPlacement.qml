import QtQuick
import "HudText.js" as HudText

// The bottom pill (research Variant 5): a small black capsule at the bottom
// centre of the display, the placement most dictation apps settled on, in
// Talkify's own language: the ghost at its left end floating with the voice
// and blinking now and then, the picked waveform in miniature beside it.
//
// With words, the pill grows upward into a short panel: the newest line sits
// at the bottom, nearest the pill, and older lines fade out under the top
// edge (Handy, VoiceInk). A status line (a message, the muted warning, a dead
// microphone) shows the same way whatever the words setting.
//
// The row's far end carries what the session is: the App rules in force,
// the latched clock (a pause mark in it while paused), and the ⏎ key a
// spoken send presses as the text lands.
//
// Fills the HUD surface; the shape is drawn at the bottom centre of it.
Item {
  id: placement

  property var stage: null
  property real dpr: 1
  property string fontFamily: ""
  // Distance from the display's bottom edge to the pill: Omarchy's spacing,
  // plus the bar's height when the bar sits at the bottom.
  property real bottomMargin: 40

  readonly property var cfg: stage.settings
  // Below about 60% the pill stops reading as one; the notch keeps the full
  // range because its smallest sizes cover screen the user was working in.
  readonly property real s: Math.max(0.6, cfg.scale)
  readonly property bool isMessage: stage.layoutKind === "message"
  readonly property string status: stage.statusText
  readonly property string words: cfg.showsWords ? stage.draft : ""
  readonly property string shownText: status !== "" ? status : words
  readonly property bool hasText: shownText !== ""
  readonly property bool latchedClock: stage.latched && stage.listening

  readonly property real rowHeight: 40 * s
  readonly property real pad: 14 * s
  readonly property real ghostWidth: 15 * s
  readonly property real ghostHeight: 17 * s
  readonly property real gap: 10 * s
  readonly property real compactWidth: 184 * s
  readonly property real panelWidth: 420 * s
  readonly property real pointSize: 14 * s
  // The row's far end: tags, the send key, the clock.
  readonly property real endWidth: endRow.implicitWidth > 0 ? endRow.implicitWidth + gap : 0
  // A status line is read whole, whatever the long-draft pick.
  readonly property string textStyle: status !== "" ? "grow-down" : cfg.longDraft
  readonly property int visibleLines: textStyle === "grow-down" ? 3 : 1
  readonly property real textWidth: panelWidth - pad * 2

  // A message is one shape with the ghost beside the words; a session's text
  // hangs above the pill's row.
  readonly property real messageTextWidth: Math.min(messageMeasure.implicitWidth,
    panelWidth - pad * 2 - ghostWidth - gap)
  readonly property real targetWidth: {
    if (isMessage) return Math.max(compactWidth, pad * 2 + ghostWidth + gap + messageTextWidth + 2)
    if (hasText) return panelWidth
    return compactWidth + endWidth
  }
  // A marked draft is laid out a word at a time and can run a line longer
  // than the plain text, while removed words fold out.
  readonly property real textBlockHeight: hasText && !isMessage
    ? Math.min(Math.max(measure.implicitHeight, body.rich ? body.implicitHeight : 0), measure.lineHeightPx * visibleLines) : 0
  readonly property real targetHeight: {
    if (isMessage) return Math.max(rowHeight, messageBody.implicitHeight + 24 * s)
    return rowHeight + (textBlockHeight > 0 ? textBlockHeight + 10 * s : 0)
  }

  function settle() {
    // Only the value: the targets are bindings, and assigning one would
    // cut it loose from the layout for the rest of the session.
    widthSpring.snap(targetWidth)
    heightSpring.snap(targetHeight)
    reveal.park()
  }

  Connections {
    target: placement.stage
    function onMountSerialChanged() { placement.settle() }
    function onMountedChanged() { if (!placement.stage.mounted) reveal.park() }
  }
  Component.onCompleted: settle()

  SpringValue {
    id: widthSpring
    duration: 0.25
    target: placement.targetWidth
  }
  SpringValue {
    id: heightSpring
    duration: 0.25
    target: placement.targetHeight
  }

  // Measures a session's text at the panel's width.
  DraftText {
    textRgb: placement.stage.look.textRgb
    id: measure
    visible: false
    width: placement.textWidth
    draft: placement.shownText
    solid: true
    longDraft: placement.textStyle
    lines: 100
    hudScale: placement.s * 14 / 15
    fontFamily: placement.fontFamily
    readonly property real lineHeightPx: Math.max(1, fontInfo.pixelSize * 1.32)
    lineHeightMode: Text.FixedHeight
    lineHeight: lineHeightPx
  }

  TextMetrics {
    id: messageMeasure
    readonly property real implicitWidth: advanceWidth
    font.family: placement.fontFamily
    font.pixelSize: Math.max(1, placement.pointSize)
    font.weight: Font.Medium
    text: placement.isMessage ? placement.shownText : ""
  }

  FloatReveal {
    id: reveal
    x: Math.round((placement.width - widthSpring.value) / 2)
    y: Math.round(placement.height - placement.bottomMargin - heightSpring.value)
    width: widthSpring.value
    height: heightSpring.value
    revealed: placement.stage.revealed
    style: placement.cfg.reveal
    anchorEdge: "bottom"
    // From past the bottom edge, as the notch slides from past the top.
    travel: placement.bottomMargin + heightSpring.value + 20

    CapsuleBody {
      bodyWidth: reveal.width
      bodyHeight: reveal.height
      cornerRadius: Math.min(placement.rowHeight / 2, reveal.height / 2)
      hudScale: placement.s
      dpr: placement.dpr
      edgeTint: placement.stage.edge
      look: placement.stage.look
    }

    HudGhost {
      id: ghost
      x: placement.pad
      y: placement.isMessage
        ? Math.round((reveal.height - height) / 2)
        : reveal.height - placement.rowHeight + Math.round((placement.rowHeight - height) / 2)
      width: placement.ghostWidth
      height: placement.ghostHeight
      color: placement.stage.listening && !placement.stage.voiceAlive
        ? Qt.rgba(1.0, 0.6, 0.16, 1) : placement.stage.look.ghost
      level: placement.stage.level
      live: placement.stage.voiceLive
      eyesOpen: placement.stage.latched
      nodEpoch: placement.stage.nodEpoch
    }

    // The row: the voice visual beside the ghost, the session's tags, the
    // send key and the latched clock at the end.
    MiniVisual {
      visible: !placement.isMessage
      x: ghost.x + ghost.width + placement.gap
      y: reveal.height - placement.rowHeight + (placement.rowHeight - height) / 2
      // With words, the voice keeps to a short strip.
      width: Math.max(1, (placement.hasText
        ? Math.min(96 * placement.s, reveal.width - x - placement.pad - placement.endWidth)
        : placement.compactWidth - placement.pad * 2 - placement.ghostWidth - placement.gap) - 4 * placement.s)
      height: 22 * placement.s
      stage: placement.stage
      dpr: placement.dpr
      hudScale: placement.s
      opacity: placement.stage.mounted ? 1 : 0
    }

    Row {
      id: endRow
      visible: !placement.isMessage
      anchors.right: parent.right
      anchors.rightMargin: placement.pad
      y: reveal.height - placement.rowHeight + (placement.rowHeight - height) / 2
      height: Math.max(sendKey.implicitHeight, clock.implicitHeight)
      spacing: 6 * placement.s

      TagCapsule {
        anchors.verticalCenter: parent.verticalCenter
        text: placement.stage.ruleTag
        textRgb: placement.stage.look.textRgb
        hudScale: placement.s
        fontFamily: placement.fontFamily
      }

      SendKey {
        id: sendKey
        anchors.verticalCenter: parent.verticalCenter
        active: placement.stage.sent
        pressEpoch: placement.stage.sendEpoch
        textRgb: placement.stage.look.textRgb
        accentRgb: placement.stage.look.accentRgb
        hudScale: placement.s
      }

      ElapsedLabel {
        id: clock
        anchors.verticalCenter: parent.verticalCenter
        color: placement.stage.look.text
        visible: placement.latchedClock
        startedAt: placement.stage.startedAt
        running: placement.latchedClock
        paused: placement.stage.paused
        pausedColor: placement.stage.look.muted
        fontFamily: placement.fontFamily
        pointSize: 12 * placement.s
      }
    }

    // A session's words above the row, newest line at the bottom.
    Item {
      id: textBlock
      visible: placement.hasText && !placement.isMessage
      x: placement.pad
      y: 10 * placement.s
      width: placement.textWidth
      height: Math.max(0, reveal.height - placement.rowHeight - 10 * placement.s)
      clip: true

      LiveDraft {
        id: body
        width: parent.width
        y: parent.height - implicitHeight
        textRgb: placement.stage.look.textRgb
        accentRgb: placement.stage.look.accentRgb
        draft: placement.shownText
        committed: placement.stage.committed
        solid: placement.status !== "" || !placement.cfg.twoTone
        leading: true
        longDraft: placement.textStyle
        lines: 100
        hudScale: placement.s * 14 / 15
        fontFamily: placement.fontFamily
        lineHeightPx: measure.lineHeightPx
        marks: placement.status !== "" ? [] : placement.stage.draftMarks
        fold: placement.stage.fold
        paused: placement.stage.paused
      }

      // Older lines fade out under the top edge, into the shape's own fill.
      Rectangle {
        id: topFade
        readonly property vector4d fill: placement.stage.look.fill
        // Only over a block of more than a line: on one line it would hide
        // the newest words.
        visible: body.implicitHeight > textBlock.height + 1 && textBlock.height > measure.lineHeightPx * 1.5
        width: parent.width
        height: measure.lineHeightPx
        gradient: Gradient {
          GradientStop { position: 0; color: Qt.rgba(topFade.fill.x, topFade.fill.y, topFade.fill.z, 1) }
          GradientStop { position: 1; color: Qt.rgba(topFade.fill.x, topFade.fill.y, topFade.fill.z, 0) }
        }
      }

      FinalizeSweep {
        tint: placement.stage.look.sweep
        anchors.fill: parent
        running: placement.stage.finalizing && placement.words !== ""
      }
    }

    // A message: the words beside the ghost. A replayed dictation is swept
    // once as it lands again.
    LiveDraft {
      id: messageBody
      visible: placement.isMessage
      x: ghost.x + ghost.width + placement.gap
      y: Math.round((reveal.height - implicitHeight) / 2)
      width: placement.messageTextWidth + 2
      textRgb: placement.stage.look.textRgb
      accentRgb: placement.stage.look.accentRgb
      draft: placement.isMessage ? placement.shownText : ""
      solid: true
      leading: true
      longDraft: "grow-down"
      lines: 3
      hudScale: placement.s * 14 / 15
      fontFamily: placement.fontFamily
      marks: placement.isMessage ? placement.stage.statusMarks : []

      FinalizeSweep {
        anchors.fill: parent
        tint: placement.stage.look.sweep
        running: placement.stage.replaying && placement.isMessage
      }
    }
  }
}
