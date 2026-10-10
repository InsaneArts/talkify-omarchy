import QtQuick
import qs.Commons
import qs.Ui

// A captioned row of buttons, one per option. Bound to a config key, or,
// with `key` empty, to `current` and the `picked` signal.
Column {
  id: choice

  required property var ctx
  property string title: ""
  property string key: ""
  property var fallback: ""
  property var options: []
  property var current: key !== "" ? ctx.value(key, fallback) : fallback
  property real fontSize: Style.font.bodySmall
  signal picked(var value)

  width: parent ? parent.width : 0
  spacing: Style.space(8)

  Heading {
    visible: choice.title !== ""
    ctx: choice.ctx
    text: choice.title
  }

  Flow {
    width: parent.width
    spacing: Style.space(6)

    Repeater {
      model: choice.options
      delegate: Button {
        required property var modelData
        text: modelData.label
        tooltipText: modelData.tip || ""
        selected: String(choice.current) === String(modelData.value)
        bordered: true
        focusable: true
        foreground: choice.ctx.fg
        fontFamily: choice.ctx.fontFamily
        fontSize: choice.fontSize
        onClicked: {
          if (choice.key !== "") choice.ctx.set(choice.key, modelData.value)
          choice.picked(modelData.value)
        }
      }
    }
  }
}
