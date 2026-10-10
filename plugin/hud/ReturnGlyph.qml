import QtQuick
import QtQuick.Shapes

// The ⏎ of a spoken send, drawn rather than set in type, so it looks the same
// in every HUD font: a stroke down, a stroke back, and the arrowhead.
Shape {
  id: glyph

  property color color: "white"
  property real stroke: 1.4

  implicitWidth: 12
  implicitHeight: 10
  preferredRendererType: Shape.CurveRenderer

  ShapePath {
    strokeColor: glyph.color
    strokeWidth: glyph.stroke
    fillColor: "transparent"
    capStyle: ShapePath.RoundCap
    joinStyle: ShapePath.RoundJoin
    startX: glyph.width * 0.86
    startY: glyph.height * 0.08
    PathLine { x: glyph.width * 0.86; y: glyph.height * 0.62 }
    PathLine { x: glyph.width * 0.12; y: glyph.height * 0.62 }
    PathMove { x: glyph.width * 0.38; y: glyph.height * 0.3 }
    PathLine { x: glyph.width * 0.12; y: glyph.height * 0.62 }
    PathLine { x: glyph.width * 0.38; y: glyph.height * 0.94 }
  }
}
