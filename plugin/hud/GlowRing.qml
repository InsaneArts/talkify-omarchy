import QtQuick
import "HudTokens.js" as Tokens

// Edge Glow traced around a closed rounded rectangle: a window's halo, or
// the screen's own edges for a fullscreen window. The beam and its mask are
// edgeglow.frag's, the notch's; the origin sits at the bottom centre, so the
// light is brightest along the bottom edge and blooms around the frame from
// there when the ramp rises (research Variant 2).
//
// A window-sized frame is drawn as four strips along its edges, so the
// shader only runs where the light can land, never across the window.
Item {
  id: ring

  // The traced rectangle, in this item's parent's coordinates.
  property rect path: Qt.rect(0, 0, 100, 100)
  property real cornerRadius: 10
  property real level: 0
  property bool alive: true
  // The session is paused: the light holds still and dims to the muted
  // colour, where a dead microphone holds amber.
  property bool paused: false
  property var look: null
  // Rotate the palette slowly: a latched session.
  property bool turning: false
  // The session ramp, 0..1; the parent animates it.
  property real progress: 0
  // The palette's gradient stops, [[r, g, b], location]: the session's pick
  // or the look's own, resolved by the stage.
  property var stops: Tokens.glowStops("spectrum")
  property real spill: 36
  property real dpr: 1
  // Below 1 a large frame keeps some light along its far edges.
  property real maskScale: 0.6

  // The voice in body and brightness, as the notch's beam; a halo can be
  // wider, 6 to 18 points.
  readonly property real lineWidth: 6 + 12 * level
  readonly property real blurRadius: 12 * (1 + 0.5 * level)
  readonly property real amplitude: !alive ? 1.5 : (paused ? 0.9 : 1.8 + 1.2 * level)
  // Amber for a dead microphone, the muted colour for a paused session.
  readonly property vector4d stillColor: alive ? stillMuted : Qt.vector4d(1.0, 0.6, 0.16, 1.0)
  readonly property vector4d stillMuted: look && look.mutedRgb
    ? Qt.vector4d(look.mutedRgb[0], look.mutedRgb[1], look.mutedRgb[2], 1) : Qt.vector4d(0.55, 0.56, 0.6, 1)
  readonly property real band: spill * 2 + cornerRadius

  property real angleOffset: 0
  property vector4d c0: Qt.vector4d(1, 1, 1, 1)
  property vector4d c1: Qt.vector4d(1, 1, 1, 1)
  property vector4d c2: Qt.vector4d(1, 1, 1, 1)
  property vector4d c3: Qt.vector4d(1, 1, 1, 1)
  property vector4d c4: Qt.vector4d(1, 1, 1, 1)
  property vector4d c5: Qt.vector4d(1, 1, 1, 1)
  property vector4d c6: Qt.vector4d(1, 1, 1, 1)
  property vector4d l0: Qt.vector4d(0, 1, 1, 1)
  property vector4d l1: Qt.vector4d(1, 1, 1, 1)
  property real stopCount: 2

  x: path.x - spill
  y: path.y - spill
  width: path.width + spill * 2
  height: path.height + spill * 2
  visible: progress > 0

  function applyPalette() {
    var stops = ring.stops && ring.stops.length ? ring.stops : Tokens.glowStops("spectrum")
    var colors = []
    var locations = []
    for (var i = 0; i < 7; i++) {
      var stop = stops[Math.min(i, stops.length - 1)]
      colors.push(Tokens.rgba(stop[0], 1))
      locations.push(stop[1])
    }
    c0 = colors[0]; c1 = colors[1]; c2 = colors[2]; c3 = colors[3]
    c4 = colors[4]; c5 = colors[5]; c6 = colors[6]
    l0 = Qt.vector4d(locations[0], locations[1], locations[2], locations[3])
    l1 = Qt.vector4d(locations[4], locations[5], locations[6], 1)
    stopCount = stops.length
  }

  onStopsChanged: applyPalette()
  Component.onCompleted: applyPalette()

  FrameAnimation {
    running: ring.turning && ring.alive && !ring.paused && ring.visible
    onTriggered: ring.angleOffset = (ring.angleOffset + frameTime * 0.06) % 1
  }

  component Strip: ShaderEffect {
    fragmentShader: Qt.resolvedUrl("../shaders/edgeglow.frag.qsb")
    property size viewSize: Qt.size(width, height)
    property point viewOrigin: Qt.point(x, y)
    property size fullSize: Qt.size(ring.width, ring.height)
    property vector4d silhouette: Qt.vector4d(ring.spill, ring.width - ring.spill, ring.height - ring.spill, ring.cornerRadius)
    property real closedPath: 1
    property real silhouetteTop: ring.spill
    property real angleOffset: ring.angleOffset
    property real maskScale: ring.maskScale
    property real topRadius: 0
    property real lineWidth: ring.lineWidth
    property real blurRadius: ring.blurRadius
    property real blurScale: 0.5
    property point origin: Qt.point(ring.width / 2, ring.height - ring.spill)
    property real amplitude: ring.amplitude
    property real progress: ring.progress
    property real micAlive: ring.alive && !ring.paused ? 1 : 0
    property vector4d stillColor: ring.stillColor
    property real stopCount: ring.stopCount
    property vector4d c0: ring.c0
    property vector4d c1: ring.c1
    property vector4d c2: ring.c2
    property vector4d c3: ring.c3
    property vector4d c4: ring.c4
    property vector4d c5: ring.c5
    property vector4d c6: ring.c6
    property vector4d l0: ring.l0
    property vector4d l1: ring.l1
    property real dpr: ring.dpr
  }

  // Top and bottom run the full width; the sides fill in between.
  Strip { x: 0; y: 0; width: ring.width; height: Math.min(ring.band, ring.height / 2) }
  Strip { x: 0; y: ring.height - Math.min(ring.band, ring.height / 2); width: ring.width; height: Math.min(ring.band, ring.height / 2) }
  Strip {
    x: 0
    y: Math.min(ring.band, ring.height / 2)
    width: Math.min(ring.band, ring.width / 2)
    height: Math.max(0, ring.height - 2 * Math.min(ring.band, ring.height / 2))
  }
  Strip {
    x: ring.width - Math.min(ring.band, ring.width / 2)
    y: Math.min(ring.band, ring.height / 2)
    width: Math.min(ring.band, ring.width / 2)
    height: Math.max(0, ring.height - 2 * Math.min(ring.band, ring.height / 2))
  }
}
