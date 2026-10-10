import QtQuick
import "HudGeometry.js" as Geometry
import "HudTokens.js" as Tokens

// The Edge Glow particle cloud (HUDParticleCloudView, ParticleCloud.metal):
// 32 motes respawn at random spots inside the shape, drift toward the point
// the beam is lighting, and are consumed there or pop at the end of a
// hundred-frame life. The session ramp scales every mote's alpha and radius,
// so the cloud blooms and drains with the beam.
//
// Talkify ran the simulation in a compute kernel because SwiftUI's shader
// hooks keep no state across frames (ADR-0002). A Qt fragment shader keeps
// none either, so the stateful half runs here at the kernel's fixed 60 steps
// a second, in points rather than Retina drawable pixels, and
// particles.frag draws the result.
ShaderEffect {
  id: cloud

  property bool listening: false
  property bool alive: true
  // A paused session keeps no motes either: what is left is the beam, still.
  property bool paused: false
  property int epoch: 0
  property real cornerRadiusValue: 20
  property real topFilletRadius: 0
  // The motes' three colours, resolved by the stage.
  property var colors: Tokens.particleColors("spectrum")
  property real dpr: 1

  readonly property int count: 32
  readonly property real rampDuration: 0.4

  // The ramp the beam uses; a dead microphone zeroes it outright, leaving
  // only the static amber outline.
  property real ramp: 0
  readonly property real effectiveProgress: alive && !paused ? ramp : 0

  visible: effectiveProgress > 0
  fragmentShader: Qt.resolvedUrl("../shaders/particles.frag.qsb")

  property size viewSize: Qt.size(width, height)
  property real cornerRadius: cornerRadiusValue
  property vector4d color0: Qt.vector4d(1, 1, 1, 1)
  property vector4d color1: Qt.vector4d(1, 1, 1, 1)
  property vector4d color2: Qt.vector4d(1, 1, 1, 1)
  property vector4d p0: Qt.vector4d(0, 0, 0, 0)
  property vector4d p1: Qt.vector4d(0, 0, 0, 0)
  property vector4d p2: Qt.vector4d(0, 0, 0, 0)
  property vector4d p3: Qt.vector4d(0, 0, 0, 0)
  property vector4d p4: Qt.vector4d(0, 0, 0, 0)
  property vector4d p5: Qt.vector4d(0, 0, 0, 0)
  property vector4d p6: Qt.vector4d(0, 0, 0, 0)
  property vector4d p7: Qt.vector4d(0, 0, 0, 0)
  property vector4d p8: Qt.vector4d(0, 0, 0, 0)
  property vector4d p9: Qt.vector4d(0, 0, 0, 0)
  property vector4d p10: Qt.vector4d(0, 0, 0, 0)
  property vector4d p11: Qt.vector4d(0, 0, 0, 0)
  property vector4d p12: Qt.vector4d(0, 0, 0, 0)
  property vector4d p13: Qt.vector4d(0, 0, 0, 0)
  property vector4d p14: Qt.vector4d(0, 0, 0, 0)
  property vector4d p15: Qt.vector4d(0, 0, 0, 0)
  property vector4d p16: Qt.vector4d(0, 0, 0, 0)
  property vector4d p17: Qt.vector4d(0, 0, 0, 0)
  property vector4d p18: Qt.vector4d(0, 0, 0, 0)
  property vector4d p19: Qt.vector4d(0, 0, 0, 0)
  property vector4d p20: Qt.vector4d(0, 0, 0, 0)
  property vector4d p21: Qt.vector4d(0, 0, 0, 0)
  property vector4d p22: Qt.vector4d(0, 0, 0, 0)
  property vector4d p23: Qt.vector4d(0, 0, 0, 0)
  property vector4d p24: Qt.vector4d(0, 0, 0, 0)
  property vector4d p25: Qt.vector4d(0, 0, 0, 0)
  property vector4d p26: Qt.vector4d(0, 0, 0, 0)
  property vector4d p27: Qt.vector4d(0, 0, 0, 0)
  property vector4d p28: Qt.vector4d(0, 0, 0, 0)
  property vector4d p29: Qt.vector4d(0, 0, 0, 0)
  property vector4d p30: Qt.vector4d(0, 0, 0, 0)
  property vector4d p31: Qt.vector4d(0, 0, 0, 0)

  property var motes: []
  property real sweepTime: 0
  property real stepDebt: 0

  function makeMotes() {
    var list = []
    for (var i = 0; i < count; i++) {
      // Radius 3–12 and velocity 2–4 per axis were drawable pixels on a
      // Retina panel; halved, they are the same motes in points. A zeroed
      // position makes the first step scatter the cloud.
      var vx = 2 + Math.random() * 2
      var vy = 2 + Math.random() * 2
      list.push({
        radius: 3 + Math.random() * 9,
        speed: Math.sqrt(vx * vx + vy * vy) / 2,
        life: 0,
        x: 0,
        y: 0
      })
    }
    motes = list
  }

  function reset() {
    rampAnimation.stop()
    ramp = 0
  }

  function applyPalette() {
    var list = cloud.colors && cloud.colors.length >= 3 ? cloud.colors : Tokens.particleColors("spectrum")
    color0 = Tokens.rgba(list[0])
    color1 = Tokens.rgba(list[1])
    color2 = Tokens.rgba(list[2])
  }

  function target() {
    return Geometry.silhouettePoint(
      Geometry.sweepFraction(sweepTime), cornerRadiusValue, topFilletRadius, 0, width, height)
  }

  // One kernel dispatch: respawn what reached the origin, aged out, or never
  // started; move the rest one step toward the origin.
  function step(center) {
    for (var i = 0; i < motes.length; i++) {
      var m = motes[i]
      var dx = center.x - m.x
      var dy = center.y - m.y
      var distance = Math.sqrt(dx * dx + dy * dy)
      if (distance < 6 || (m.x === 0 && m.y === 0) || m.life > 100) {
        m.x = Math.max(0.001, Math.random() * width)
        m.y = Math.max(0.001, Math.random() * height)
        m.life = 0
      } else {
        m.x += dx / distance * m.speed
        m.y += dy / distance * m.speed
        m.life += 1
      }
    }
  }

  function publish() {
    var progress = effectiveProgress
    var packed = []
    for (var i = 0; i < count; i++) {
      var m = motes[i]
      // Young motes fade in over their life; the ramp scales the whole cloud.
      // The kernel truncated the radius to whole drawable pixels.
      var alpha = Math.min(m.life / 100, 1) * progress
      var radius = Math.max(0.5, Math.floor(m.radius * progress) / 2)
      packed.push(Qt.vector4d(m.x, m.y, radius, alpha))
    }
    p0 = packed[0]; p1 = packed[1]; p2 = packed[2]; p3 = packed[3]
    p4 = packed[4]; p5 = packed[5]; p6 = packed[6]; p7 = packed[7]
    p8 = packed[8]; p9 = packed[9]; p10 = packed[10]; p11 = packed[11]
    p12 = packed[12]; p13 = packed[13]; p14 = packed[14]; p15 = packed[15]
    p16 = packed[16]; p17 = packed[17]; p18 = packed[18]; p19 = packed[19]
    p20 = packed[20]; p21 = packed[21]; p22 = packed[22]; p23 = packed[23]
    p24 = packed[24]; p25 = packed[25]; p26 = packed[26]; p27 = packed[27]
    p28 = packed[28]; p29 = packed[29]; p30 = packed[30]; p31 = packed[31]
  }

  onColorsChanged: applyPalette()
  // In the same turn as the beam's, so both sweeps stay in phase.
  onEpochChanged: sweepTime = 0
  onListeningChanged: {
    rampAnimation.to = listening ? 1 : 0
    rampAnimation.restart()
  }
  Component.onCompleted: {
    makeMotes()
    applyPalette()
    if (listening) {
      rampAnimation.to = 1
      rampAnimation.restart()
    }
  }

  NumberAnimation {
    id: rampAnimation
    target: cloud
    property: "ramp"
    to: 0
    duration: cloud.rampDuration * 1000
    easing.type: Easing.Linear
  }

  FrameAnimation {
    running: cloud.visible
    onTriggered: {
      // The origin only travels while listening, as the beam's does.
      if (cloud.listening) cloud.sweepTime += frameTime
      var center = cloud.target()
      cloud.stepDebt += Math.min(frameTime, 0.1) * 60
      while (cloud.stepDebt >= 1) {
        cloud.step(center)
        cloud.stepDebt -= 1
      }
      cloud.publish()
    }
  }
}
