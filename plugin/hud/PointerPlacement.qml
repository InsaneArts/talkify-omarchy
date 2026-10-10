import QtQuick
import QtQuick.Shapes

// The pointer dot (research Variant 4): the smallest HUD that still shows
// the voice, beside the mouse pointer, which on a wide or multi-monitor
// desk is nearer the user's eyes than any edge. A ring on a dark disc (so it
// reads on a white page as well as a dark one) whose radius and stroke
// breathe with the level, or the ghost in its place. It sits below and right
// of the pointer and flips at the display's edges.
//
// Latched: a solid dot inside the ring. Dead microphone: static amber. The
// finalize: a short arc runs around the ring. Status lines, and the words
// when turned on, ride in a small label beside it.
//
// Paused, the ring gives way to a muted pause mark, and a spoken send
// presses its ⏎ inside the disc.
Item {
  id: placement

  property var stage: null
  property real dpr: 1
  property string fontFamily: ""
  // The pointer in this surface's coordinates; it follows only while the
  // pointer is on this display.
  property point pointer: Qt.point(width / 2, height / 2)

  readonly property var cfg: stage.settings
  readonly property real s: Math.max(0.6, cfg.scale)
  readonly property real disc: 32 * s
  readonly property real offset: 18
  readonly property bool dead: stage.listening && !stage.voiceAlive
  // The ring is the voice, in the look's bright core; the ghost is the mark,
  // in its accent; both amber for a dead microphone.
  readonly property color tint: dead ? Qt.rgba(1.0, 0.6, 0.16, 1) : stage.look.coreColor
  readonly property bool showsKey: stage.sent && stage.landing
  readonly property string labelText: {
    if (stage.statusText !== "") return stage.statusText
    if (cfg.showsWords && stage.draft !== "") return stage.draft
    return ""
  }

  // Below and right of the pointer, flipped toward the room at the edges.
  readonly property bool flipX: pointer.x + offset + disc + labelRoom > width
  readonly property bool flipY: pointer.y + offset + disc > height
  readonly property real labelRoom: labelText !== "" ? label.width + 8 * s : 0
  readonly property real targetX: flipX ? pointer.x - offset - disc : pointer.x + offset
  readonly property real targetY: flipY ? pointer.y - offset - disc : pointer.y + offset

  property real followX: targetX
  property real followY: targetY

  function snapToPointer() {
    followX = targetX
    followY = targetY
  }

  Connections {
    target: placement.stage
    function onMountSerialChanged() {
      placement.snapToPointer()
      reveal.park()
    }
    function onMountedChanged() { if (!placement.stage.mounted) reveal.park() }
  }
  Component.onCompleted: snapToPointer()

  // Eased over about 80 ms, so a 30 Hz pointer does not jitter it.
  FrameAnimation {
    running: placement.visible && placement.stage.mounted
      && (Math.abs(placement.followX - placement.targetX) > 0.2 || Math.abs(placement.followY - placement.targetY) > 0.2)
    onTriggered: {
      var k = 1 - Math.exp(-frameTime / 0.04)
      placement.followX += (placement.targetX - placement.followX) * k
      placement.followY += (placement.targetY - placement.followY) * k
    }
  }

  FloatReveal {
    id: reveal
    x: Math.round(placement.followX)
    y: Math.round(placement.followY)
    width: placement.disc
    height: placement.disc
    revealed: placement.stage.revealed
    // It scales in from 0.6 whatever the reveal pick: there is no edge here
    // for a slide to come from.
    style: placement.cfg.reveal === "drift" ? "drift" : "bloom"
    bloomFrom: 0.6
    anchorEdge: "center"

    CapsuleBody {
      bodyWidth: placement.disc
      bodyHeight: placement.disc
      cornerRadius: placement.disc / 2
      hudScale: placement.s * 0.6
      dpr: placement.dpr
      edgeTint: placement.stage.edge
      look: placement.stage.look
    }

    Rectangle {
      id: ringMark
      visible: placement.cfg.pointerMark === "ring" && !placement.stage.finalizing && !placement.stage.paused && !placement.showsKey
      readonly property real breath: placement.stage.listening && placement.stage.voiceAlive ? placement.stage.level : 0
      width: (16 + 5 * breath) * placement.s
      height: width
      radius: width / 2
      anchors.centerIn: parent
      color: "transparent"
      border.width: (1.8 + 1.4 * breath) * placement.s
      border.color: placement.tint
      antialiasing: true
      Behavior on width { NumberAnimation { duration: 70 } }
    }

    HudGhost {
      visible: placement.cfg.pointerMark === "ghost" && !placement.showsKey
      anchors.centerIn: parent
      width: 13 * placement.s
      height: 15 * placement.s
      color: placement.dead ? Qt.rgba(1.0, 0.6, 0.16, 1) : placement.stage.look.ghost
      level: placement.stage.level
      live: placement.stage.voiceLive
      eyesOpen: placement.stage.latched
      nodEpoch: placement.stage.nodEpoch
    }

    PauseMark {
      visible: placement.cfg.pointerMark === "ring" && placement.stage.paused
      anchors.centerIn: parent
      size: 11 * placement.s
      color: placement.stage.look.muted
    }

    SendKey {
      anchors.centerIn: parent
      active: placement.stage.sent
      pressEpoch: placement.stage.sendEpoch
      textRgb: placement.stage.look.textRgb
      accentRgb: placement.stage.look.accentRgb
      hudScale: placement.s * 0.8
    }

    // Latched: a solid centre.
    Rectangle {
      visible: placement.cfg.pointerMark === "ring" && placement.stage.latched && placement.stage.listening
        && !placement.stage.paused && !placement.showsKey
      width: 5 * placement.s
      height: width
      radius: width / 2
      anchors.centerIn: parent
      color: placement.tint
    }

    // The finalize: a short arc running around the ring.
    Shape {
      id: arc
      visible: placement.stage.finalizing && placement.cfg.pointerMark === "ring"
      anchors.centerIn: parent
      width: 16 * placement.s + 4
      height: width
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        strokeColor: placement.stage.look.ghost
        strokeWidth: 2 * placement.s
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        PathAngleArc {
          centerX: arc.width / 2
          centerY: arc.height / 2
          radiusX: 8 * placement.s
          radiusY: 8 * placement.s
          startAngle: -90
          sweepAngle: 100
        }
      }
      RotationAnimation on rotation {
        running: arc.visible
        loops: Animation.Infinite
        from: 0
        to: 360
        duration: 900
      }
    }

    // Status, or the words when they are on, beside the dot.
    Item {
      id: label
      visible: placement.labelText !== ""
      // Words keep to a short tail on one line; a status line gets more room
      // and wraps, so it is always read whole.
      readonly property bool isStatus: placement.stage.statusText !== ""
      readonly property real maxWidth: (isStatus ? 420 : 300) * placement.s
      width: Math.min(maxWidth, labelMetrics.advanceWidth + 24 * placement.s)
      height: Math.max(26 * placement.s, labelBody.implicitHeight + 12 * placement.s)
      x: placement.flipX ? -width - 8 * placement.s : placement.disc + 8 * placement.s
      y: (placement.disc - height) / 2

      TextMetrics {
        id: labelMetrics
        font.family: placement.fontFamily
        font.pixelSize: Math.max(1, 13 * placement.s)
        font.weight: Font.Medium
        text: placement.labelText
      }

      CapsuleBody {
        bodyWidth: label.width
        bodyHeight: label.height
        cornerRadius: Math.min(label.height / 2, 13 * placement.s)
        hudScale: placement.s * 0.6
        dpr: placement.dpr
        edgeTint: placement.stage.edge
      look: placement.stage.look
      }

      LiveDraft {
        id: labelBody
        x: 12 * placement.s
        width: label.width - 24 * placement.s
        anchors.verticalCenter: parent.verticalCenter
        textRgb: placement.stage.look.textRgb
        accentRgb: placement.stage.look.accentRgb
        draft: placement.labelText
        committed: placement.stage.committed
        solid: placement.stage.statusText !== "" || !placement.cfg.twoTone
        leading: true
        longDraft: label.isStatus ? "grow-down" : "tail-only"
        lines: 3
        hudScale: placement.s * 13 / 15
        fontFamily: placement.fontFamily
        marks: label.isStatus ? placement.stage.statusMarks : placement.stage.draftMarks
        fold: placement.stage.fold
        paused: placement.stage.paused
      }

      FinalizeSweep {
        anchors.fill: parent
        anchors.leftMargin: 6 * placement.s
        anchors.rightMargin: 6 * placement.s
        tint: placement.stage.look.sweep
        running: label.visible && placement.stage.replaying
      }
    }
  }
}
