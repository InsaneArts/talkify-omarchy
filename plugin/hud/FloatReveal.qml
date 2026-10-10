import QtQuick

// Talkify's four reveal styles for a shape that is not hanging from the top
// edge: the same timings as the notch (HudSurface), turned to face whichever
// edge the shape grows from. Bounce still lives only in scale anchored at
// that edge, never in position.
Item {
  id: reveal

  property bool revealed: false
  property string style: "slide"
  // The edge the shape grows from: "bottom", "top" or "center".
  property string anchorEdge: "bottom"
  // How far Slide travels: from past the screen edge for a shape that sits
  // on one, a short way for a floating one.
  property real travel: 40
  // A floating shape fades as it slides, so it never crosses content opaque.
  property bool slideFades: false
  property real bloomFrom: 0.55

  default property alias content: inner.data
  readonly property real value: spring.value
  readonly property bool moving: spring.moving

  function park() {
    spring.snap(0)
  }

  onRevealedChanged: {
    if (revealed) {
      switch (style) {
      case "unfurl": spring.curve = "spring"; spring.duration = 0.45; spring.bounce = 0.3; break
      case "bloom": spring.curve = "spring"; spring.duration = 0.4; spring.bounce = 0.25; break
      case "drift": spring.curve = "easeOut"; spring.duration = 0.24; spring.bounce = 0; break
      default: spring.curve = "spring"; spring.duration = 0.4; spring.bounce = 0
      }
    } else if (style === "drift") {
      spring.curve = "easeIn"
      spring.duration = 0.18
      spring.bounce = 0
    } else {
      spring.curve = "spring"
      spring.duration = 0.28
      spring.bounce = 0
    }
    spring.target = revealed ? 1 : 0
  }

  SpringValue {
    id: spring
  }

  readonly property real direction: anchorEdge === "top" ? -1 : 1
  readonly property real offset: {
    var r = spring.value
    if (style === "slide") return direction * travel * (1 - r)
    if (style === "drift") return direction * 14 * (1 - r)
    return 0
  }
  readonly property real scaleX: style === "bloom" ? bloomFrom + (1 - bloomFrom) * spring.value : 1
  readonly property real scaleY: {
    if (style === "unfurl") return Math.max(0.001, 0.001 + 0.999 * spring.value)
    if (style === "bloom") return bloomFrom + (1 - bloomFrom) * spring.value
    return 1
  }
  readonly property real fade: {
    if (style === "bloom" || style === "drift" || (style === "slide" && slideFades))
      return Math.max(0, Math.min(1, spring.value))
    return 1
  }

  Item {
    id: inner
    anchors.fill: parent
    opacity: reveal.fade
    visible: reveal.fade > 0.001
    transform: [
      Scale {
        origin.x: inner.width / 2
        origin.y: reveal.anchorEdge === "bottom" ? inner.height : (reveal.anchorEdge === "top" ? 0 : inner.height / 2)
        xScale: reveal.scaleX
        yScale: reveal.scaleY
      },
      Translate { y: reveal.offset }
    ]
  }
}
