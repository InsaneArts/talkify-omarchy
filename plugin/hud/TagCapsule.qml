import QtQuick

// A shoulder tag in the shape (DictationHUDShellView's tag capsule): small
// caps on a faint capsule, out of the draft's way. Talkify uses it to name
// the live language; here it also says when a session is latched, since a
// hands-free session otherwise looks like a held one, and which App rules
// are in force.
Item {
  id: tag

  property string text: ""
  property real hudScale: 1
  property string fontFamily: ""
  property var textRgb: [1, 1, 1]
  // "pause" draws a paused session's two bars before the text.
  property string glyph: ""

  readonly property real glyphRoom: glyph === "pause" ? 9 : 0
  // The tag's text width, measured, capped so a long label truncates rather
  // than pushing the draft off the shape. Unscaled, like Talkify's.
  readonly property real textWidth: Math.min(Math.ceil(metrics.advanceWidth / Math.max(hudScale, 0.01)) + 0.5 * text.length, 150)
  // The room the tag needs on each side of a centered draft: its capsule
  // padding, its inset from the shape's edge, and air before the draft.
  readonly property real reserve: text.length > 0 ? textWidth + glyphRoom + 4 * 2 + 12 + 8 : 0

  implicitWidth: (textWidth + glyphRoom + 8) * hudScale
  implicitHeight: label.implicitHeight + 3 * hudScale
  visible: text.length > 0

  TextMetrics {
    id: metrics
    font: label.font
    text: tag.text
  }

  Rectangle {
    anchors.fill: parent
    radius: height / 2
    color: Qt.rgba(tag.textRgb[0], tag.textRgb[1], tag.textRgb[2], 0.13)
  }

  PauseMark {
    visible: tag.glyph === "pause"
    x: 5 * tag.hudScale
    anchors.verticalCenter: parent.verticalCenter
    size: 6 * tag.hudScale
    color: Qt.rgba(tag.textRgb[0], tag.textRgb[1], tag.textRgb[2], 0.72)
  }

  Text {
    id: label
    x: (4 + tag.glyphRoom) * tag.hudScale
    anchors.verticalCenter: parent.verticalCenter
    width: tag.textWidth * tag.hudScale
    horizontalAlignment: Text.AlignHCenter
    text: tag.text
    color: Qt.rgba(tag.textRgb[0], tag.textRgb[1], tag.textRgb[2], 0.72)
    font.family: tag.fontFamily
    font.pixelSize: Math.max(1, 9 * tag.hudScale)
    font.weight: Font.DemiBold
    font.letterSpacing: 0.5 * tag.hudScale
    elide: Text.ElideRight
    maximumLineCount: 1
    renderType: Text.NativeRendering
  }
}
