import QtQuick

// A number that follows `target` the way SwiftUI animates one: a spring given
// by perceptual duration and bounce (WWDC23 "Animate with springs": stiffness
// (2π/duration)², damping 4π(1 − bounce)/duration), or an ease curve. Qt's
// SpringAnimation is parameterized differently and has no duration, so the
// reveal's feel would be guessed at; this solves the same oscillator in closed
// form instead, and carries velocity through a retarget so an interrupted
// retract turns around rather than restarting.
//
// It only ticks while it is moving: once settled, nothing runs.
QtObject {
  id: spring

  property real target: 0
  property real duration: 0.4
  property real bounce: 0
  // "spring", "easeOut", "easeIn" or "linear".
  property string curve: "spring"
  // Off snaps straight to every new target.
  property bool animated: true

  property real value: 0
  property real velocity: 0
  readonly property bool moving: driver.running

  signal settled()

  property real _offset: 0
  property real _startVelocity: 0
  property real _from: 0
  property real _elapsed: 0
  property real _duration: 0.4
  property real _bounce: 0
  property string _curve: "spring"

  onTargetChanged: animated ? retarget() : snap(target)

  function snap(to) {
    driver.stop()
    value = to
    velocity = 0
  }

  // Starts toward the current target from wherever the value is now, with
  // the timing in effect at this moment.
  function retarget() {
    _offset = value - target
    _startVelocity = velocity
    _from = value
    _elapsed = 0
    _duration = Math.max(duration, 0.01)
    _bounce = Math.max(-0.99, Math.min(bounce, 0.99))
    _curve = curve
    if (Math.abs(_offset) < 1e-6 && Math.abs(_startVelocity) < 1e-6) {
      snap(target)
      return
    }
    driver.restart()
  }

  function _springAt(t) {
    var omega = 2 * Math.PI / _duration
    // SwiftUI's damping over critical damping is 1 − bounce for bounce ≥ 0.
    var zeta = _bounce >= 0 ? 1 - _bounce : 1 / (1 + _bounce)
    var x0 = _offset
    var v0 = _startVelocity
    var decay, x, v
    if (zeta < 1) {
      var omegaD = omega * Math.sqrt(1 - zeta * zeta)
      var b = (v0 + zeta * omega * x0) / omegaD
      decay = Math.exp(-zeta * omega * t)
      var c = Math.cos(omegaD * t)
      var s = Math.sin(omegaD * t)
      x = decay * (x0 * c + b * s)
      v = decay * ((-zeta * omega) * (x0 * c + b * s) + (-x0 * omegaD * s + b * omegaD * c))
    } else if (zeta === 1) {
      var k = v0 + omega * x0
      decay = Math.exp(-omega * t)
      x = decay * (x0 + k * t)
      v = decay * (k - omega * (x0 + k * t))
    } else {
      var root = omega * Math.sqrt(zeta * zeta - 1)
      var r1 = -zeta * omega + root
      var r2 = -zeta * omega - root
      var c2 = (v0 - r1 * x0) / (r2 - r1)
      var c1 = x0 - c2
      x = c1 * Math.exp(r1 * t) + c2 * Math.exp(r2 * t)
      v = c1 * r1 * Math.exp(r1 * t) + c2 * r2 * Math.exp(r2 * t)
    }
    return { x: x, v: v }
  }

  // CSS-style cubic Bézier timing, as Core Animation's ease curves are.
  function _bezier(x1, y1, x2, y2, progress) {
    var t = progress
    for (var i = 0; i < 8; i++) {
      var inv = 1 - t
      var x = 3 * inv * inv * t * x1 + 3 * inv * t * t * x2 + t * t * t - progress
      var dx = 3 * inv * inv * x1 + 6 * inv * t * (x2 - x1) + 3 * t * t * (1 - x2)
      if (Math.abs(x) < 1e-5 || Math.abs(dx) < 1e-6) break
      t = Math.min(1, Math.max(0, t - x / dx))
    }
    var u = 1 - t
    return 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t
  }

  function _advance(dt) {
    _elapsed += dt
    if (_curve !== "spring") {
      var p = Math.min(1, _elapsed / _duration)
      var eased = p
      if (_curve === "easeOut") eased = _bezier(0, 0, 0.58, 1, p)
      else if (_curve === "easeIn") eased = _bezier(0.42, 0, 1, 1, p)
      value = _from + (target - _from) * eased
      velocity = 0
      if (p >= 1) {
        snap(target)
        settled()
      }
      return
    }
    var state = _springAt(_elapsed)
    // Settled once the motion is below anything a pixel could show.
    if (_elapsed > 0.05 && Math.abs(state.x) < 1e-3 && Math.abs(state.v) < 1e-2) {
      snap(target)
      settled()
      return
    }
    velocity = state.v
    value = target + state.x
  }

  property FrameAnimation driver: FrameAnimation {
    running: false
    // A stalled first frame (a surface still mapping) must not skip the
    // motion, so one frame never advances more than a 24 Hz step.
    onTriggered: spring._advance(Math.min(frameTime, 1 / 24))
  }
}
