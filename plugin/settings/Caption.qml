import QtQuick
import qs.Commons

// A sentence that explains the control beside it: wrapped, smaller, dimmer.
Text {
  required property var ctx
  property real strength: 0.7

  width: parent ? parent.width : implicitWidth
  wrapMode: Text.Wrap
  textFormat: Text.PlainText
  color: ctx.fg
  opacity: strength
  font.family: ctx.fontFamily
  font.pixelSize: Style.font.caption
  // What is shown is what to type: a coding font's ligatures would draw
  // "->" as an arrow nobody can type.
  font.features: { "calt": 0, "liga": 0 }
  lineHeight: 1.1
}
