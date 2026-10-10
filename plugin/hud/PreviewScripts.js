.pragma library

// The sessions the previews play to show what the HUD does with the daemon's
// newer fields (docs/protocol.md): a tidied draft sent to a terminal, a
// pause, a replay and a Teach.
// Shared by PreviewSession's loop (the Settings previews) and the dev
// harness's captures, so both show the same words.

// The marks over `text` for `spec`, a list of [phrase, kind, replacement]
// in the order they are spoken: each phrase's first whole occurrence after
// the last one. A phrase not fully spoken yet has no mark, as the daemon
// marks only what it has heard.
function marksFor(text, spec) {
  var out = []
  var from = 0
  for (var i = 0; i < spec.length; i++) {
    var at = text.indexOf(spec[i][0], from)
    if (at < 0) continue
    var mark = { start: at, end: at + spec[i][0].length, kind: spec[i][1] }
    if (spec[i][2]) mark.replacement = spec[i][2]
    out.push(mark)
    from = at + spec[i][0].length
  }
  return out
}

// The first `count` words of `sentence`, with their marks.
function draft(sentence, spec, count) {
  var text = sentence.split(" ").slice(0, count).join(" ")
  return { text: text, marks: spec ? marksFor(text, spec) : [] }
}

var tidy = {
  sentence: "Um so we should ship the omachi port today scratch that tomorrow comma then polish the reveal send it",
  spec: [["Um", "filler"], ["omachi", "vocabulary", "Omarchy"], ["today scratch that", "scratched"], ["comma", "punctuation"], ["send it", "send"]],
  rule: "terminal",
  result: {
    text: "So we should ship the Omarchy port tomorrow, then polish the reveal",
    raw: "Um so we should ship the omachi port today scratch that tomorrow comma then polish the reveal send it",
    sent: true
  }
}

var paused = {
  sentence: "first the notes for the standup then the release checklist",
  // Words spoken before the pause; the rest come after it.
  before: 5
}

var replay = "So we should ship the Omarchy port tomorrow, then polish the reveal"

var taught = { heard: "omachi", written: "Omarchy" }
