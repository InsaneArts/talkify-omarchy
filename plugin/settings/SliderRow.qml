import QtQuick
import qs.Commons
import qs.Ui

// A captioned slider bound to one config key, saved on release.
Column {
  id: row

  required property var ctx
  property string title: ""
  property string key: ""
  property string description: ""
  property real minimum: 0
  property real maximum: 10
  property real step: 1
  property real fallback: 0
  property string suffix: ""
  // Stored 0–1, shown and dragged as a percentage.
  property bool percent: false
  readonly property real liveValue: slider.liveValue
  // How the number beside the title reads; a caller binds its own from
  // `liveValue`.
  property string display: Math.round(liveValue) + suffix

  width: parent ? parent.width : 0
  spacing: Style.space(8)

  Item {
    width: parent.width
    implicitHeight: header.implicitHeight

    Heading {
      id: header
      ctx: row.ctx
      text: row.title
    }

    Text {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: row.display
      color: row.ctx.fg
      font.family: row.ctx.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }
  }

  PanelSlider {
    id: slider
    width: parent.width
    bar: row.ctx.bar
    minimum: row.minimum
    maximum: row.maximum
    step: row.step
    integer: true
    value: Number(row.ctx.value(row.key, row.fallback)) * (row.percent ? 100 : 1)
    onReleased: function(value) {
      var stored = Math.round(value)
      row.ctx.set(row.key, row.percent ? stored / 100 : stored)
    }

    // The wheel scrolls the page: a slider that took it would change a
    // setting under a pointer that only meant to scroll past.
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.NoButton
      onWheel: function(wheel) { row.ctx.scrollBy(wheel.angleDelta.y) }
    }
  }

  Caption {
    visible: row.description !== ""
    ctx: row.ctx
    text: row.description
    strength: 0.6
  }
}
