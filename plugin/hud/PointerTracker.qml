import QtQuick
import Quickshell.Io
import Quickshell.Hyprland

// The mouse pointer, for the pointer placement. Hyprland answers
// `j/cursorpos` on its request socket and closes the connection, so each
// read is one short exchange on the socket — no hyprctl process spawned 30
// times a second. Coordinates are Hyprland's layout coordinates.
Item {
  id: tracker

  property bool running: false
  property real pointerX: 0
  property real pointerY: 0
  property bool valid: false

  function request() {
    if (!socket.connected) socket.connected = true
  }

  Socket {
    id: socket
    path: Hyprland.requestSocketPath
    onConnectedChanged: {
      if (connected) {
        write("j/cursorpos")
        flush()
      }
    }
    parser: SplitParser {
      splitMarker: "}"
      onRead: function (data) {
        var x = /"x"\s*:\s*(-?\d+(?:\.\d+)?)/.exec(data)
        var y = /"y"\s*:\s*(-?\d+(?:\.\d+)?)/.exec(data)
        if (!x || !y) return
        tracker.valid = true
        tracker.pointerX = Number(x[1])
        tracker.pointerY = Number(y[1])
        // Hang up first: Hyprland closes after answering, and a peer close
        // is logged as a socket error, thirty times a second.
        socket.connected = false
      }
    }
  }

  Timer {
    interval: 33
    repeat: true
    running: tracker.running
    triggeredOnStart: true
    onTriggered: tracker.request()
  }
}
