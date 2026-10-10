import QtQuick
import qs.Commons

// A boxed note: urgent for something that is wrong now, quiet otherwise.
Rectangle {
  id: callout

  required property var ctx
  property string text: ""
  property bool urgent: false

  width: parent ? parent.width : 0
  implicitHeight: body.implicitHeight + Style.space(20)
  radius: Style.cornerRadius
  color: "transparent"
  border.width: 1
  border.color: urgent ? Color.urgent : Qt.rgba(ctx.fg.r, ctx.fg.g, ctx.fg.b, 0.25)

  Text {
    id: body
    anchors.fill: parent
    anchors.margins: Style.space(10)
    wrapMode: Text.Wrap
    textFormat: Text.PlainText
    text: callout.text
    color: callout.ctx.fg
    font.family: callout.ctx.fontFamily
    font.pixelSize: Style.font.caption
  }
}
