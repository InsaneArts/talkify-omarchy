import QtQuick
import "HudGeometry.js" as Geometry

// The window halo (research Variant 2): Edge Glow around the window the
// session started in, just outside its border and following its corners. It
// covers nothing and marks where the text is going without a word. On a
// fullscreen window it becomes the screen's own edge glow.
//
// It blooms around the window from the bottom centre when listening starts,
// swells with the voice, turns slowly for a latched session, freezes amber
// for a dead microphone, and drains back to the bottom centre at the
// finalize. Words, when turned on, and status lines ride in a small caption.
//
// A paused session holds still in the muted colour; a spoken send presses
// its ⏎ at the bottom centre, where the light drained to.
Item {
  id: placement

  property var stage: null
  property real dpr: 1
  property string fontFamily: ""
  property rect target: Qt.rect(0, 0, 0, 0)
  property bool fullscreen: false
  // Hyprland's window rounding, which the halo follows.
  property real windowRadius: 10

  readonly property var cfg: stage.settings
  readonly property real s: Math.max(0.6, cfg.scale)
  readonly property bool glowing: stage.listening && !stage.finalizing
  readonly property bool captioned: cfg.showsWords || stage.statusText !== ""

  // Just outside the window's border; the screen's edges when fullscreen.
  readonly property rect traced: fullscreen
    ? Qt.rect(0, 0, width, height)
    : Qt.rect(target.x - 3, target.y - 3, target.width + 6, target.height + 6)

  Connections {
    target: placement.stage
    function onMountSerialChanged() {
      ramp.stop()
      ring.progress = 0
      caption.settle()
      reveal.park()
    }
    function onMountedChanged() {
      if (!placement.stage.mounted) {
        ramp.stop()
        ring.progress = 0
        reveal.park()
      }
    }
  }

  // Around the window in 250 ms; back to the bottom centre at the finalize.
  onGlowingChanged: {
    ramp.to = glowing ? 1 : 0
    ramp.duration = glowing ? 250 : 400
    ramp.restart()
  }
  Component.onCompleted: if (glowing) { ramp.to = 1; ramp.restart() }

  NumberAnimation {
    id: ramp
    target: ring
    property: "progress"
    easing.type: Easing.OutQuad
  }

  GlowRing {
    id: ring
    path: placement.traced
    cornerRadius: placement.fullscreen ? 0 : placement.windowRadius + 3
    level: placement.stage.level
    alive: placement.stage.voiceAlive
    paused: placement.stage.paused
    look: placement.stage.look
    turning: placement.stage.latched && placement.stage.listening
    stops: placement.stage.glowStops
    dpr: placement.dpr
  }

  // A spoken send without a caption: the key on a small disc of the shape's
  // fill at the window's bottom centre.
  Item {
    id: sendDisc
    readonly property real size: 34 * placement.s
    visible: opacity > 0.001
    // Fades with the retract, so it is gone before the shape unmounts and
    // nothing is left animating after.
    opacity: placement.stage.sent && !placement.captioned && placement.stage.landing && !placement.stage.dismissing ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 160 } }
    x: Math.round(placement.target.x + placement.target.width / 2 - size / 2)
    y: Math.round(Geometry.captionBottom(placement.target, size) - size)
    width: size
    height: size

    CapsuleBody {
      bodyWidth: sendDisc.size
      bodyHeight: sendDisc.size
      cornerRadius: sendDisc.size / 2
      hudScale: placement.s * 0.6
      dpr: placement.dpr
      edgeTint: placement.stage.edge
      look: placement.stage.look
    }

    SendKey {
      anchors.centerIn: parent
      active: placement.stage.sent
      pressEpoch: placement.stage.sendEpoch
      textRgb: placement.stage.look.textRgb
      accentRgb: placement.stage.look.accentRgb
      hudScale: placement.s * 0.85
    }
  }

  FloatReveal {
    id: reveal
    visible: placement.captioned
    x: Math.round(placement.target.x + placement.target.width / 2 - width / 2)
    y: Math.round(Geometry.captionBottom(placement.target, caption.height) - height)
    width: caption.width
    height: caption.height
    revealed: placement.stage.revealed && placement.captioned
    style: placement.cfg.reveal
    anchorEdge: "bottom"
    travel: 24
    slideFades: true

    CaptionBody {
      id: caption
      stage: placement.stage
      dpr: placement.dpr
      fontFamily: placement.fontFamily
      hudScale: placement.s
      maxWidth: Math.min(0.6 * placement.target.width, 560 * placement.s)
      wordsOn: placement.cfg.showsWords
    }
  }
}
