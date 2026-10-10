import QtQuick

// A paused session's mark: two short bars where the voice would be, in the
// muted colour. It never moves, so it reads as a held breath beside the
// still voice, and nothing like the amber of a dead microphone.
Item {
  id: mark

  property color color: "white"
  property real size: 10

  implicitWidth: size
  implicitHeight: size

  Row {
    anchors.centerIn: parent
    spacing: mark.size * 0.24
    Repeater {
      model: 2
      Rectangle {
        width: Math.max(1.5, mark.size * 0.27)
        height: mark.size
        radius: width / 2
        color: mark.color
        antialiasing: true
      }
    }
  }
}
