.pragma library

// The HUD's colours, either Talkify's own (black, silver, the spectrum) or
// derived from the Omarchy theme's colors.toml. Pure: text in, a "look" out,
// so the same rules serve the live HUD, the Settings previews and the
// harness reading a stock theme.
//
// What the theme gives, and what it becomes:
// - the glow palette (Edge Glow, the halo, the particles): the window border
//   gradient first (the theme's signature), then the accent, the cursor and
//   the vivid terminal colours; near-duplicates and dark or grey entries
//   dropped, ordered by hue so the sweep turns smoothly, four to six colours.
//   A theme with no vivid colours at all (white, vantablack) gets a quiet
//   ramp of its own foreground and accent instead;
// - the waveform keeps Talkify's bright core, the part that reads as voice,
//   with its ends and sheen tinted toward the foreground and accent;
// - the shape is the theme's background, darkened to keep its contrast, with
//   the foreground as text and the accent on the ghost;
// - the dead-microphone amber stays amber: it is a warning, not decoration;
// - the accent marks what Talkify changed or will change (a vocabulary hit,
//   spoken punctuation, the send key); the muted colour, halfway from the
//   text to the shape, is a paused session's voice.

function clamp01(x) {
  return Math.max(0, Math.min(1, x))
}

// `key = "value"` lines; anything else is ignored.
function parseToml(text) {
  var out = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var match = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']([^"']*)["']/)
    if (match) out[match[1]] = match[2]
  }
  return out
}

function hexPairs(hex) {
  var parts = []
  for (var i = 0; i + 1 < hex.length; i += 2) parts.push(parseInt(hex.substr(i, 2), 16) / 255)
  return parts
}

