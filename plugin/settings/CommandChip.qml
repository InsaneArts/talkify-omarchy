import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// A command to run, click to copy. The commands Talkify asks for (teach,
// pause) belong in a terminal or a Hyprland bind, so the useful thing to
// do with one here is take it.
BorderSurface {
  id: chip

  required property var ctx
  property string command: ""
  property bool copied: false
  readonly property bool hot: mouse.containsMouse || activeFocus

  implicitWidth: row.implicitWidth + Style.space(20) + borderLeft + borderRight
  implicitHeight: row.implicitHeight + Style.space(10) + borderTop + borderBottom
  radius: Style.cornerRadius
  color: hot ? Style.hoverFillFor(ctx.fg, Color.accent) : Style.normalFillFor(ctx.fg, Color.accent)
  borderSpec: Border.controlSpec(hot ? "hover-cursor" : "normal", ctx.fg, Color.accent)
  activeFocusOnTab: true

  function copy() {
    Quickshell.execDetached(["wl-copy", "--", chip.command])
    chip.copied = true
    reset.restart()
  }

  Keys.onReturnPressed: copy()
  Keys.onEnterPressed: copy()
  Keys.onSpacePressed: copy()

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(10)

    Text {
      textFormat: Text.PlainText
      text: chip.command
      color: chip.ctx.fg
      font.family: chip.ctx.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: chip.copied ? "copied" : "copy"
      color: chip.copied ? Color.accent : chip.ctx.fg
      opacity: chip.copied ? 1 : 0.5
      font.family: chip.ctx.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: chip.copy()
  }

  Timer {
    id: reset
    interval: 1400
    onTriggered: chip.copied = false
  }
}
