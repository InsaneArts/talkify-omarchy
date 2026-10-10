.pragma library

// The live draft in two tones: the part live insertion has already put in
// the window, solid, and the tail that can still change, at half strength.
// Apple draws its provisional text at about this weight, and Aqua's raw tail
// "arrives soft"; here the line between them is the daemon's, not a guess.

var pendingAlpha = 0.5

function escape(text) {
  return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

// How much of `full` is committed: the committed prefix when it really is
// one, nothing otherwise.
function committedLength(full, committed) {
  full = String(full || "")
  committed = String(committed || "")
  return committed.length > 0 && full.indexOf(committed) === 0 ? committed.length : 0
}

// StyledText for a draft. `solid` draws it all in one tone, for status lines;
// `rgb` is the text colour, whose half-strength the tail takes.
function styled(full, committed, solid, rgb) {
  full = String(full || "")
  if (solid || full.length === 0) return escape(full)
  var cut = committedLength(full, committed)
  var tail = full.substring(cut)
  if (tail.length === 0) return escape(full)
  return escape(full.substring(0, cut))
    + "<font color='#" + alphaHex(pendingAlpha) + rgbHex(rgb) + "'>" + escape(tail) + "</font>"
}

function rgbHex(rgb) {
  if (!rgb) return "ffffff"
  return alphaHex(rgb[0]) + alphaHex(rgb[1]) + alphaHex(rgb[2])
}

function alphaHex(alpha) {
  var value = Math.round(Math.max(0, Math.min(1, alpha)) * 255).toString(16)
  return value.length < 2 ? "0" + value : value
}
