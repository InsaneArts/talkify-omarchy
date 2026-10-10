import QtQuick
import qs.Commons
import qs.Ui
import "Format.js" as Format

// One app's rules: a header that says what differs from the global settings,
// and, opened, a row per field. Every field starts on Inherit; setting one
// writes apps.<class>.<field>, and Inherit writes "" to clear it, so a rule
// with nothing set disappears from the config by itself.
Column {
  id: rule

  required property var ctx
  // The window class, or "terminal" for every window Omarchy tags as one.
  property string cls: ""
  // The rule as the config holds it, or undefined for none yet.
  property var fields: undefined
  // The terminal rule, for a class known to be a terminal: a field this rule
  // leaves unset falls through to it before the globals.
  property var fallback: undefined
  property bool expanded: false
  signal toggled()

  function current(field) {
    var v = fields ? fields[field] : undefined
    return v === undefined || v === null ? "" : v
  }

  function onOff(flag) { return flag ? "on" : "off" }

  // What each field inherits, said on its Inherit button so "Inherit" is
  // never a mystery.
  function inherited(field) {
    var through = fallback ? fallback[field] : undefined
    if (through !== undefined && through !== null) return "terminal: " + describe(field, through)
    switch (field) {
    case "tidy": return onOff(ctx.value("tidy.enabled", true) === true)
    case "final_period": return "keep"
    case "case": return "sentence"
    case "trailing_space": return onOff(ctx.value("insertion.trailing_space", true) === true)
    case "send": return "never"
    }
    return ""
  }

  function describe(field, value) {
    if (field === "final_period") return value ? "keep" : "drop"
    if (field === "send") return value === "spoken" ? "on a phrase" : value
    if (value === true || value === false) return onOff(value)
    return String(value)
  }

  readonly property var schema: [
    { field: "tidy", label: "Tidy pass", options: [{ value: true, label: "On" }, { value: false, label: "Off" }] },
    { field: "final_period", label: "Final period", options: [{ value: true, label: "Keep" }, { value: false, label: "Drop" }] },
    { field: "case", label: "Case", options: [{ value: "sentence", label: "Sentence" }, { value: "lower", label: "lower" }] },
    { field: "trailing_space", label: "Space after", options: [{ value: true, label: "On" }, { value: false, label: "Off" }] },
    {
      field: "send", label: "Press Enter",
      options: [
        { value: "never", label: "Never" },
        { value: "spoken", label: "On a send phrase", tip: "Only when a send phrase is the last thing said, after a pause" },
        { value: "always", label: "Always" }
      ]
    }
  ]

  readonly property string summary: {
    var parts = []
    var tidy = current("tidy")
    if (tidy !== "") parts.push("Tidy " + onOff(tidy))
    var period = current("final_period")
    if (period !== "") parts.push(period ? "Keeps the final period" : "No final period")
    var letterCase = current("case")
    if (letterCase === "lower") parts.push("lower case")
    else if (letterCase === "sentence") parts.push("Sentence case")
    var space = current("trailing_space")
    if (space !== "") parts.push(space ? "Space after" : "No space after")
    var send = current("send")
    if (send === "spoken") parts.push("Enter on a send phrase")
    else if (send === "always") parts.push("Always presses Enter")
    else if (send === "never") parts.push("Never presses Enter")
    if (parts.length) return parts.join("  ·  ")
    return fallback ? "A terminal: follows the Terminals rule" : "Follows the global settings"
  }

  function setField(field, next) {
    ctx.svc.set("apps." + cls + "." + field, next)
  }

  width: parent ? parent.width : 0
  spacing: 0

  BorderSurface {
    id: header
    width: parent.width
    implicitHeight: headerColumn.implicitHeight + Style.space(18) + borderTop + borderBottom
    radius: Style.cornerRadius
    readonly property bool hot: headerMouse.containsMouse || activeFocus
    color: rule.expanded ? Style.selectedFillFor(rule.ctx.fg, Color.accent)
      : Style.controlFill(activeFocus, headerMouse.containsMouse, rule.ctx.fg, Color.accent)
    borderSpec: Border.controlSpec(activeFocus ? "focus" : (hot ? "hover-cursor" : "normal"), rule.ctx.fg, Color.accent)
    activeFocusOnTab: true
    Keys.onReturnPressed: rule.toggled()
    Keys.onEnterPressed: rule.toggled()
    Keys.onSpacePressed: rule.toggled()

    Column {
      id: headerColumn
      anchors.left: parent.left
      anchors.leftMargin: Style.space(12)
      anchors.right: chevron.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(3)

      Row {
        width: parent.width
        spacing: Style.space(8)

        Text {
          id: name
          textFormat: Text.PlainText
          text: Format.appLabel(rule.cls)
          color: rule.ctx.fg
          font.family: rule.ctx.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Text {
          anchors.baseline: name.baseline
          width: parent.width - name.width - parent.spacing
          elide: Text.ElideRight
          textFormat: Text.PlainText
          text: rule.cls === "terminal" ? "every window Omarchy tags as a terminal" : rule.cls
          visible: text.toLowerCase() !== name.text.toLowerCase()
          color: rule.ctx.fg
          opacity: 0.5
          font.family: rule.ctx.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Text {
        width: parent.width
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: rule.summary
        color: rule.ctx.fg
        opacity: rule.fields ? 0.8 : 0.5
        font.family: rule.ctx.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Text {
      id: chevron
      anchors.right: parent.right
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      text: rule.expanded ? "󰅀" : "󰅂"
      color: rule.ctx.fg
      opacity: 0.7
      font.family: rule.ctx.fontFamily
      font.pixelSize: Style.font.body
    }

    MouseArea {
      id: headerMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: rule.toggled()
    }
  }

  Column {
    visible: rule.expanded
    width: parent.width
    topPadding: Style.space(10)
    bottomPadding: Style.space(6)
    leftPadding: Style.space(12)
    spacing: Style.space(8)

    Repeater {
      model: rule.expanded ? rule.schema : []

      delegate: Item {
        id: fieldRow
        required property var modelData
        readonly property var value: rule.current(modelData.field)
        width: rule.width - Style.space(12)
        implicitHeight: Math.max(fieldLabel.implicitHeight, choices.implicitHeight)

        Text {
          id: fieldLabel
          width: Style.space(118)
          y: Style.space(5)
          textFormat: Text.PlainText
          text: fieldRow.modelData.label
          color: rule.ctx.fg
          opacity: 0.8
          font.family: rule.ctx.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Flow {
          id: choices
          anchors.left: fieldLabel.right
          anchors.right: parent.right
          spacing: Style.space(6)

          Repeater {
            model: [{ value: "", label: "Inherit · " + rule.inherited(fieldRow.modelData.field) }]
              .concat(fieldRow.modelData.options)
            delegate: Button {
              required property var modelData
              text: modelData.label
              tooltipText: modelData.tip || ""
              selected: String(fieldRow.value) === String(modelData.value)
              bordered: true
              focusable: true
              verticalPadding: Style.space(3)
              foreground: rule.ctx.fg
              fontFamily: rule.ctx.fontFamily
              fontSize: Style.font.caption
              onClicked: rule.setField(fieldRow.modelData.field, modelData.value)
            }
          }
        }
      }
    }

    Button {
      visible: !!rule.fields
      text: "Clear this rule"
      tooltipText: "Put every field back on Inherit"
      bordered: true
      focusable: true
      verticalPadding: Style.space(4)
      foreground: rule.ctx.fg
      fontFamily: rule.ctx.fontFamily
      fontSize: Style.font.caption
      onClicked: {
        for (var i = 0; i < rule.schema.length; i++) {
          if (rule.current(rule.schema[i].field) !== "") rule.setField(rule.schema[i].field, "")
        }
      }
    }
  }
}
