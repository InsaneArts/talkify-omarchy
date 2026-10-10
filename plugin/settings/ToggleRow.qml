import QtQuick
import qs.Ui

// A switch bound to one config key.
Toggle {
  required property var ctx
  property string key: ""
  // What the daemon defaults to, for a config that does not carry the key
  // yet (an older daemon).
  property bool fallback: false

  width: parent ? parent.width : 0
  checked: ctx.value(key, fallback) === true
  foreground: ctx.fg
  fontFamily: ctx.fontFamily
  onClicked: ctx.set(key, !checked)
}
