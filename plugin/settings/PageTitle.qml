import QtQuick
import qs.Commons

Text {
  required property var ctx

  textFormat: Text.PlainText
  color: ctx.fg
  font.family: ctx.fontFamily
  font.pixelSize: Style.font.subtitle
  font.bold: true
}