// One colour from any of the forms themes use: #rgb, #rrggbb, #rrggbbaa,
// 0xaarrggbb, rgb(rrggbb), rgba(rrggbbaa), rgb(r, g, b), rgba(r, g, b, a).
function parseColor(token) {
  var s = String(token || "").trim()
  var m = s.match(/^#([0-9a-fA-F]{3})$/)
  if (m) {
    var h = m[1]
    return [parseInt(h[0] + h[0], 16) / 255, parseInt(h[1] + h[1], 16) / 255, parseInt(h[2] + h[2], 16) / 255, 1]
  }
  m = s.match(/^#([0-9a-fA-F]{6})([0-9a-fA-F]{2})?$/)
  if (m) {
    var p = hexPairs(m[1])
    return [p[0], p[1], p[2], m[2] ? parseInt(m[2], 16) / 255 : 1]
  }
  m = s.match(/^0x([0-9a-fA-F]{8})$/)
  if (m) {
    var q = hexPairs(m[1])
    return [q[1], q[2], q[3], q[0]]
  }
  m = s.match(/^rgba?\(\s*([0-9a-fA-F]{6})([0-9a-fA-F]{2})?\s*\)$/)
  if (m) {
    var r = hexPairs(m[1])
    return [r[0], r[1], r[2], m[2] ? parseInt(m[2], 16) / 255 : 1]
  }
  m = s.match(/^rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*(?:,\s*([\d.]+)\s*)?\)$/)
  if (m) {
    var a = m[4] === undefined ? 1 : Number(m[4])
    return [Number(m[1]) / 255, Number(m[2]) / 255, Number(m[3]) / 255, a > 1 ? a / 255 : a]
  }
  return null
}

// Hyprland's border: one or more colours and an optional angle.
function parseBorder(value) {
  var out = []
  var tokens = String(value || "").match(/(rgba?\([^)]*\)|0x[0-9a-fA-F]{8}|#[0-9a-fA-F]{3,8})/g) || []
  for (var i = 0; i < tokens.length; i++) {
    var c = parseColor(tokens[i])
    if (c) out.push(c)
  }
  return out
}

function hsv(c) {
  var r = c[0], g = c[1], b = c[2]
  var max = Math.max(r, g, b), min = Math.min(r, g, b)
  var d = max - min
  var h = 0
  if (d > 0) {
    if (max === r) h = ((g - b) / d) % 6
    else if (max === g) h = (b - r) / d + 2
    else h = (r - g) / d + 4
    h *= 60
    if (h < 0) h += 360
  }
  return { h: h, s: max > 0 ? d / max : 0, v: max }
}

function luminance(c) {
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
}

function mix(a, b, t) {
  return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, 1]
}

function scale(c, k) {
  return [c[0] * k, c[1] * k, c[2] * k, 1]
}

function hueDistance(a, b) {
  var d = Math.abs(a - b) % 360
  return d > 180 ? 360 - d : d
}

function vec(c, alpha) {
  var a = alpha === undefined ? (c.length > 3 ? c[3] : 1) : alpha
  return Qt.vector4d(c[0], c[1], c[2], a)
}

function premul(c, alpha) {
  var a = alpha === undefined ? 1 : alpha
  return Qt.vector4d(c[0] * a, c[1] * a, c[2] * a, a)
}

function qcolor(c, alpha) {
  return Qt.rgba(c[0], c[1], c[2], alpha === undefined ? 1 : alpha)
}

function hex(c) {
  function two(x) {
    var v = Math.round(clamp01(x) * 255).toString(16)
    return v.length < 2 ? "0" + v : v
  }
  return two(c[0]) + two(c[1]) + two(c[2])
}

// The vivid colours worth sweeping through, in the order the theme ranks
// them: its border, its accent, its cursor, then its terminal palette.
var paletteKeys = ["accent", "cursor"]
  .concat(["color0", "color1", "color2", "color3", "color4", "color5", "color6", "color7",
    "color8", "color9", "color10", "color11", "color12", "color13", "color14", "color15"])
  // Omarchy 4 names its colours; "brown" is left out, it is the one that is
  // muddy by design.
  .concat(["red", "orange", "yellow", "green", "cyan", "blue", "magenta",
    "bright_red", "bright_yellow", "bright_green", "bright_cyan", "bright_blue", "bright_magenta"])

function glowColors(raw) {
  var candidates = parseBorder(raw.hyprland_active_border)
  for (var i = 0; i < paletteKeys.length; i++) {
    var c = parseColor(raw[paletteKeys[i]])
    if (c) candidates.push(c)
  }
  var kept = []
  for (var j = 0; j < candidates.length && kept.length < 6; j++) {
    var hc = hsv(candidates[j])
    if (hc.s < 0.25 || hc.v < 0.45) continue
    var duplicate = false
    for (var k = 0; k < kept.length; k++) {
      var hk = hsv(kept[k])
      if (hueDistance(hc.h, hk.h) < 16 && Math.abs(hc.v - hk.v) < 0.3) {
        duplicate = true
        break
      }
    }
    if (!duplicate) kept.push(candidates[j])
  }
  // Two is enough: a border gradient alone is the theme's signature.
  if (kept.length >= 2) {
    kept.sort(function (a, b) { return hsv(a).h - hsv(b).h })
    return kept.slice(0, 6)
  }
  return null
}

// A theme without vivid colours: a ramp of its own greys, foreground to
// accent and back, so the glow still reads as the theme rather than a
// rainbow it never had.
function quietColors(fg, accent, light) {
  var far = light ? scale(fg, 1) : mix(fg, [1, 1, 1, 1], 0.3)
  return [far, mix(fg, accent, 0.5), accent, mix(accent, fg, 0.25)]
}

function stops(colors) {
  var out = []
  for (var i = 0; i < colors.length; i++) out.push([[colors[i][0], colors[i][1], colors[i][2]], i / colors.length])
  out.push([[colors[0][0], colors[0][1], colors[0][2]], 1])
  return out
}

// Talkify's own look, exactly as the Mac draws it. Its accent is the blue
// the Mac underlines uncertain words in.
function talkify(edgeBase) {
  var white = [1, 1, 1, 1]
  var accent = [0.42, 0.64, 1.0, 1]
  var muted = [0.55, 0.56, 0.6, 1]
  return {
    name: "talkify",
    light: false,
    fill: Qt.vector4d(0, 0, 0, 1),
    edgeBase: edgeBase || white,
    shadowAlpha: 0.35,
    text: qcolor(white),
    textRgb: white,
    ghost: qcolor(white),
    core: vec(white),
    coreColor: qcolor(white),
    lineEdge: Qt.vector4d(0.68, 0.74, 0.88, 0.85),
    lineMid: Qt.vector4d(0.82, 0.86, 0.95, 1),
    waveEdge: Qt.vector4d(0.62, 0.72, 1.0, 0.75),
    glowStops: null,
    particles: null,
    ripple: Qt.vector4d(1, 1, 1, 1),
    sweep: qcolor(white, 0.1),
    accentRgb: accent,
    accent: qcolor(accent),
    mutedRgb: muted,
    muted: qcolor(muted),
    still: vec(muted, 0.7)
  }
}

// The look for a theme's colors.toml contents, with the shell's own colours
// as the fallback for anything the file does not say.
function derive(raw, fallback) {
  raw = raw || {}
  fallback = fallback || {}
  var fg = parseColor(raw.foreground) || fallback.foreground || [0.8, 0.8, 0.8, 1]
  var bg = parseColor(raw.background) || fallback.background || [0.06, 0.06, 0.07, 1]
  var accent = parseColor(raw.accent) || fallback.accent || fg
  var light = raw.mode === "light" || (raw.mode !== "dark" && luminance(bg) > 0.5)

  // The shape: the theme's background, darkened until it holds its own
  // against the desktop; a light theme keeps a light shape.
  // Dark: well under the background, since windows wear that background and
  // the shape has to stand off them; it keeps the background's hue.
  var fill = light ? scale(bg, 0.94) : scale(bg, 0.5)
  if (!light) {
    var lum = luminance(fill)
    if (lum > 0.035) fill = scale(fill, 0.035 / lum)
  }

  var white = [1, 1, 1, 1]
  // The voice's bright core: white on a dark shape; on a light one the
  // foreground, which is the theme's own strongest contrast there.
  var core = light ? fg : white
  var colors = glowColors(raw) || quietColors(fg, accent, light)
  var mid = Math.floor(colors.length / 2)
  // The theme's own muted colour where it stands off the shape; several
  // dark themes' sit too close to the darkened fill to read, and get the
  // foreground halfway to the fill instead.
  var themeMuted = parseColor(raw.muted)
  var muted = themeMuted && Math.abs(luminance(themeMuted) - luminance(fill)) >= 0.15
    ? themeMuted : mix(fg, fill, 0.45)

  return {
    name: "theme",
    light: light,
    fill: vec(fill, 1),
    edgeBase: fg,
    // A tinted shape sits nearer its surroundings than black does, so its
    // hairline carries more of the silhouette.
    edgeBoost: light ? 2.2 : 1.8,
    shadowAlpha: light ? 0.2 : 0.35,
    text: qcolor(fg),
    textRgb: fg,
    ghost: qcolor(accent),
    core: vec(core, 1),
    coreColor: qcolor(core),
    lineEdge: vec(fg, 0.85),
    lineMid: vec(mix(core, accent, 0.3), 1),
    waveEdge: vec(mix(fg, accent, 0.35), 0.8),
    glowStops: stops(colors),
    particles: [colors[0], colors[mid], colors[colors.length - 1]],
    ripple: vec(accent, 1),
    sweep: qcolor(accent, 0.16),
    accentRgb: [accent[0], accent[1], accent[2], 1],
    accent: qcolor(accent),
    mutedRgb: muted,
    muted: qcolor(muted),
    still: vec(muted, light ? 0.9 : 0.75)
  }
}

// The dead-microphone amber as the voice visuals' still colour, straight
// alpha.
var deadStill = Qt.vector4d(1.0, 0.624, 0.039, 0.55)

// What a voice visual draws when it stops: amber for a dead microphone, the
// muted colour for a paused session.
function still(look, alive) {
  if (!alive) return deadStill
  return look && look.still ? look.still : Qt.vector4d(0.55, 0.56, 0.6, 0.7)
}

// The hairline, from a look and the user's edge strength.
function edge(look, alpha) {
  var a = clamp01((isFinite(alpha) ? alpha : 0.09) * (look.edgeBoost || 1))
  var c = look.edgeBase
  return Qt.vector4d(c[0] * a, c[1] * a, c[2] * a, a)
}
