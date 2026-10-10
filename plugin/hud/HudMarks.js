.pragma library

// The marks the daemon lays over a Live draft (docs/protocol.md, `hud.marks`):
// what the Tidy pass and the vocabulary will do to the words, so the HUD can
// show it before the text lands. Pure, so the rules are pinned in
// dev/tests.qml without a window.
//
// - filler: a word the Tidy pass drops; faint, folded out at the finalize;
// - scratched: a phrase "scratch that" removes; struck through, folded out;
// - punctuation: a spoken mark ("comma"); the word over an accent underline,
//   turning into the mark at the finalize;
// - vocabulary: a word the vocabulary rewrites; the accent, for a moment,
//   and at the finalize it turns into its `replacement` ("omachi" lands as
//   "Omarchy");
// - send: the send phrase; a ⏎ chip in its place.

var kinds = ["filler", "scratched", "punctuation", "vocabulary", "send"]

// Marks clamped to the text and sorted, with unknown kinds and overlaps
// dropped (the earlier mark wins), so a draft and marks that disagree can
// only draw less, never throw.
function normalize(text, marks) {
  var length = String(text || "").length
  var list = []
  for (var i = 0; marks && i < marks.length; i++) {
    var m = marks[i]
    if (!m || kinds.indexOf(m.kind) === -1) continue
    var start = Math.max(0, Math.min(length, Math.floor(Number(m.start) || 0)))
    var end = Math.max(start, Math.min(length, Math.floor(Number(m.end) || 0)))
    if (end > start) {
      var mark = { start: start, end: end, kind: m.kind }
      if (m.kind === "vocabulary" && m.replacement) mark.replacement = String(m.replacement)
      list.push(mark)
    }
  }
  list.sort(function (a, b) { return a.start - b.start || b.end - a.end })
  var kept = []
  var reach = 0
  for (var j = 0; j < list.length; j++) {
    if (list[j].start < reach) continue
    kept.push(list[j])
    reach = list[j].end
  }
  return kept
}

// The mark a spoken punctuation phrase becomes. Line breaks are drawn as
// glyphs, since the HUD's lines are its own, not the text's.
var punctuationMarks = {
  "comma": ",",
  "period": ".",
  "full stop": ".",
  "dot": ".",
  "question mark": "?",
  "exclamation mark": "!",
  "exclamation point": "!",
  "colon": ":",
  "semicolon": ";",
  "semi colon": ";",
  "dash": "–",
  "hyphen": "-",
  "new line": "↵",
  "newline": "↵",
  "new paragraph": "¶"
}

function punctuationGlyph(phrase) {
  var key = String(phrase || "").toLowerCase().replace(/[^a-z ]+/g, " ").replace(/\s+/g, " ").trim()
  return punctuationMarks[key] || "·"
}

// Whether a mark sits against the word before it, taking that word's space.
function attaches(glyph) {
  return [",", ".", "?", "!", ":", ";"].indexOf(glyph) !== -1
}

// The draft as the pieces the HUD lays out one at a time: each word with the
// whitespace after it, so a fold takes its space with it. A mark's words
// carry its kind; a send phrase, a spoken punctuation phrase and a
// vocabulary hit with a replacement stay one piece, since each becomes one
// thing, and `glyph` is what it becomes. `trim` marks a piece whose trailing
// space the next piece's mark takes at the finalize ("today comma" lands as
// "today,"). Offsets are UTF-16, as the protocol's are.
//
// Each piece: {text, word, space, start, kind, glyph, chip, trim, group}.
function pieces(text, marks) {
  text = String(text || "")
  var list = normalize(text, marks)
  var out = []

  function push(from, to, kind, group, replacement) {
    var slice = text.substring(from, to)
    if (slice.length === 0) return
    // Whitespace opening a region trails the piece before it.
    var lead = slice.match(/^\s+/)
    if (lead && out.length > 0) {
      out[out.length - 1].text += lead[0]
      out[out.length - 1].space += lead[0]
      slice = slice.substring(lead[0].length)
      from += lead[0].length
    }
    if (slice.length === 0) return
    if (kind === "send" || kind === "punctuation" || (kind === "vocabulary" && replacement)) {
      var body = slice.replace(/\s+$/, "")
      var glyph = kind === "punctuation" ? punctuationGlyph(body) : (kind === "vocabulary" ? replacement : "")
      out.push({
        text: slice, word: body, space: slice.substring(body.length), start: from, kind: kind,
        glyph: glyph, chip: kind === "send", trim: false, group: group
      })
      return
    }
    var pattern = /\s*\S+\s*/g
    var match
    while ((match = pattern.exec(slice)) !== null) {
      var piece = match[0]
      var word = piece.replace(/\s+$/, "")
      out.push({
        text: piece, word: word, space: piece.substring(word.length), start: from + match.index,
        kind: kind, glyph: "", chip: false, trim: false, group: group
      })
    }
  }

  var at = 0
  for (var i = 0; i < list.length; i++) {
    push(at, list[i].start, "", -1)
    push(list[i].start, list[i].end, list[i].kind, i, list[i].replacement || "")
    at = list[i].end
  }
  push(at, text.length, "", -1)

  for (var k = 1; k < out.length; k++) {
    if (out[k].kind === "punctuation" && attaches(out[k].glyph) && out[k - 1].space.length > 0)
      out[k - 1].trim = true
  }
  return out
}

// Whether a piece folds out of the line at the finalize. The send phrase
// stays a chip until the text lands.
function folds(kind) {
  return kind === "filler" || kind === "scratched"
}

// Marks for a Teach message, "heard omachi → Omarchy": what was heard faint,
// what it is written as in the accent, the way the draft draws a filler and
// a vocabulary hit.
function taughtMessage(heard, written) {
  heard = String(heard || "")
  written = String(written || "")
  var text = "heard " + heard + " → " + written
  var marks = []
  if (heard.length) marks.push({ start: 6, end: 6 + heard.length, kind: "filler" })
  if (written.length) marks.push({ start: text.length - written.length, end: text.length, kind: "vocabulary" })
  return { text: text, marks: marks }
}

// An App rule's name as the tag shows it: "terminal" as is, a window class
// by its last part ("org.gnome.Nautilus" is "nautilus"), short enough for a
// shoulder tag.
function ruleLabel(rule) {
  var name = String(rule || "").trim()
  if (!name.length) return ""
  var parts = name.split(".")
  var last = parts[parts.length - 1] || name
  if (last.length > 14) last = last.substring(0, 13) + "…"
  return last.toUpperCase()
}
