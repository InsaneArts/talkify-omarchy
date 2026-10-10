import QtQuick
import "ThemeColors.js" as ThemeColors

// The waveform's other looks (HUDWaveformView): Talkify's bar architecture,
// AudioWaveform's capsules and area chart, WaveformScrubber's dots and curve,
// AudioKit's filled region — all fed by the same level history and finished
// with the WaveformSheen treatment. The drawing is waveform.frag.
//
// Sized by its parent to the drawn strip; it reaches `margin` past it on
// every side so the sheen's offset taps have pixels to land on.
ShaderEffect {
  id: bars

  property string waveformStyle: "capsules"
  property var history: []
  property real level: 0
  property bool live: false
  property bool alive: true
  // The session is paused: the bars stop in the muted colour.
  property bool paused: false
  property real dpr: 1

  fragmentShader: Qt.resolvedUrl("../shaders/waveform.frag.qsb")

  property size viewSize: Qt.size(width, height)
  property real margin: 8
  property real style: {
    switch (waveformStyle) {
    case "article": return 0
    case "silver": return 1
    case "capsules": return 2
    case "dots": return 3
    case "curve": return 4
    case "filled": return 5
    default: return 6
    }
  }
  property real time: 0
  // Uniforms are floats; a bool would arrive as raw bits.
  property real micAlive: alive && !paused ? 1 : 0
  // The fill: Talkify's blue-silver ends around white, or the theme's tint
  // around the same bright body (ThemeColors).
  property var look: null
  property vector4d waveEdge: look ? look.waveEdge : Qt.vector4d(0.62, 0.72, 1.0, 0.75)
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

  // Capsules are sized with SwiftUI frames, which the level animation eases
  // over 50 ms; the other looks are paths, which it cannot tween, so they
  // land on each tick. Kept as Talkify draws them.
  readonly property bool eases: waveformStyle === "capsules"
  property var _from: []
  property var _to: []
  property real _blend: 1

  function rawAt(i) {
    var to = Number(_to[i]) || 0
    if (!eases || _blend >= 1) return to
    var from = Number(_from[i]) || 0
    return from + (to - from) * _blend
  }

  function push() {
    var v = rawAt
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
    var current = []
    for (var i = 0; i < 56; i++) current.push(rawAt(i))
    _from = current
    _to = history ? history.slice() : []
    _blend = eases ? 0 : 1
    push()
  }
  Component.onCompleted: {
    _to = history ? history.slice() : []
    push()
  }

  FrameAnimation {
    running: bars.live && !bars.paused && bars.visible
    onTriggered: {
      bars.time += frameTime
      if (bars._blend < 1) {
        bars._blend = Math.min(1, bars._blend + frameTime / 0.05)
        bars.push()
      }
    }
  }
}
