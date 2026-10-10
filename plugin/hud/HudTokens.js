.pragma library

// Colors shared across the HUD's voice visuals, Talkify's HUDVisualTokens and
// HUDGlowPalette in plain numbers. The system colors are macOS's dark-mode
// values: the HUD is black, and that is the appearance its palettes were
// tuned against.

var systemBlue = [0.039, 0.518, 1.0]
var systemPurple = [0.749, 0.353, 0.949]
var systemRed = [1.0, 0.271, 0.227]
var systemMint = [0.4, 0.831, 0.812]
var systemIndigo = [0.369, 0.361, 0.902]
var systemPink = [1.0, 0.216, 0.373]
var systemTeal = [0.251, 0.796, 0.878]
var systemGreen = [0.188, 0.82, 0.345]
var systemCyan = [0.392, 0.824, 1.0]
var systemOrange = [1.0, 0.624, 0.039]
var white = [1, 1, 1]

// The dead-microphone state's motionless amber: a dead microphone must look
// different from silence. The waveform family keeps its own dimmer orange.
var deadMicAmber = [1.0, 0.6, 0.16]

function rgba(rgb, a) {
  return Qt.vector4d(rgb[0], rgb[1], rgb[2], a === undefined ? 1 : a)
}

function mix(a, b, t) {
  return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]
}

// The beam's angular gradient stops, [color, location]. `accent` is the
// Omarchy theme's accent, for the one palette that follows the theme.
function glowStops(palette, accent) {
  switch (palette) {
  case "silver":
    return [[white, 0], [[0.62, 0.72, 1.0], 0.3], [white, 0.5], [[0.75, 0.78, 0.95], 0.75], [white, 1]]
  case "aurora":
    return [[systemMint, 0], [systemTeal, 0.3], [systemGreen, 0.5], [systemCyan, 0.75], [systemMint, 1]]
  case "sunset":
    return [[systemOrange, 0], [systemRed, 0.35], [systemPink, 0.6], [systemPurple, 0.85], [systemOrange, 1]]
  case "ocean":
    return [[systemBlue, 0], [systemCyan, 0.35], [systemIndigo, 0.65], [[0.0, 0.1, 0.45], 0.85], [systemBlue, 1]]
  case "mono":
    return [[white, 0], [white, 1]]
  case "accent":
    var tint = accent || white
    return [[tint, 0], [mix(tint, white, 0.55), 0.3], [tint, 0.5], [mix(tint, white, 0.35), 0.75], [tint, 1]]
  default:
    // Spectrum, the gist's palette and Talkify's default.
    return [[systemBlue, 0], [systemPurple, 0.2], [systemRed, 0.4], [systemMint, 0.5],
      [systemIndigo, 0.7], [systemPink, 0.9], [systemBlue, 1]]
  }
}

// The particle cloud's colors, cycled across the motes.
function particleColors(palette, accent) {
  switch (palette) {
  case "silver":
    return [[0.62, 0.72, 1.0], [0.85, 0.90, 1.0], [1.0, 1.0, 1.0]]
  case "aurora":
    return [[0.4, 1.0, 0.8], [0.3, 0.85, 0.85], [0.9, 1.0, 0.95]]
  case "sunset":
    return [[1.0, 0.6, 0.25], [1.0, 0.45, 0.6], [1.0, 0.9, 0.8]]
  case "ocean":
    return [[0.25, 0.75, 1.0], [0.3, 0.45, 1.0], [0.85, 0.95, 1.0]]
  case "mono":
    return [[1.0, 1.0, 1.0], [0.9, 0.9, 0.9], [0.75, 0.75, 0.75]]
  case "accent":
    var tint = accent || white
    return [tint, mix(tint, white, 0.4), mix(tint, white, 0.8)]
  default:
    return [[0.35, 0.45, 1.0], [0.75, 0.4, 1.0], [1.0, 0.5, 0.75]]
  }
}
