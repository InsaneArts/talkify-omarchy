.pragma library

// Frames for the dictation HUD, after Talkify's HUDNotchGeometry and HUDMetrics
// (ADR-0001): a fixed-size host window pinned to the top center whose size
// never changes during a session, and a shape inside it that does.
//
// What the display imposes (the housing band, the fillets, the window) is kept
// apart from what the user resizes (everything that follows the HUD scale).
// The housing band is the Omarchy bar's height rather than a notch: there is no
// camera to clear, but there is a bar, and content below it stays readable.

var minimumScale = 0.2
var maximumScale = 1
// Below this the 15-point draft falls under 6 points, which is not text anyone
// reads; the sizes beneath it are for the visuals that replace the draft.
var minimumReadableScale = 0.4

// Slack on the left, right and bottom so the shape's shadow and the edge
// glow's spill are not clipped by the fixed window. Nothing at the top: that
// edge is the screen edge and the shape is flush against it.
var shadowPadding = 44

// Unscaled, like Talkify's: the flare meets the screen edge, which does not
// shrink with the HUD.
var filletSize = 11

var placements = ["pill", "window", "halo", "island", "pointer", "notch"]
var visuals = ["waveform", "glow", "glow-draft", "compact"]
var waveformStyles = ["chart-line", "capsules", "dots", "filled", "curve", "article", "silver", "chart-area"]
var reveals = ["slide", "unfurl", "bloom", "drift"]
var longDrafts = ["grow-down", "tail-only", "shrink-to-fit"]
var palettes = ["spectrum", "silver", "aurora", "sunset", "ocean", "mono"]

function pick(value, allowed, fallback) {
  return allowed.indexOf(value) !== -1 ? value : fallback
}

// Compact and Edge Glow + Draft are built around the live draft, so a
// placeholder there would be words nobody spoke.
function showsDraftWhileListening(visual) {
  return visual === "compact" || visual === "glow-draft"
}

// Whether the words show, given the words setting. "auto" is each
// placement's natural choice:
// - notch: the visual decides, as on the Mac (Compact and Edge Glow + Draft
//   are built around the draft; Waveform and Edge Glow replace it);
// - pill: on, unless live insertion is already putting the words where they
//   land, in which case the pill stays a pill;
// - window: on, it is a caption;
// - halo, island, pointer: off, they mark where and that, not what.
function showsWords(placement, visual, words, insertionLive) {
  if (words === "on") return true
  if (words === "off") return false
  switch (placement) {
  case "notch": return showsDraftWhileListening(visual)
  case "pill": return !insertionLive
  case "window": return true
  default: return false
  }
}

function usesEdgeGlow(visual) {
  return visual === "glow" || visual === "glow-draft"
}

// Held to the visual's floor, so a layout built around live text never
// shrinks past reading it, and read once per session so the shape cannot
// change size partway through.
function sessionScale(picked, visual) {
  var scale = Number(picked)
  if (!isFinite(scale)) scale = maximumScale
  var floor = showsDraftWhileListening(visual) ? minimumReadableScale : minimumScale
  return Math.min(Math.max(scale, floor), maximumScale)
}

function metrics(scale) {
  return {
    scale: scale,
    contentWidth: 540 * scale,
    textBandHeight: 36 * scale,
    // The downward-growing long draft caps at a few wrapped lines.
    maxTextBandHeight: 120 * scale,
    visualBandHeight: 24 * scale,
    glowDraftStageHeight: 40 * scale,
    waveBandHeight: 64 * scale,
    bottomCornerRadius: 20 * scale
  }
}

// The notch's frame inside the HUD surface: sized for the tallest layout at
// this scale, whichever visual is picked (with the words on, a visual band
// can carry a text band under it), so the frame never resizes under a shape.
function windowSize(screenWidth, housingHeight, scale) {
  var m = metrics(scale)
  return {
    width: Math.ceil(Math.min(m.contentWidth + shadowPadding * 2, screenWidth)),
    height: Math.ceil(housingHeight + m.waveBandHeight + m.maxTextBandHeight + shadowPadding)
  }
}

// The eased ping-pong position along the silhouette at time `t` (left tip,
// bottom, right tip, back), phase-shifted so t = 0 lands at bottom center.
// Mostly linear: full smoothstep parks the origin at each flank tip, which
// reads as the glow stopping to wait for the particles.
var sweepDuration = 4.0

function sweepFraction(t) {
  var phase = (t / sweepDuration + 0.5) % 2.0
  var linear = phase < 1.0 ? phase : 2.0 - phase
  var eased = linear * linear * (3.0 - 2.0 * linear)
  return linear + (eased - linear) * 0.3
}

// The point at `fraction` of the open silhouette's arc length (left flank
// tip to right flank tip, never the top edge), mirroring the edge glow
// shader's path. Shared by the beam and the particle cloud so the motes chase
// the point the beam lights.
function silhouettePoint(fraction, cornerRadius, topFilletRadius, inset, width, height) {
  var left = inset
  var right = width - inset
  var bottom = height - inset
  var radius = Math.min(cornerRadius, bottom / 2)
  var topRadius = Math.min(topFilletRadius, bottom / 2)

  var flank = Math.max(0, bottom - radius - topRadius)
  var topCorner = Math.PI * topRadius / 2
  var corner = Math.PI * radius / 2
  var run = (right - left) - 2 * radius
  var total = 2 * flank + 2 * corner + run + 2 * topCorner
  var distance = Math.min(Math.max(fraction, 0), 1) * total
  var angle
  if (topRadius > 0) {
    if (distance < topCorner) {
      angle = -Math.PI / 2 + distance / topRadius
      return { x: left - topRadius + topRadius * Math.cos(angle), y: topRadius + topRadius * Math.sin(angle) }
    }
    distance -= topCorner
  }
  if (distance < flank) return { x: left, y: topRadius + distance }
  distance -= flank
  if (distance < corner) {
    angle = Math.PI - distance / radius
    return { x: left + radius + radius * Math.cos(angle), y: bottom - radius + radius * Math.sin(angle) }
  }
  distance -= corner
  if (distance < run) return { x: left + radius + distance, y: bottom }
  distance -= run
  if (distance < corner) {
    angle = Math.PI / 2 - distance / radius
    return { x: right - radius + radius * Math.cos(angle), y: bottom - radius + radius * Math.sin(angle) }
  }
  distance -= corner
  if (distance < flank) return { x: right, y: bottom - radius - distance }
  distance -= flank
  if (topRadius > 0) {
    angle = Math.PI + distance / topRadius
    return { x: right + topRadius + topRadius * Math.cos(angle), y: topRadius + topRadius * Math.sin(angle) }
  }
  return { x: right, y: 0 }
}

// Chat apps and terminals keep their input at the bottom of the window, so
// a caption leaves this much of the window's bottom uncovered.
var captionKeepClear = 72
var captionGap = 8

// Where a caption's bottom edge goes for a window `rect`: just above the
// window's bottom band, or above the window's top edge when the window is
// too short for that.
function captionBottom(rect, captionHeight) {
  var inside = rect.y + rect.height - captionKeepClear - captionGap
  if (inside - captionHeight >= rect.y + captionGap) return inside
  return rect.y - captionGap
}

// Whether a window can carry a caption at all: wide enough to read one, and
// with room for it inside or above.
function windowFitsCaption(rect, captionHeight) {
  if (rect.width < 320 || rect.height < 1) return false
  var bottom = captionBottom(rect, captionHeight)
  return bottom - captionHeight >= 0
}
