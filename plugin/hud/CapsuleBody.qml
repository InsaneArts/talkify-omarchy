import QtQuick

// The black body of a floating shape, drawn by capsule.frag with room around
// it for its shadow. Children of the shape sit on top; this is only the fill.
ShaderEffect {
  id: body

  // The body's own size; the effect reaches `pad` past it on every side.
  property real bodyWidth: 100
  property real bodyHeight: 40
  property real cornerRadius: 20
  property real pad: 24
  property real hudScale: 1
  property real dpr: 1
  property vector4d edgeTint: Qt.vector4d(0, 0, 0, 0)
  // The fill and shadow: Talkify's black, or the theme's darkened background.
  property var look: null

  x: -pad
  y: -pad
  width: bodyWidth + pad * 2
  height: bodyHeight + pad * 2
  fragmentShader: Qt.resolvedUrl("../shaders/capsule.frag.qsb")

  property size viewSize: Qt.size(width, height)
  property vector4d boxRect: Qt.vector4d(pad, pad, bodyWidth, bodyHeight)
  property real radius: cornerRadius
  property vector4d fillColor: look ? look.fill : Qt.vector4d(0, 0, 0, 1)
  property vector4d edgeColor: edgeTint
  property real edgeWidth: 1
  // The notch's shadow: black at 35%, radius 11, four points down.
  property real shadowAlpha: look ? look.shadowAlpha : 0.35
  property real shadowSigma: 11 * hudScale * 0.5
  property real shadowOffset: 4 * hudScale
}
