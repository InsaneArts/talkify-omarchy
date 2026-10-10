import QtQuick
import "ThemeColors.js" as ThemeColors

// The Chart Line look rendered as a conveyor (ChartLineWaveView): each level
// tick shifts the buffer one slot, and between ticks the line glides left by
// the fraction of the measured tick interval that has passed, so the points
// move continuously instead of jumping 46 times a second. The drawing is
// chartline.frag.
//
// Paused when the session is over or the microphone is dead, so the amber
// line is motionless: a dead microphone must look different from silence.
// A paused session stops it the same way, in the muted colour instead.
ShaderEffect {
  id: wave

  property var history: []
  property real level: 0
  // Listening with a live microphone: drives the conveyor and the sweep.
  property bool live: false
  property bool alive: true
  // The session is paused: one still line in the muted colour.
  property bool paused: false
  property real dpr: 1

  fragmentShader: Qt.resolvedUrl("../shaders/chartline.frag.qsb")

  property size viewSize: Qt.size(width, height)
  property real scroll: 0
  property real time: 0
  // Lifts the rest line toward the shape's visual center: the housing strip
  // above makes the band's own middle read low. Ten points on Talkify's
  // standard band, in proportion on a smaller one.
  property real restOffset: -10 * Math.min(1, height / 52)
  // SwiftUI blur radii read as about two standard deviations: Talkify
  // budgets 28 points of spill for a radius-12 glow, which only fits if so.
  property real blurScale: 0.5
  // Uniforms are floats; a bool would arrive as raw bits.
  property real micAlive: alive && !paused ? 1 : 0
  // The colours: Talkify's silver around a white core, or the theme's tint
  // around the same bright core (ThemeColors).
  property var look: null
  property vector4d lineEdge: look ? look.lineEdge : Qt.vector4d(0.68, 0.74, 0.88, 0.85)
  property vector4d lineMid: look ? look.lineMid : Qt.vector4d(0.82, 0.86, 0.95, 1)
  property vector4d coreColor: look ? look.core : Qt.vector4d(1, 1, 1, 1)
  property vector4d stillColor: ThemeColors.still(look, alive)
  property vector4d s0: Qt.vector4d(0, 0, 0, 0)
  property vector4d s1: Qt.vector4d(0, 0, 0, 0)
  property vector4d s2: Qt.vector4d(0, 0, 0, 0)
  property vector4d s3: Qt.vector4d(0, 0, 0, 0)
  property vector4d s4: Qt.vector4d(0, 0, 0, 0)
  property vector4d s5: Qt.vector4d(0, 0, 0, 0)
  property vector4d s6: Qt.vector4d(0, 0, 0, 0)
  property vector4d s7: Qt.vector4d(0, 0, 0, 0)
  property vector4d s8: Qt.vector4d(0, 0, 0, 0)
  property vector4d s9: Qt.vector4d(0, 0, 0, 0)
  property vector4d s10: Qt.vector4d(0, 0, 0, 0)
  property vector4d s11: Qt.vector4d(0, 0, 0, 0)
  property vector4d s12: Qt.vector4d(0, 0, 0, 0)
  property vector4d s13: Qt.vector4d(0, 0, 0, 0)

  // Seconds of one level tick, measured and smoothed; scroll speed follows.
  property real tickInterval: 0.022
  property real lastTick: -1
  function now() {
    return Date.now() / 1000
  }

  function push() {
    var values = history || []
    var v = function (i) { return Number(values[i]) || 0 }
    s0 = Qt.vector4d(v(0), v(1), v(2), v(3))
    s1 = Qt.vector4d(v(4), v(5), v(6), v(7))
    s2 = Qt.vector4d(v(8), v(9), v(10), v(11))
    s3 = Qt.vector4d(v(12), v(13), v(14), v(15))
    s4 = Qt.vector4d(v(16), v(17), v(18), v(19))
    s5 = Qt.vector4d(v(20), v(21), v(22), v(23))
    s6 = Qt.vector4d(v(24), v(25), v(26), v(27))
    s7 = Qt.vector4d(v(28), v(29), v(30), v(31))
    s8 = Qt.vector4d(v(32), v(33), v(34), v(35))
    s9 = Qt.vector4d(v(36), v(37), v(38), v(39))
    s10 = Qt.vector4d(v(40), v(41), v(42), v(43))
    s11 = Qt.vector4d(v(44), v(45), v(46), v(47))
    s12 = Qt.vector4d(v(48), v(49), v(50), v(51))
    s13 = Qt.vector4d(v(52), v(53), v(54), v(55))
  }

  onHistoryChanged: {
    var t = now()
    if (lastTick >= 0) {
      var gap = t - lastTick
      if (gap < 0.1) tickInterval = tickInterval * 0.8 + gap * 0.2
    }
    lastTick = t
    scroll = 0
    push()
  }
  Component.onCompleted: push()

  FrameAnimation {
    running: wave.live && !wave.paused && wave.visible
    onTriggered: {
      wave.time += frameTime
      if (wave.lastTick >= 0)
        wave.scroll = Math.min(1, Math.max(0, (wave.now() - wave.lastTick) / wave.tickInterval))
    }
  }
}
