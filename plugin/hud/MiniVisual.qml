import QtQuick

// The session's voice visual in miniature, for the floating placements: the
// picked waveform style (the notch's own components, smaller), or Compact's
// five bars. The finalize swaps it for stepping dots held at the same
// height, so nothing jumps while the final pass runs. A paused session
// freezes it in the muted colour under a pause mark.
Item {
  id: mini

  property var stage: null
  property real dpr: 1
  property real hudScale: 1
  // "auto" follows the settings; "bars" forces Compact's indicator.
  property string kind: "auto"

  readonly property var cfg: stage.settings
  readonly property string shown: {
    if (kind === "bars" || cfg.visual === "compact") return "bars"
    return cfg.waveformStyle === "chart-line" ? "line" : "wave"
  }
  readonly property bool live: stage.listening && stage.voiceAlive
  readonly property bool paused: stage.paused
  readonly property bool settling: stage.finalizing || stage.landing

  ChartLineWave {
    anchors.fill: parent
    visible: mini.shown === "line" && !mini.settling
    // Centered: there is no housing above it to balance.
    restOffset: 0
    history: mini.stage.history
    level: mini.stage.level
    live: mini.live
    alive: mini.stage.voiceAlive
    paused: mini.paused
    dpr: mini.dpr
    look: mini.stage.look
  }

  WaveformBars {
    x: -margin
    y: -margin
    width: mini.width + margin * 2
    height: mini.height + margin * 2
    visible: mini.shown === "wave" && !mini.settling
    waveformStyle: mini.cfg.waveformStyle
    history: mini.stage.history
    level: mini.stage.level
    live: mini.live
    alive: mini.stage.voiceAlive
    paused: mini.paused
    dpr: mini.dpr
    look: mini.stage.look
  }

  CompactIndicator {
    anchors.centerIn: parent
    visible: mini.shown === "bars" && !mini.settling
    listening: mini.stage.listening
    alive: mini.stage.voiceAlive
    paused: mini.paused
    mutedColor: mini.stage.look.muted
    level: mini.stage.level
    hudScale: mini.hudScale
    barColor: mini.stage.look.coreColor
  }

  SteppingDots {
    anchors.centerIn: parent
    // Gone once the text has landed: nothing is pending any more.
    visible: mini.stage.finalizing
    running: visible
    dotSize: 4 * mini.hudScale
    color: mini.stage.look.text
  }

  // A pause mark over the frozen voice, on a dab of the shape's own fill so
  // the still line does not run through it.
  Rectangle {
    visible: mini.paused
    anchors.centerIn: parent
    width: pauseMark.size * 2.4
    height: pauseMark.size * 1.6
    radius: height / 2
    color: Qt.rgba(mini.stage.look.fill.x, mini.stage.look.fill.y, mini.stage.look.fill.z, 1)

    PauseMark {
      id: pauseMark
      anchors.centerIn: parent
      size: Math.max(7, Math.min(12, mini.height * 0.55))
      color: mini.stage.look.muted
    }
  }
}
