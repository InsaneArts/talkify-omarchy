import QtQuick
import QtQuick.Shapes
import qs.Commons

// A display in miniature for the Settings previews, in the Omarchy theme's
// colours: a wallpaper gradient, a transparent bar with the ghost at its
// right, and one window with a text box at its bottom, the way a chat app or
// a terminal keeps its input. Drawn at a virtual 1600×900 and scaled by its
// parent, so the HUD placed on it is the real thing at its real proportions.
Item {
  id: mock

  readonly property real barHeight: 35
  // The window the session "started in", and where the pointer rests.
  readonly property rect windowRect: Qt.rect(250, 95, 1100, 690)
  readonly property point pointerAt: Qt.point(1010, 470)
  property bool showPointer: false
  // Hides the bar's ghost while an island stands in its slot.
  property bool ghostHidden: false
  readonly property point ghostSlot: Qt.point(width - 150, 0)

  width: 1600
  height: 900

  Rectangle {
    anchors.fill: parent
    gradient: Gradient {
      GradientStop { position: 0; color: Qt.tint(Color.background, Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.32)) }
      GradientStop { position: 0.55; color: Qt.tint(Color.background, Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.12)) }
      GradientStop { position: 1; color: Color.background }
    }
  }

  // The bar: workspaces at the left, the clock in the middle, the ghost.
  Item {
    width: parent.width
    height: mock.barHeight

    Row {
      x: 18
      anchors.verticalCenter: parent.verticalCenter
      spacing: 10
      Repeater {
        model: 4
        Rectangle {
          required property int index
          width: index === 0 ? 22 : 9
          height: 9
          radius: 4.5
          color: Color.foreground
          opacity: index === 0 ? 0.9 : 0.4
        }
      }
    }

    Text {
      anchors.centerIn: parent
      text: "Thursday 08:40"
      color: Color.bar.text
      font.family: Style.font.family
      font.pixelSize: 15
    }

    Row {
      x: mock.width - 260
      anchors.verticalCenter: parent.verticalCenter
      spacing: 14
      Repeater {
        model: 3
        Rectangle {
          width: 13
          height: 13
          radius: 3
          color: Color.foreground
          opacity: 0.45
        }
      }
    }

    HudGhost {
      x: mock.ghostSlot.x
      anchors.verticalCenter: parent.verticalCenter
      width: 14
      height: 16
      color: Color.bar.text
      visible: !mock.ghostHidden
    }
  }

  // The window, its active border in the accent, its text box at the bottom.
  Rectangle {
    x: mock.windowRect.x
    y: mock.windowRect.y
    width: mock.windowRect.width
    height: mock.windowRect.height
    radius: Math.max(Style.cornerRadius, 4)
    color: Qt.lighter(Color.background, 1.25)
    border.width: 2
    border.color: Color.accent

    Column {
      x: 34
      y: 34
      spacing: 18
      Repeater {
        model: [0.62, 0.8, 0.44, 0.7, 0.55, 0.32]
        Rectangle {
          required property var modelData
          width: (mock.windowRect.width - 68) * modelData
          height: 12
          radius: 6
          color: Color.foreground
          opacity: 0.16
        }
      }
    }

    Rectangle {
      x: 26
      width: parent.width - 52
      height: 50
      y: parent.height - height - 18
      radius: 12
      color: Qt.darker(Color.background, 1.1)
      border.width: 1
      border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.28)

      Text {
        x: 18
        anchors.verticalCenter: parent.verticalCenter
        text: "Message"
        color: Color.foreground
        opacity: 0.4
        font.family: Style.font.family
        font.pixelSize: 17
      }
    }
  }

  // The pointer, for the placement that follows it.
  Shape {
    visible: mock.showPointer
    x: mock.pointerAt.x
    y: mock.pointerAt.y
    width: 18
    height: 26
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      fillColor: "white"
      strokeColor: "black"
      strokeWidth: 1.5
      startX: 0; startY: 0
      PathLine { x: 0; y: 22 }
      PathLine { x: 6; y: 16 }
      PathLine { x: 10; y: 25 }
      PathLine { x: 13.5; y: 23.5 }
      PathLine { x: 9.5; y: 15 }
      PathLine { x: 17; y: 15 }
      PathLine { x: 0; y: 0 }
    }
  }
}
