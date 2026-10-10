import QtQuick

// The finalize over words: the text stays exactly where it is (collapsing it
// squishes it mid-stream, as Handy found) while a soft band of light runs
// across it, left to right, until the final pass lands.
Item {
  id: sweep

  property bool running: false
  // The band's light: white for Talkify, the accent for a theme.
  property color tint: Qt.rgba(1, 1, 1, 0.1)

  clip: true
  visible: running

  Rectangle {
    id: band
    width: Math.max(24, sweep.width * 0.28)
    height: sweep.height
    x: -width
    opacity: 0.85
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0; color: Qt.rgba(sweep.tint.r, sweep.tint.g, sweep.tint.b, 0) }
      GradientStop { position: 0.5; color: Qt.rgba(sweep.tint.r, sweep.tint.g, sweep.tint.b, sweep.tint.a) }
      GradientStop { position: 1; color: Qt.rgba(sweep.tint.r, sweep.tint.g, sweep.tint.b, 0) }
    }

    NumberAnimation on x {
      running: sweep.running && sweep.visible
      loops: Animation.Infinite
      from: -band.width
      to: sweep.width
      duration: 1100
      easing.type: Easing.InOutSine
    }
  }
}
