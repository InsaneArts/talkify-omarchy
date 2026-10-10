import QtQuick
import qs.Commons
import qs.Ui

// A quiet surface that groups a few lines, drawn with the kit's resting
// control fill and border so it reads like the toggles around it.
BorderSurface {
  id: card

  required property var ctx
  default property alias content: column.data
  property alias spacing: column.spacing
  property real inset: Style.space(12)
  property bool highlighted: false

  width: parent ? parent.width : 0
  implicitHeight: column.implicitHeight + inset * 2 + borderTop + borderBottom
  radius: Style.cornerRadius
  color: highlighted ? Style.selectedFillFor(ctx.fg, Color.accent) : Style.normalFillFor(ctx.fg, Color.accent)
  borderSpec: Border.controlSpec(highlighted ? "selected" : "normal", ctx.fg, Color.accent)

  Column {
    id: column
    x: card.borderLeft + card.inset
    y: card.borderTop + card.inset
    width: card.width - card.inset * 2 - card.borderLeft - card.borderRight
    spacing: Style.space(8)
  }
}
