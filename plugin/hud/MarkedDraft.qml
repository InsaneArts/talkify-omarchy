import QtQuick
import "HudMarks.js" as Marks
import "HudText.js" as HudText

// The Live draft drawn a word at a time, for what one styled Text cannot
// show: the marks over it (HudMarks.js).
//
// - A filler is faint and a scratched phrase struck through; at the finalize
//   both fold out of the line, narrowing and fading as the sweep passes, so
//   the user sees what the Tidy pass removed.
// - Spoken punctuation is the word over an accent underline, which turns
//   into the mark at the finalize and takes the space before it.
// - A vocabulary hit is in the accent for a moment when it appears, and
//   once more at the finalize, as it turns into what the vocabulary writes
//   ("omachi" becomes "Omarchy").
// - The send phrase is a ⏎ chip.
//
// It wraps as DraftText does, except that at the line cap it keeps the
// newest lines, not the oldest; Tail Only and Shrink to Fit keep one line
// whose head runs off the leading edge.
Item {
  id: root

  property string draft: ""
  property string committed: ""
  property var marks: []
  // One tone: no committed prefix to set apart.
  property bool solid: false
  property var textRgb: [1, 1, 1]
  property var accentRgb: [0.42, 0.64, 1, 1]
  property string longDraft: "grow-down"
  property int lines: 4
  property bool leading: false
  property real hudScale: 1
  property real pointSize: 15 * hudScale
  property string fontFamily: ""
  // The pill's fixed line height; 0 is the font's own.
  property real lineHeightPx: 0
  // The finalize's fold, 0 to 1 (HudStage).
  property real fold: 0
  // Off while DraftText draws the words instead, so nothing is laid out.
  property bool active: true

  readonly property bool wraps: longDraft === "grow-down"
  readonly property real lineStep: lineHeightPx > 0 ? lineHeightPx : Math.ceil(metrics.height)
  // Shrink to Fit's type size, as a share of the full one.
  property real fontScale: 1
  property int lineCount: 0
  property real contentWidth: 0
  property var geometry: []
  // Whether a vocabulary hit is still in its moment, which keeps the layout
  // ticking.
  property bool flashing: false
  // When each vocabulary hit was first drawn, by its place and word.
  property var seen: ({})

  readonly property real fillerAlpha: 0.42
  readonly property real flashSeconds: 1.6

  implicitWidth: contentWidth
  implicitHeight: Math.max(1, Math.min(lineCount, wraps ? lines : 1)) * lineStep
  clip: !wraps

  FontMetrics {
    id: metrics
    font.family: root.fontFamily
    font.pixelSize: Math.max(1, root.pointSize)
    font.weight: Font.Medium
  }

  ListModel {
    id: tokens
  }

  property var widthCache: ({})
  function measure(text) {
    if (!text) return 0
    var cached = widthCache[text]
    if (cached === undefined) {
      cached = metrics.advanceWidth(text)
      widthCache[text] = cached
    }
    return cached
  }

  readonly property real chipWidth: Math.round(pointSize * 1.45)

  function clamp01(x) {
    return Math.max(0, Math.min(1, x))
  }
  function ease(t) {
    return t * t * (3 - 2 * t)
  }

  function syncModel(list) {
    for (var i = 0; i < list.length; i++) {
      var row = { word: list[i].word, kind: list[i].kind || "", glyph: list[i].glyph || "", chip: !!list[i].chip }
      if (i < tokens.count) {
        var old = tokens.get(i)
        if (old.word !== row.word || old.kind !== row.kind || old.glyph !== row.glyph || old.chip !== row.chip)
          tokens.set(i, row)
      } else {
        tokens.append(row)
      }
    }
    if (tokens.count > list.length) tokens.remove(list.length, tokens.count - list.length)
  }

  function schedule() {
    if (active) Qt.callLater(relayout)
  }

  function relayout() {
    if (!active) return
    var list = Marks.pieces(draft, marks)
    syncModel(list)

    var cut = HudText.committedLength(draft, committed)
    var n = list.length
    var now = Date.now() / 1000
    var stillFlashing = false
    var nextSeen = {}
    var pieces = []

    for (var i = 0; i < n; i++) {
      var p = list[i]
      var word = p.chip ? chipWidth : measure(p.word)
      var space = measure(p.space)
      var alpha = solid || p.start < cut ? 1 : HudText.pendingAlpha
      var g = { word: word, space: space, spaceScale: 1, squash: 1, alpha: alpha, textAlpha: 1, morph: 0, accent: 0, glyphSquash: 1 }
      // The fold runs left to right, as the sweep does.
      var local = clamp01(fold * 1.7 - 0.7 * (n > 1 ? i / (n - 1) : 0))

      switch (p.kind) {
      case "filler":
        g.textAlpha = Math.min(alpha, fillerAlpha) * (1 - clamp01(local * 1.7))
        g.squash = 1 - ease(local)
        g.spaceScale = g.squash
        break
      case "scratched":
        g.textAlpha = Math.min(alpha, 0.6) * (1 - clamp01(local * 1.7))
        g.squash = 1 - ease(local)
        g.spaceScale = g.squash
        break
      case "punctuation":
        // The word narrows into the mark's width as the mark fades in.
        g.morph = ease(local)
        var glyphWidth = measure(p.glyph)
        g.word = word + (glyphWidth - word) * g.morph
        g.squash = word > 0 ? g.word / word : 1
        if (i > 0 && list[i - 1].trim) pieces[i - 1].spaceScale *= 1 - g.morph
        break
      case "vocabulary":
        var key = p.start + ":" + p.word
        var first = seen[key] !== undefined ? seen[key] : now
        nextSeen[key] = first
        var age = (now - first) / flashSeconds
        if (age < 1) stillFlashing = true
        g.accent = Math.max(age < 1 ? 1 - ease(clamp01(age)) : 0, Math.sin(Math.PI * local))
        if (p.glyph) {
          // The heard word gives way to the written one, each squeezed to
          // the width between them so neither overflows its neighbours.
          g.morph = ease(local)
          var written = measure(p.glyph)
          g.word = word + (written - word) * g.morph
          g.squash = word > 0 ? g.word / word : 1
          g.glyphSquash = written > 0 ? g.word / written : 1
        }
        break
      }
      if (p.kind !== "filler" && p.kind !== "scratched") g.textAlpha = alpha
      pieces.push(g)
    }
    seen = nextSeen
    flashing = stillFlashing

    // Shrink to Fit: the type comes down to 55% before the head runs off.
    var total = 0
    for (i = 0; i < n; i++) {
      var piece = pieces[i]
      total += (piece.morph > 0 ? piece.word : piece.word * piece.squash) + piece.space * piece.spaceScale
    }
    var k = longDraft === "shrink-to-fit" && total > width && total > 0 ? Math.max(0.55, width / total) : 1
    fontScale = k

    var placed = []
    var lineOf = []
    var lineWidths = [0]
    var line = 0
    var x = 0
    for (i = 0; i < n; i++) {
      var q = pieces[i]
      var w = (q.morph > 0 ? q.word : q.word * q.squash) * k
      var gap = q.space * q.spaceScale * k
      if (wraps && x > 0 && x + w > width + 0.5 && w > 0.5) {
        line += 1
        x = 0
        lineWidths.push(0)
      }
      placed.push({ x: x, line: line, w: w })
      lineOf.push(line)
      if (w > 0) lineWidths[line] = x + w
      x += w + gap
    }
    var count = wraps ? line + 1 : 1
    if (n === 0) count = 0

    var first = wraps && count > lines ? count - lines : 0
    var widest = 0
    for (var l = first; l < lineWidths.length; l++) widest = Math.max(widest, lineWidths[l])

    var out = []
    for (i = 0; i < n; i++) {
      var r = pieces[i]
      var at = placed[i]
      var lineWidth = lineWidths[at.line]
      var offset
      if (!wraps && lineWidth > width) offset = width - lineWidth
      else offset = leading ? 0 : (width - lineWidth) / 2
      out.push({
        x: at.x + offset,
        y: (at.line - first) * lineStep,
        w: at.w,
        squash: r.squash,
        alpha: at.line < first ? 0 : r.alpha,
        textAlpha: r.textAlpha,
        morph: r.morph,
        accent: r.accent,
        glyphSquash: r.glyphSquash
      })
    }
    lineCount = count
    contentWidth = Math.min(Math.max(widest, 0), wraps ? width : widest)
    geometry = out
  }

  onDraftChanged: schedule()
  onCommittedChanged: schedule()
  onMarksChanged: schedule()
  onFoldChanged: schedule()
  onSolidChanged: schedule()
  onWidthChanged: schedule()
  onLinesChanged: schedule()
  onLongDraftChanged: schedule()
  onLeadingChanged: schedule()
  onActiveChanged: schedule()
  onPointSizeChanged: {
    widthCache = {}
    schedule()
  }
  onFontFamilyChanged: {
    widthCache = {}
    schedule()
  }
  Component.onCompleted: schedule()

  // Only while a vocabulary hit is in its moment.
  FrameAnimation {
    running: root.flashing && root.active && root.visible
    onTriggered: root.relayout()
  }

  Repeater {
    model: tokens

    Item {
      id: piece

      required property int index
      required property string word
      required property string kind
      required property string glyph
      required property bool chip

      readonly property var g: index < root.geometry.length ? root.geometry[index] : null
      readonly property real accent: g ? g.accent : 0
      readonly property var rgb: [
        root.textRgb[0] + (root.accentRgb[0] - root.textRgb[0]) * accent,
        root.textRgb[1] + (root.accentRgb[1] - root.textRgb[1]) * accent,
        root.textRgb[2] + (root.accentRgb[2] - root.textRgb[2]) * accent
      ]

      visible: !!g && g.alpha > 0.003 && g.w > 0.3
      x: g ? g.x : 0
      y: g ? g.y : 0
      width: g ? g.w : 0
      height: root.lineStep
      opacity: g ? g.alpha : 0

      Text {
        id: label
        visible: !piece.chip && (!piece.g || piece.g.morph < 0.999)
        text: piece.word
        color: Qt.rgba(piece.rgb[0], piece.rgb[1], piece.rgb[2], piece.g ? piece.g.textAlpha : 1)
        opacity: piece.g ? 1 - piece.g.morph : 1
        font.family: root.fontFamily
        font.pixelSize: Math.max(1, root.pointSize * root.fontScale)
        font.weight: Font.Medium
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
        wrapMode: Text.NoWrap
        transform: Scale { xScale: piece.g ? Math.max(0.001, piece.g.squash) : 1 }
      }

      // A scratched phrase's strike, through the middle of the lowercase.
      Rectangle {
        visible: piece.kind === "scratched"
        y: label.y + (metrics.ascent - metrics.xHeight * 0.5) * root.fontScale
        width: label.implicitWidth * (piece.g ? piece.g.squash : 1)
        height: Math.max(1, 1.3 * root.hudScale)
        radius: height / 2
        color: Qt.rgba(root.textRgb[0], root.textRgb[1], root.textRgb[2], piece.g ? Math.min(0.85, piece.g.textAlpha + 0.2) : 0.8)
      }

      // Spoken punctuation's underline, which narrows into the mark.
      Rectangle {
        visible: piece.kind === "punctuation" && !!piece.g && piece.g.morph < 0.999
        y: label.y + (metrics.ascent + 3 * root.hudScale) * root.fontScale
        width: label.implicitWidth * (piece.g ? piece.g.squash * (1 - piece.g.morph) : 1)
        height: Math.max(1, 1.6 * root.hudScale)
        radius: height / 2
        color: Qt.rgba(root.accentRgb[0], root.accentRgb[1], root.accentRgb[2], 0.8)
      }

      // What the piece becomes: spoken punctuation's mark, or the word the
      // vocabulary writes, in the colour of the moment.
      Text {
        visible: (piece.kind === "punctuation" || piece.kind === "vocabulary") && piece.glyph !== ""
          && !!piece.g && piece.g.morph > 0.001
        text: piece.glyph
        color: piece.kind === "vocabulary"
          ? Qt.rgba(piece.rgb[0], piece.rgb[1], piece.rgb[2], 1)
          : Qt.rgba(root.textRgb[0], root.textRgb[1], root.textRgb[2], piece.g ? piece.g.textAlpha : 1)
        opacity: piece.g ? piece.g.morph : 0
        font: label.font
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
        transform: Scale { xScale: piece.g ? Math.max(0.001, Math.min(1, piece.g.glyphSquash)) : 1 }
      }

      // The send phrase: a ⏎ chip in the line.
      Rectangle {
        visible: piece.chip
        y: label.y + Math.round((metrics.height * root.fontScale - height) / 2)
        width: Math.max(1, piece.width - 2 * root.hudScale)
        height: Math.round(metrics.height * root.fontScale * 0.82)
        radius: 4 * root.hudScale
        color: Qt.rgba(root.accentRgb[0], root.accentRgb[1], root.accentRgb[2], 0.16)
        border.width: 1
        border.color: Qt.rgba(root.accentRgb[0], root.accentRgb[1], root.accentRgb[2], 0.6)

        ReturnGlyph {
          anchors.centerIn: parent
          width: parent.height * 0.62
          height: parent.height * 0.5
          stroke: Math.max(1.1, 1.3 * root.hudScale)
          color: Qt.rgba(root.accentRgb[0], root.accentRgb[1], root.accentRgb[2], 1)
        }
      }
    }
  }
}
