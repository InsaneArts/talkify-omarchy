import QtQuick
import "HudGeometry.js" as Geometry

// The window caption (research Variant 1): the caption pill pinned to the
// window the session started in, the nearest Wayland gets to dictating "at
// the cursor", and the one HUD that says which window the text is going to.
//
// Chat apps and terminals keep their input at the bottom, so the caption
// never covers the window's bottom 72 points: it sits just above that band,
// or above the window's top edge when the window is too short for it. It
// follows the window when it moves. The HUD falls back to the pill when
// there is no window, or one too small to carry a caption.
Item {
  id: placement

  property var stage: null
  property real dpr: 1
  property string fontFamily: ""
  // The target window in this surface's coordinates.
  property rect target: Qt.rect(0, 0, 0, 0)

  readonly property var cfg: stage.settings
  readonly property real s: Math.max(0.6, cfg.scale)
  readonly property real anchorX: target.x + target.width / 2
  readonly property real anchorBottom: Geometry.captionBottom(target, caption.height)

  function snapToWindow() {
    xSpring.snap(anchorX)
    bottomSpring.snap(anchorBottom)
  }

  Connections {
    target: placement.stage
    function onMountSerialChanged() {
      caption.settle()
      placement.snapToWindow()
      reveal.park()
    }
    function onMountedChanged() { if (!placement.stage.mounted) reveal.park() }
  }
  Component.onCompleted: snapToWindow()

  // Glides after the window when it moves, rather than jumping a poll at a
  // time.
  SpringValue {
    id: xSpring
    duration: 0.3
    target: placement.anchorX
  }
  SpringValue {
    id: bottomSpring
    duration: 0.3
    target: placement.anchorBottom
  }

  FloatReveal {
    id: reveal
    x: Math.round(xSpring.value - width / 2)
    y: Math.round(bottomSpring.value - height)
    width: caption.width
    height: caption.height
    revealed: placement.stage.revealed
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
