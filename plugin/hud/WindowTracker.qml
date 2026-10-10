import QtQuick
import Quickshell.Hyprland

// The window a session started in, for the placements that hang off it. It
// is read at the session's start and then a few times a second, so a
// floating window that moves takes its caption or halo with it. Rectangles
// are in Hyprland's layout coordinates.
Item {
  id: tracker

  property bool running: false
  property var toplevel: null
  property bool valid: false
  // Whether the first read has come back (or given up), so a placement that
  // needs the window can decide before it reveals.
  property bool settled: true
  property rect rect: Qt.rect(0, 0, 0, 0)
  property bool fullscreen: false

  function capture() {
    toplevel = Hyprland.activeToplevel
    valid = false
    settled = false
    if (toplevel !== null) read()
    Hyprland.refreshToplevels()
    settleTimer.restart()
  }

  // Quickshell learns the active window from focus events, so right after
  // the shell starts it may not know one yet; the window Hyprland focused
  // last is the one with focus history 0.
  function pickFocused() {
    var list = Hyprland.toplevels.values
    for (var i = 0; i < list.length; i++) {
      var o = list[i].lastIpcObject
      if (o && o.focusHistoryID === 0) {
        toplevel = list[i]
        read()
        return
      }
    }
  }

  function read() {
    var o = toplevel ? toplevel.lastIpcObject : null
    if (!o || !o.at || !o.size || o.size[0] <= 0) return
    rect = Qt.rect(o.at[0], o.at[1], o.size[0], o.size[1])
    fullscreen = (Number(o.fullscreen) || 0) > 0
    valid = true
    settled = true
  }

  Connections {
    target: tracker.toplevel
    ignoreUnknownSignals: true
    function onLastIpcObjectChanged() { tracker.read() }
  }

  // The first refresh is a socket round trip; past this, decide without it.
  Timer {
    id: settleTimer
    interval: 160
    onTriggered: {
      if (tracker.toplevel === null) tracker.pickFocused()
      tracker.settled = true
    }
  }

  Timer {
    interval: 250
    repeat: true
    running: tracker.running && tracker.toplevel !== null
    onTriggered: Hyprland.refreshToplevels()
  }
}
