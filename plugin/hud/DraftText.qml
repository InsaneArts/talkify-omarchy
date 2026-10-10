import QtQuick
import "HudText.js" as HudText

// The live draft or a status line, with the long-draft behavior picked in
// settings (HUDLongDraftStyle):
// - grow-down wraps and lets the shape grow with it, capped at four lines;
// - tail-only keeps one line and truncates the head, because the newest
//   words are what the speaker checks;
// - shrink-to-fit keeps one line whose type shrinks down to 55% before the
//   head truncates.
// Grow-down cannot truncate the head: Qt, like SwiftUI, only elides the head
// of a single line, so at the cap it loses the tail.
//
// The committed prefix (already inserted) is solid and the rest of the draft
// at half strength; a status line is solid throughout.
Text {
  id: label

  property string draft: ""
  property string committed: ""
  property bool solid: false

  // The text colour, as [r, g, b]: Talkify's white or the theme's foreground.
  property var textRgb: [1, 1, 1]
  property string longDraft: "grow-down"
  // The line cap for Grow Down; Talkify's notch allows four.
  property int lines: 4
  property bool leading: false
  property real hudScale: 1
  property string fontFamily: ""

  readonly property real pointSize: 15 * hudScale
  readonly property bool grows: longDraft === "grow-down"

  color: Qt.rgba(textRgb[0], textRgb[1], textRgb[2], 1)
  font.family: fontFamily
  font.pixelSize: Math.max(1, pointSize)
  font.weight: Font.Medium
  horizontalAlignment: leading ? Text.AlignLeft : Text.AlignHCenter
  wrapMode: grows ? Text.Wrap : Text.NoWrap
  maximumLineCount: grows ? lines : 1
  elide: grows ? Text.ElideRight : Text.ElideLeft
  fontSizeMode: longDraft === "shrink-to-fit" ? Text.HorizontalFit : Text.FixedSize
  minimumPixelSize: Math.max(1, Math.round(pointSize * 0.55))
  text: HudText.styled(draft, committed, solid, textRgb)
  textFormat: Text.StyledText
  renderType: Text.NativeRendering
}
