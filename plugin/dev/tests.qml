import QtQuick
import Quickshell
import "hud/HudMarks.js" as Marks

// The HUD's pure helpers pinned without a window: the pieces a marked Live
// draft is drawn in (HudMarks.js). Run in the same JavaScript engine the HUD
// uses:
//
//   quickshell -p plugin/dev/tests.qml
//
// It prints each failure and ends with a summary line, "tests: N passed" or
// "tests: N failed".
ShellRoot {
  id: root

  property int passed: 0
  property int failed: 0

  function check(name, actual, expected) {
    var a = JSON.stringify(actual)
    var e = JSON.stringify(expected)
    if (a === e) {
      passed += 1
    } else {
      failed += 1
      console.log("FAIL " + name + "\n  expected " + e + "\n  actual   " + a)
    }
  }

  function kinds(pieces) {
    return pieces.map(function (p) { return (p.kind || "plain") + ":" + p.word + (p.trim ? "|trim" : "") + (p.glyph ? "|" + p.glyph : "") })
  }

  function marksTests() {
    var text = "So um we ship it today scratch that tomorrow comma then go send it"
    // "um" 3–5, "today scratch that" 17–35, "comma" 45–50, "send it" 59–66.
    var marks = [
      { start: 3, end: 5, kind: "filler" },
      { start: 17, end: 35, kind: "scratched" },
      { start: 45, end: 50, kind: "punctuation" },
      { start: 59, end: 66, kind: "send" }
    ]
    check("pieces", kinds(Marks.pieces(text, marks)), [
      "plain:So", "filler:um", "plain:we", "plain:ship", "plain:it", "scratched:today", "scratched:scratch",
      "scratched:that", "plain:tomorrow|trim", "punctuation:comma|,", "plain:then", "plain:go", "send:send it"
    ])
    check("pieces keep their whitespace", Marks.pieces(text, marks).map(function (p) { return p.text }).join(""), text)
    check("pieces carry UTF-16 starts", Marks.pieces(text, marks).map(function (p) { return p.start }),
      [0, 3, 6, 9, 14, 17, 23, 31, 36, 45, 51, 56, 59])

    check("unknown kinds and empty marks are dropped",
      Marks.normalize("hello", [{ start: 0, end: 5, kind: "shout" }, { start: 2, end: 2, kind: "filler" }]), [])
    check("marks are clamped to the text",
      Marks.normalize("hello", [{ start: 3, end: 40, kind: "filler" }]), [{ start: 3, end: 5, kind: "filler" }])
    check("overlaps keep the earlier mark",
      Marks.normalize("one two three", [{ start: 4, end: 13, kind: "scratched" }, { start: 0, end: 7, kind: "filler" }]),
      [{ start: 0, end: 7, kind: "filler" }])
    check("unsorted marks are sorted",
      Marks.normalize("a b c", [{ start: 4, end: 5, kind: "filler" }, { start: 0, end: 1, kind: "filler" }]).map(function (m) { return m.start }),
      [0, 4])
    check("a mark inside a word splits it", kinds(Marks.pieces("Um, so", [{ start: 0, end: 2, kind: "filler" }])),
      ["filler:Um", "plain:,", "plain:so"])
    check("no marks", kinds(Marks.pieces("just words", [])), ["plain:just", "plain:words"])
    check("emoji offsets are UTF-16", kinds(Marks.pieces("ok 👍 um yes", [{ start: 6, end: 8, kind: "filler" }])),
      ["plain:ok", "plain:👍", "filler:um", "plain:yes"])
    check("a line break stays its own word",
      kinds(Marks.pieces("first new line second", [{ start: 6, end: 14, kind: "punctuation" }])),
      ["plain:first", "punctuation:new line|↵", "plain:second"])

    check("glyphs", ["Comma", "question mark", "full stop", "new paragraph", "kazoo"].map(Marks.punctuationGlyph),
      [",", "?", ".", "¶", "·"])
    var vocab = "ship the omachi port"
    var hit = [{ start: 9, end: 15, kind: "vocabulary", replacement: "Omarchy" }]
    check("a vocabulary hit with its replacement is one piece", kinds(Marks.pieces(vocab, hit)),
      ["plain:ship", "plain:the", "vocabulary:omachi|Omarchy", "plain:port"])
    check("normalize keeps a vocabulary replacement", Marks.normalize(vocab, hit), hit)
    check("a replacement on another kind is dropped",
      Marks.normalize("um ok", [{ start: 0, end: 2, kind: "filler", replacement: "x" }]), [{ start: 0, end: 2, kind: "filler" }])
    check("a two-word hit stays whole", kinds(Marks.pieces("hyper land rocks", [{ start: 0, end: 10, kind: "vocabulary", replacement: "Hyprland" }])),
      ["vocabulary:hyper land|Hyprland", "plain:rocks"])
    check("a hit without a replacement keeps its words",
      kinds(Marks.pieces("the Omarchy port", [{ start: 4, end: 11, kind: "vocabulary" }])), ["plain:the", "vocabulary:Omarchy", "plain:port"])

    check("taught message", Marks.taughtMessage("omachi", "Omarchy"), {
      text: "heard omachi → Omarchy",
      marks: [{ start: 6, end: 12, kind: "filler" }, { start: 15, end: 22, kind: "vocabulary" }]
    })
    check("rule labels", ["terminal", "org.gnome.Nautilus", "com.mitchellh.ghostty", "", "averyveryverylongclassname"].map(Marks.ruleLabel),
      ["TERMINAL", "NAUTILUS", "GHOSTTY", "", "AVERYVERYVERY…"])
  }

  Component.onCompleted: {
    marksTests()
    console.log(failed > 0 ? "tests: " + failed + " failed, " + passed + " passed" : "tests: " + passed + " passed")
    // Quickshell connects nothing to Qt.quit() and takes no exit code from
    // QML, so the run ends itself and the summary line is the verdict.
    Quickshell.execDetached(["pkill", "-f", "^(qs|quickshell) (-p|--path) \\S*dev/tests.qml"])
  }
}
