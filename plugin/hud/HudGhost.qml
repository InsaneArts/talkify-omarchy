import QtQuick
import QtQuick.Shapes

// Talkify's ghost as a voice mark: the bar's outline (Ghost.qml), with eyes
// that can close, so it blinks now and then while it listens, holds them
// open for a latched session, and floats with the voice as the bar's ghost
// does. The eyes are cut out of the body, so it reads on any fill. It nods
// once when Teach learns a word: yes, got it.
Item {
  id: ghost

  property color color: "white"
  property real level: 0
  // Listening: it bobs with the level and blinks.
  property bool live: false
  // Latched: the eyes stay open.
  property bool eyesOpen: false
  // Each bump nods once.
  property int nodEpoch: 0

  // 0 upright, 1 the bottom of the nod.
  property real nod: 0

  // 1 open, toward 0 closed.
  property real openness: 1

  implicitWidth: 14
  implicitHeight: 16

  readonly property real eyeHeight: 22 * Math.max(0.14, openness)
  readonly property real eyeCap: Math.min(4, eyeHeight / 2)
  readonly property real eyeTop: 41 - eyeHeight / 2

  function eye(left) {
    var right = left + 8
    var top = eyeTop + eyeCap
    var bottom = eyeTop + eyeHeight - eyeCap
    return "M " + left + " " + top + " A 4 " + eyeCap + " 0 0 1 " + right + " " + top
      + " L " + right + " " + bottom + " A 4 " + eyeCap + " 0 0 1 " + left + " " + bottom + " Z"
  }

  Shape {
    width: ghost.width
    height: ghost.height
    // Up to two points at full level, like the bar's ghost, plus a breath.
    y: (ghost.live ? -0.12 * ghost.height * ghost.level : 0) + 0.14 * ghost.height * ghost.nod
    scale: 1 + (ghost.live ? 0.05 * ghost.level : 0)
    transformOrigin: Item.Bottom
    preferredRendererType: Shape.CurveRenderer
    // The nod tips the head toward the viewer, about its hem.
    transform: Rotation {
      origin.x: ghost.width / 2
      origin.y: ghost.height
      axis { x: 1; y: 0; z: 0 }
      angle: 50 * ghost.nod
    }

    Behavior on y { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }

    ShapePath {
      fillColor: ghost.color
      strokeColor: "transparent"
      fillRule: ShapePath.OddEvenFill
      scale: Qt.size(ghost.width / 84, ghost.height / 96)
      PathSvg {
        path: "M 0 96 L 0 42 A 42 42 0 0 1 84 42 L 84 96 "
          + "Q 73.5 86 63 96 Q 52.5 86 42 96 Q 31.5 86 21 96 Q 10.5 86 0 96 Z "
          + ghost.eye(26) + " " + ghost.eye(50)
      }
    }
  }

  // A blink every few seconds while it listens, never in a latched session.
  SequentialAnimation {
    id: blink
    NumberAnimation { target: ghost; property: "openness"; to: 0; duration: 70; easing.type: Easing.InQuad }
    NumberAnimation { target: ghost; property: "openness"; to: 1; duration: 110; easing.type: Easing.OutQuad }
  }

  Timer {
    running: ghost.live && !ghost.eyesOpen && ghost.visible
    interval: 2600 + Math.random() * 2600
    repeat: true
    onTriggered: {
      interval = 2600 + Math.random() * 2600
      blink.restart()
    }
  }

  // After the reveal has settled, so the nod is not lost in it.
  SequentialAnimation {
    id: nodding
    PauseAnimation { duration: 260 }
    NumberAnimation { target: ghost; property: "nod"; to: 1; duration: 150; easing.type: Easing.OutQuad }
    NumberAnimation { target: ghost; property: "nod"; to: 0; duration: 320; easing.type: Easing.OutBack }
  }

  onNodEpochChanged: if (nodEpoch > 0) nodding.restart()
  onEyesOpenChanged: if (eyesOpen) { blink.stop(); openness = 1 }
  onLiveChanged: if (!live) { blink.stop(); openness = 1 }
}
