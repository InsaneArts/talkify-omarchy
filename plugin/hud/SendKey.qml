import QtQuick

// The Enter a spoken send presses (an App rule's `send`): a key cap that comes
// up as the text lands and presses down once, so the user sees Enter go in
// after the words. Each bump of `pressEpoch` plays it once; it then holds
// still, lit in the accent, until the shape leaves.
Item {
  id: key

  property int pressEpoch: 0
  // Off between sessions: the key is gone, ready for the next send.
  property bool active: true
  property var textRgb: [1, 1, 1, 1]
  property var accentRgb: [0.42, 0.64, 1, 1]
  property real hudScale: 1

  readonly property real s: hudScale
  // How far the cap travels when pressed: the depth of its side.
  readonly property real depth: 2.5 * s

  property real shown: 0
  property real press: 0
  property real lit: 0

  implicitWidth: 25 * s
  implicitHeight: 20 * s
  opacity: shown
  visible: active && shown > 0.001

  function mix(a, b, t) {
    return Qt.rgba(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, 1)
  }
  function tint(rgb, alpha) {
    return Qt.rgba(rgb[0], rgb[1], rgb[2], alpha)
  }

  // Back to nothing, for a shape that has left.
  function reset() {
    pressing.stop()
    shown = 0
    press = 0
    lit = 0
  }

  onPressEpochChanged: if (active && pressEpoch > 0) pressing.restart()
  onActiveChanged: if (!active) reset()

  SequentialAnimation {
    id: pressing
    NumberAnimation { target: key; property: "shown"; from: 0; to: 1; duration: 120; easing.type: Easing.OutQuad }
    PauseAnimation { duration: 90 }
    ParallelAnimation {
      NumberAnimation { target: key; property: "press"; from: 0; to: 1; duration: 75; easing.type: Easing.InQuad }
      NumberAnimation { target: key; property: "lit"; from: 0; to: 1; duration: 75 }
    }
    NumberAnimation { target: key; property: "press"; to: 0; duration: 240; easing.type: Easing.OutBack }
  }

  // The key's side, which the cap sinks into.
  Rectangle {
    y: key.depth
    width: key.width
    height: key.height - key.depth
    radius: 5 * key.s
    color: key.tint(key.textRgb, 0.2)
    antialiasing: true
  }

  Rectangle {
    id: cap
    y: key.depth * key.press
    width: key.width
    height: key.height - key.depth
    radius: 5 * key.s
    antialiasing: true
    color: Qt.rgba(
      key.textRgb[0] * 0.1 * (1 - key.lit) + key.accentRgb[0] * 0.3 * key.lit,
      key.textRgb[1] * 0.1 * (1 - key.lit) + key.accentRgb[1] * 0.3 * key.lit,
      key.textRgb[2] * 0.1 * (1 - key.lit) + key.accentRgb[2] * 0.3 * key.lit,
      0.1 + 0.25 * key.lit)
    border.width: Math.max(1, key.s)
    border.color: Qt.rgba(
      key.textRgb[0] + (key.accentRgb[0] - key.textRgb[0]) * key.lit,
      key.textRgb[1] + (key.accentRgb[1] - key.textRgb[1]) * key.lit,
      key.textRgb[2] + (key.accentRgb[2] - key.textRgb[2]) * key.lit,
      0.45 + 0.45 * key.lit)

    ReturnGlyph {
      anchors.centerIn: parent
      width: 11 * key.s
      height: 9 * key.s
      stroke: Math.max(1.1, 1.4 * key.s)
      color: key.mix(key.textRgb, key.accentRgb, key.lit)
    }
  }
}
