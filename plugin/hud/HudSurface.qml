import QtQuick

// The HUD's black shape and its reveal (Talkify's HUDSurface): the rules that
// break on real screens live here.
//
// Bounce is expressed only in top-anchored scale, never in position, because
// a position overshoot lifts the shape off the screen edge and opens a gap.
// The host window never resizes, so the shape top-aligns inside it and only
// its own height animates. Content is not clipped to the shape: the voice
// visuals bloom past the silhouette on purpose.
//
// Children go into the shape's coordinate space, between the housing and the
// overlays; `overlays` sit above the content and below the fillets, which is
// where Talkify stacks the edge glow and the particle cloud.
Item {
  id: surface

  property real shapeWidth: 540
  property real shapeHeight: 90
  property real cornerRadius: 20
  property real filletSize: 11
  property real housingHeight: 26
  property real hudScale: 1
  property string revealStyle: "slide"
  property bool revealed: false
  property real dpr: 1
  // Premultiplied hairline along the silhouette; alpha 0 leaves Talkify's
  // plain black edge.
  property vector4d edgeColor: Qt.vector4d(0, 0, 0, 0)
  property vector4d fillColor: Qt.vector4d(0, 0, 0, 1)
  property real shadowAlpha: 0.35
  // What the session-start ripple lights the housing toward.
  property vector4d rippleTint: Qt.vector4d(1, 1, 1, 1)
  // Seconds into the session-start ripple, or below zero.
  property real rippleTime: -1

  default property alias content: shape.data
  property alias overlays: overlayLayer.data
  readonly property alias shapeItem: shape
  readonly property real reveal: revealSpring.value
  readonly property bool moving: revealSpring.moving

  // Room the housing shader needs beside and below the body for the shadow
  // and the fillets.
  readonly property real housingPad: 28

  // Snaps to the parked pose, for a shape mounting from nothing.
  function park() {
    revealSpring.snap(0)
  }

  // Each style's timing, from HUDSurface.revealAnimation. Slide and drift
  // move position, so they never bounce; unfurl and bloom carry their
  // overshoot in scale anchored at the top.
  onRevealedChanged: {
    if (revealed) {
      switch (revealStyle) {
      case "unfurl": revealSpring.curve = "spring"; revealSpring.duration = 0.45; revealSpring.bounce = 0.3; break
      case "bloom": revealSpring.curve = "spring"; revealSpring.duration = 0.4; revealSpring.bounce = 0.25; break
      case "drift": revealSpring.curve = "easeOut"; revealSpring.duration = 0.24; revealSpring.bounce = 0; break
      default: revealSpring.curve = "spring"; revealSpring.duration = 0.4; revealSpring.bounce = 0
      }
    } else {
      if (revealStyle === "drift") {
        revealSpring.curve = "easeIn"
        revealSpring.duration = 0.18
      } else {
        revealSpring.curve = "spring"
        revealSpring.duration = 0.28
      }
      revealSpring.bounce = 0
    }
    revealSpring.target = revealed ? 1 : 0
  }

  SpringValue {
    id: revealSpring
    value: 0
    target: 0
  }

  // Where position moves at all, hidden means at or above the screen's top
  // edge, never below, so no style can open a gap.
  readonly property real revealOffset: {
    var r = revealSpring.value
    switch (revealStyle) {
    case "slide": return -(shapeHeight + 20) * (1 - r)
    case "drift": return -14 * (1 - r)
    default: return 0
    }
  }

  readonly property real revealScaleX: revealStyle === "bloom" ? 0.55 + 0.45 * revealSpring.value : 1
  readonly property real revealScaleY: {
    switch (revealStyle) {
    case "unfurl": return Math.max(0.001, 0.001 + 0.999 * revealSpring.value)
    case "bloom": return 0.55 + 0.45 * revealSpring.value
    default: return 1
    }
  }

  readonly property real revealOpacity: revealStyle === "bloom" || revealStyle === "drift"
    ? Math.max(0, Math.min(1, revealSpring.value)) : 1

  Item {
    id: shape
    x: Math.round((surface.width - surface.shapeWidth) / 2)
    y: 0
    width: surface.shapeWidth
    height: surface.shapeHeight
    opacity: surface.revealOpacity
    visible: surface.revealOpacity > 0.001
    transform: [
      Scale {
        origin.x: shape.width / 2
        origin.y: 0
        xScale: surface.revealScaleX
        yScale: surface.revealScaleY
      },
      Translate { y: surface.revealOffset }
    ]

    ShaderEffect {
      id: housing
      z: -1
      x: -surface.housingPad
      y: 0
      width: surface.shapeWidth + surface.housingPad * 2
      height: surface.shapeHeight + surface.housingPad
      fragmentShader: Qt.resolvedUrl("../shaders/housing.frag.qsb")

      property size viewSize: Qt.size(width, height)
      property vector4d shapeRect: Qt.vector4d(surface.housingPad, 0, surface.shapeWidth, surface.shapeHeight)
      property real cornerRadius: surface.cornerRadius
      property real fillet: surface.filletSize
      property real layerMode: 0
      property real shadowAlpha: surface.shadowAlpha
      property real shadowSigma: 11 * surface.hudScale * 0.5
      property real shadowOffset: 4 * surface.hudScale
      property vector4d fillColor: surface.fillColor
      property vector4d edgeColor: surface.edgeColor
      property real edgeWidth: 1
      property point rippleOrigin: Qt.point(surface.housingPad + surface.shapeWidth / 2, surface.housingHeight)
      property real rippleTime: surface.rippleTime
      property vector4d rippleTint: surface.rippleTint
      property real dpr: surface.dpr
    }

    Item {
      id: overlayLayer
      z: 1
      anchors.fill: parent
    }

    ShaderEffect {
      z: 2
      x: housing.x
      y: housing.y
      width: housing.width
      height: housing.height
      visible: surface.filletSize > 0
      fragmentShader: housing.fragmentShader

      property size viewSize: housing.viewSize
      property vector4d shapeRect: housing.shapeRect
      property real cornerRadius: housing.cornerRadius
      property real fillet: housing.fillet
      property real layerMode: 1
      property real shadowAlpha: 0
      property real shadowSigma: 1
      property real shadowOffset: 0
      property vector4d fillColor: housing.fillColor
      property vector4d edgeColor: housing.edgeColor
      property real edgeWidth: housing.edgeWidth
      property point rippleOrigin: housing.rippleOrigin
      property real rippleTime: -1
      property vector4d rippleTint: housing.rippleTint
      property real dpr: housing.dpr
    }
  }
}
