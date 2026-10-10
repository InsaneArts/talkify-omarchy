import QtQuick
import QtQuick.Shapes

// Talkify's mark, drawn as vectors so the bar can tint it, pulse it, and
// fill it from the bottom like a battery while the Speech Model downloads:
// it reads at 16 pixels, needs no extra chrome, and it is the app's own mark
// doing the work.
Item {
  id: root

  property color color: "white"
  // 0–1: how much of the ghost is solid, from the bottom. The rest is drawn
  // faint so the silhouette stays legible on any bar.
  property real fill: 1
  property real faintOpacity: 0.3

  implicitWidth: 14
  implicitHeight: 16

  // An 84×96 box: a domed head, straight sides, a four-point hem, and two
  // pill eyes cut out of the body by the even-odd fill.
  readonly property string outline: "M 0 96 L 0 42 A 42 42 0 0 1 84 42 L 84 96 "
    + "Q 73.5 86 63 96 Q 52.5 86 42 96 Q 31.5 86 21 96 Q 10.5 86 0 96 Z "
    + "M 26 34 A 4 4 0 0 1 34 34 L 34 48 A 4 4 0 0 1 26 48 Z "
    + "M 50 34 A 4 4 0 0 1 58 34 L 58 48 A 4 4 0 0 1 50 48 Z"

  component Silhouette: Shape {
    property color tint: root.color
    width: root.width
    height: root.height
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      fillColor: tint
      strokeColor: "transparent"
      fillRule: ShapePath.OddEvenFill
      scale: Qt.size(root.width / 84, root.height / 96)
      PathSvg { path: root.outline }
    }
  }

  Silhouette {
    visible: root.fill < 1
    opacity: root.faintOpacity
  }

  Item {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: root.height * Math.max(0, Math.min(1, root.fill))
    clip: true

    Silhouette {
      y: parent.height - root.height
    }
  }
}
