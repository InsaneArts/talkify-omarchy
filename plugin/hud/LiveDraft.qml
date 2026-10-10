import QtQuick

// A placement's draft or status line. While the words are plain it is
// DraftText, one styled Text, exactly as before; while they carry marks,
// MarkedDraft draws them a word at a time. A session without marks never
// takes the second path.
//
// A paused session's words dim, since nothing heard while paused is kept.
Item {
  id: live

  property string draft: ""
  property string committed: ""
  property bool solid: false
  property var textRgb: [1, 1, 1]
  property var accentRgb: [0.42, 0.64, 1, 1]
  property string longDraft: "grow-down"
  property int lines: 4
  property bool leading: false
  property real hudScale: 1
  property string fontFamily: ""
  // A fixed line height in pixels, as the pill keeps; 0 is the font's own.
  property real lineHeightPx: 0
  property var marks: []
  property real fold: 0
  property bool paused: false

  readonly property bool rich: !!marks && marks.length > 0
  // The words' font, for a parent measuring them.
  readonly property font font: plain.font
  readonly property int lineCount: rich ? marked.lineCount : plain.lineCount

  implicitWidth: rich ? marked.implicitWidth : plain.implicitWidth
  implicitHeight: rich ? marked.implicitHeight : plain.implicitHeight
  opacity: paused ? 0.55 : 1
  Behavior on opacity { NumberAnimation { duration: 200 } }

  DraftText {
    id: plain
    visible: !live.rich
    width: live.width
    textRgb: live.textRgb
    draft: live.rich ? "" : live.draft
    committed: live.committed
    solid: live.solid
    longDraft: live.longDraft
    lines: live.lines
    leading: live.leading
    hudScale: live.hudScale
    fontFamily: live.fontFamily
    lineHeightMode: live.lineHeightPx > 0 ? Text.FixedHeight : Text.ProportionalHeight
    lineHeight: live.lineHeightPx > 0 ? live.lineHeightPx : 1
  }

  MarkedDraft {
    id: marked
    visible: live.rich
    active: live.rich
    width: live.width
    textRgb: live.textRgb
    accentRgb: live.accentRgb
    draft: live.draft
    committed: live.committed
    marks: live.marks
    solid: live.solid
    longDraft: live.longDraft
    lines: live.lines
    leading: live.leading
    hudScale: live.hudScale
    fontFamily: live.fontFamily
    lineHeightPx: live.lineHeightPx
    fold: live.fold
  }
}
