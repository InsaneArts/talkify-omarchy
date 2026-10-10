import QtQuick

// The finalize: speech has ended and the final pass is running. Three dots
// step in turn, held at the height of the visual they replace so nothing
// jumps (VoiceInk's processing state).
Item {
  id: dots

  property color color: "white"
  property real dotSize: 4
  property bool running: false

  property int lit: 0

  implicitWidth: dotSize * 3 + dotSize * 1.6 * 2
  implicitHeight: dotSize

  Row {
    anchors.centerIn: parent
    spacing: dots.dotSize * 1.6
    Repeater {
      model: 3
      Rectangle {
        required property int index
        width: dots.dotSize
        height: dots.dotSize
        radius: dots.dotSize / 2
        color: dots.color
        opacity: index === dots.lit ? 1 : 0.32
        Behavior on opacity { NumberAnimation { duration: 140 } }
      }
    }
  }

  Timer {
    interval: 260
    repeat: true
    running: dots.running && dots.visible
    onTriggered: dots.lit = (dots.lit + 1) % 3
  }
}
