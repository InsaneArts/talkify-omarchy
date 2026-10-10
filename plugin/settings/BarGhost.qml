import QtQuick
import qs.Commons
import ".."

// The bar's ghost with its three small reactions: a hop and a few sparkles
// for a milestone, a rewind blink when a past dictation is pasted again, and
// a nod when Teach learns a word. Each plays once when asked and ends still;
// nothing here runs on its own. It sits beside the Settings pages because it
// is the menu's own mark, and so the settings harness can play it.
Item {
  id: root

  property color color: Color.foreground
  // 0–1: how much of the ghost is solid, from the bottom (the download).
  property real fill: 1
  // Pixels up, following the voice while recording.
  property real rise: 0
  property real baseOpacity: 1
  property var sparkColors: [Color.accent]

  // What the reactions move; all at rest when nothing plays.
  property real hop: 0
  property real squash: 1
  property real shift: 0
  property real blink: 1
  property real sparkle: 0

  readonly property bool playing: celebration.running || rewinding.running || nodding.running

  function celebrate() {
    rewinding.stop()
    nodding.stop()
    celebration.restart()
  }
  function rewind() { if (!celebration.running) rewinding.restart() }
  function nod() { if (!celebration.running) nodding.restart() }

  // Five sparks leaving the ghost's head in the theme's colours. Drawn
  // behind it, so they emerge from the silhouette, and kept low and wide:
  // the bar is not much taller than the ghost.
  Repeater {
    model: [-2.75, -2.1, -1.57, -1.04, -0.39]

    delegate: Item {
      id: spark
      required property real modelData
      required property int index
      readonly property real reach: root.height * (0.55 + 0.45 * Math.abs(Math.cos(modelData)))
      readonly property real progress: Math.max(0, Math.min(1, root.sparkle * 1.12 - (index % 2) * 0.06))
      readonly property real distance: root.height * 0.3 + reach * progress
      visible: root.sparkle > 0 && root.sparkle < 1
      width: Math.max(3, root.height * 0.28)
      height: width
      x: root.width / 2 - width / 2 + Math.cos(modelData) * distance
      y: root.height * 0.42 - height / 2 + Math.sin(modelData) * distance * 0.75 - root.hop
      opacity: progress < 0.15 ? progress / 0.15 : 1 - (progress - 0.15) / 0.85
      rotation: 90 * progress
      scale: 1 - 0.45 * progress

      readonly property color tint: root.sparkColors[index % root.sparkColors.length]

      Rectangle {
        anchors.centerIn: parent
        width: parent.width
        height: Math.max(1, parent.width * 0.3)
        radius: height / 2
        color: spark.tint
      }
      Rectangle {
        anchors.centerIn: parent
        width: Math.max(1, parent.width * 0.3)
        height: parent.width
        radius: width / 2
        color: spark.tint
      }
    }
  }

  Ghost {
    id: body
    anchors.horizontalCenter: parent.horizontalCenter
    height: parent.height
    width: height * 0.875
    y: -root.rise
    color: root.color
    fill: root.fill
    opacity: root.baseOpacity * root.blink
    // Squash from the hem, so the ghost crouches on its baseline and
    // stretches as it leaves it.
    transform: [
      Scale {
        origin.x: body.width / 2
        origin.y: body.height
        yScale: root.squash
        xScale: 1 + (1 - root.squash) * 0.6
      },
      Translate {
        x: root.shift
        y: -root.hop
      }
    ]
  }

  // About 1.2 s: crouch, hop, land, settle, with the sparks leaving at the
  // top of the hop.
  SequentialAnimation {
    id: celebration
    onStopped: root.reset()

    NumberAnimation { target: root; property: "squash"; to: 0.84; duration: 150; easing.type: Easing.OutQuad }
    ParallelAnimation {
      NumberAnimation { target: root; property: "hop"; to: root.height * 0.26; duration: 230; easing.type: Easing.OutQuad }
      NumberAnimation { target: root; property: "squash"; to: 1.08; duration: 230; easing.type: Easing.OutQuad }
      NumberAnimation { target: root; property: "sparkle"; from: 0; to: 1; duration: 950; easing.type: Easing.OutCubic }
      SequentialAnimation {
        PauseAnimation { duration: 230 }
        NumberAnimation { target: root; property: "hop"; to: 0; duration: 220; easing.type: Easing.InQuad }
        NumberAnimation { target: root; property: "squash"; to: 0.9; duration: 90; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "squash"; to: 1; duration: 260; easing.type: Easing.OutBack }
      }
    }
  }

  // A blink that leans back, the way a tape rewinds.
  SequentialAnimation {
    id: rewinding
    onStopped: root.reset()

    ParallelAnimation {
      NumberAnimation { target: root; property: "shift"; to: -root.height * 0.16; duration: 130; easing.type: Easing.OutQuad }
      NumberAnimation { target: root; property: "blink"; to: 0.3; duration: 130; easing.type: Easing.OutQuad }
    }
    ParallelAnimation {
      NumberAnimation { target: root; property: "shift"; to: 0; duration: 260; easing.type: Easing.OutBack }
      NumberAnimation { target: root; property: "blink"; to: 1; duration: 220; easing.type: Easing.InQuad }
    }
  }

  // A nod: down and back up, once.
  SequentialAnimation {
    id: nodding
    onStopped: root.reset()

    ParallelAnimation {
      NumberAnimation { target: root; property: "hop"; to: -root.height * 0.1; duration: 140; easing.type: Easing.OutQuad }
      NumberAnimation { target: root; property: "squash"; to: 0.9; duration: 140; easing.type: Easing.OutQuad }
    }
    ParallelAnimation {
      NumberAnimation { target: root; property: "hop"; to: 0; duration: 240; easing.type: Easing.OutBack }
      NumberAnimation { target: root; property: "squash"; to: 1; duration: 240; easing.type: Easing.OutBack }
    }
  }

  function reset() {
    if (playing) return
    hop = 0
    squash = 1
    shift = 0
    blink = 1
    sparkle = 0
  }
}
