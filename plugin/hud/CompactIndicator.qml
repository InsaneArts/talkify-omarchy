import QtQuick
import "HudTokens.js" as Tokens

// The Compact visual's voice indicator (HUDCompactIndicatorView): a tiny
// five-bar equalizer beside the draft, after the Dynamic Island's sound dots.
// Each bar rides the level with its own phase so the cluster reads as sound
// rather than a meter; silence settles the bars into resting dots, and a dead
// microphone freezes them amber.
Item {
  id: indicator

  property bool listening: false
  property bool alive: true
  // A paused session: the bars rest in the muted colour.
  property bool paused: false
  property color mutedColor: Qt.rgba(0.55, 0.56, 0.6, 1)
  property real level: 0
  property real hudScale: 1
  // The bars' colour while alive: white, or a theme's bright core.
  property color barColor: "white"

  readonly property int barCount: 5
  readonly property real restingHeight: 3
  readonly property bool live: listening && alive && !paused

  property real time: 0

  implicitWidth: (barCount * 2.5 + (barCount - 1) * 2.5) * hudScale
  implicitHeight: 14 * hudScale
  opacity: listening ? 1 : 0.45

  // Eases the bars down to resting dots when listening ends, instead of
  // freezing them mid-wobble.
  Behavior on opacity {
    NumberAnimation { duration: 250; easing.type: Easing.OutQuad }
  }

  Row {
    anchors.verticalCenter: parent.verticalCenter
    spacing: 2.5 * indicator.hudScale

    Repeater {
      model: indicator.barCount

      Rectangle {
        required property int index
        width: 2.5 * indicator.hudScale
        radius: width / 2
        anchors.verticalCenter: parent.verticalCenter
        color: !indicator.alive
          ? Qt.rgba(Tokens.systemOrange[0], Tokens.systemOrange[1], Tokens.systemOrange[2], 0.6)
          : (indicator.paused ? indicator.mutedColor
            : Qt.rgba(indicator.barColor.r, indicator.barColor.g, indicator.barColor.b, 0.9))
        // Per-bar phase offsets keep neighbors out of sync, so the cluster
        // shimmers with speech instead of pumping as one block.
        height: {
          if (!indicator.live) return indicator.restingHeight * indicator.hudScale
          var wobble = 0.5 + 0.5 * Math.sin(indicator.time * 9 + index * 1.7)
          return (indicator.restingHeight + indicator.level * wobble * 11) * indicator.hudScale
        }

        Behavior on height {
          enabled: !indicator.live
          NumberAnimation { duration: 250; easing.type: Easing.OutQuad }
        }
      }
    }
  }

  FrameAnimation {
    running: indicator.live && indicator.visible
    onTriggered: indicator.time += frameTime
  }
}
