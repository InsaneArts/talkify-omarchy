import QtQuick
import "HudGeometry.js" as Geometry
import "HudTokens.js" as Tokens

// The Edge Glow beam (HUDEdgeGlowView): the open silhouette stroked with the
// palette and masked by distance from an origin that sweeps it, corner to
// corner and back, starting under the housing at each session. It blooms in
// when listening starts, breathes with the voice, and drains back when the
// session ends; a dead microphone swaps the palette for a motionless amber.
//
// Placed by its parent `spill` past the shape on the left, right and bottom.
// It stays mounted after listening ends so the drain can play, and stops
// drawing once the ramp reaches zero.
ShaderEffect {
  id: glow

  property bool listening: false
  property bool alive: true
  // The session is paused: the light holds still and dims to the muted
  // colour, where a dead microphone holds amber.
  property bool paused: false
  property var look: null
  property real level: 0
  property int epoch: 0
  property real hudScale: 1
  property real cornerRadiusValue: 20
  property real topFilletRadius: 0
  // The palette's gradient stops, [[r, g, b], location]: the session's pick
  // or the look's own, resolved by the stage.
  property var stops: Tokens.glowStops("spectrum")
  property real spill: 28
  property real dpr: 1

  // Duration of the bloom-in and drain-out ramps, and of one sweep.
  readonly property real rampDuration: 0.4

  visible: progress > 0 || listening
  fragmentShader: Qt.resolvedUrl("../shaders/edgeglow.frag.qsb")

  property size viewSize: Qt.size(width, height)
  property point viewOrigin: Qt.point(0, 0)
  property size fullSize: Qt.size(width, height)
  property vector4d silhouette: Qt.vector4d(spill, width - spill, height - spill, cornerRadiusValue)
  property real closedPath: 0
  property real silhouetteTop: 0
  property real angleOffset: 0
  property real maskScale: 1
  property real topRadius: topFilletRadius
  // The voice shows in two registers: brightness, resting near the gist's
  // constant 3 so the halo never starves, and body, the strokes swelling to
  // double.
  property real lineWidth: 6 * hudScale * (1 + level)
  property real blurRadius: 12 * hudScale * (1 + 0.5 * level)
  // SwiftUI blur radii read as about two standard deviations: Talkify
  // budgets 28 points of spill for a radius-12 glow, which only fits if so.
  property real blurScale: 0.5
  property point origin: Qt.point(width / 2, height - spill)
  property real amplitude: !alive ? 1.5 : (paused ? 0.9 : 1.8 + 1.2 * level)
  property real progress: 0
  // Uniforms are floats; a bool would arrive as raw bits.
  property real micAlive: alive && !paused ? 1 : 0
  // Amber for a dead microphone, the muted colour for a paused session.
  property vector4d stillColor: alive
    ? (look && look.mutedRgb ? Qt.vector4d(look.mutedRgb[0], look.mutedRgb[1], look.mutedRgb[2], 1) : Qt.vector4d(0.55, 0.56, 0.6, 1))
    : Qt.vector4d(1.0, 0.6, 0.16, 1.0)
  property real stopCount: 2
  property vector4d c0: Qt.vector4d(1, 1, 1, 1)
  property vector4d c1: Qt.vector4d(1, 1, 1, 1)
  property vector4d c2: Qt.vector4d(1, 1, 1, 1)
  property vector4d c3: Qt.vector4d(1, 1, 1, 1)
  property vector4d c4: Qt.vector4d(1, 1, 1, 1)
  property vector4d c5: Qt.vector4d(1, 1, 1, 1)
  property vector4d c6: Qt.vector4d(1, 1, 1, 1)
  property vector4d l0: Qt.vector4d(0, 1, 1, 1)
  property vector4d l1: Qt.vector4d(1, 1, 1, 1)

  // Sweep clock in seconds; it stops while the microphone is dead, so the
  // first frame after it comes back is already at the freeze point.
  property real sweepTime: 0

  function applyPalette() {
    var stops = glow.stops && glow.stops.length ? glow.stops : Tokens.glowStops("spectrum")
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

  // Off screen, so the drain has nothing left to show.
  function reset() {
    ramp.stop()
    progress = 0
  }

  function updateOrigin() {
    var point = Geometry.silhouettePoint(
      Geometry.sweepFraction(sweepTime), cornerRadiusValue, topFilletRadius, spill, width, height)
    origin = Qt.point(point.x, point.y)
  }

  onStopsChanged: applyPalette()
  onEpochChanged: {
    sweepTime = 0
    updateOrigin()
  }
  onWidthChanged: updateOrigin()
  onHeightChanged: updateOrigin()
  onListeningChanged: {
    ramp.to = listening ? 1 : 0
    ramp.restart()
  }
  Component.onCompleted: {
    applyPalette()
    updateOrigin()
    // Mounting mid-session blooms too: the ramp always starts from zero.
    if (listening) {
      ramp.to = 1
      ramp.restart()
    }
  }

  // No `from`: the track starts at the current value, so a session ending
  // mid-bloom reverses smoothly.
  NumberAnimation {
    id: ramp
    target: glow
    property: "progress"
    to: 0
    duration: glow.rampDuration * 1000
    easing.type: Easing.Linear
  }

  FrameAnimation {
    running: glow.listening && glow.alive && !glow.paused && glow.visible
    onTriggered: {
      glow.sweepTime += frameTime
      glow.updateOrigin()
    }
  }
}
