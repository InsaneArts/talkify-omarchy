import QtQuick

// A latched session's clock: how long it has been listening hands-free,
// ticking once a second (Handy's elapsed timer). A small solid dot beside it
// says the session is latched, where a held one shows nothing; a paused
// session shows the two bars of a pause there instead.
Row {
  id: label

  property real startedAt: 0
  property bool running: false
  property color color: "white"
  property string fontFamily: ""
  property real pointSize: 12
  property bool paused: false
  property color pausedColor: color

  property int seconds: 0

  spacing: pointSize * 0.4

  function refresh() {
    seconds = startedAt > 0 ? Math.max(0, Math.floor((Date.now() - startedAt) / 1000)) : 0
  }

  Rectangle {
    visible: !label.paused
    anchors.verticalCenter: parent.verticalCenter
    width: label.pointSize * 0.45
    height: width
    radius: width / 2
    color: label.color
  }

  PauseMark {
    visible: label.paused
    anchors.verticalCenter: parent.verticalCenter
    size: label.pointSize * 0.7
    color: label.pausedColor
  }

  Text {
    anchors.verticalCenter: parent.verticalCenter
    text: Math.floor(label.seconds / 60) + ":" + ("0" + (label.seconds % 60)).slice(-2)
    color: label.color
    opacity: 0.8
    font.family: label.fontFamily
    font.pixelSize: Math.max(1, label.pointSize)
    font.weight: Font.Medium
    font.features: { "tnum": 1 }
    renderType: Text.NativeRendering
  }

  Timer {
    interval: 1000
    repeat: true
    running: label.running && label.visible
    triggeredOnStart: true
    onTriggered: label.refresh()
  }
  onStartedAtChanged: refresh()
}
