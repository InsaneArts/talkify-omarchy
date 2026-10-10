import QtQuick
import "HudGeometry.js" as Geometry

// What a Direct Dictation session puts inside the HUD (Talkify's
// DictationHUDShellView): the housing band level with the bar, the voice
// visual's band, and the draft text band, with each visual's layout:
// - Waveform and Edge Glow replace the draft with a tall band (the waveform
//   fills it; the glow keeps it as an empty stage so the light has flanks to
//   wrap);
// - Edge Glow + Draft hangs a short stage under the housing and centers the
//   recent words on the whole island;
// - Compact puts a small voice indicator beside a leading-aligned draft;
// - a status message is the text band alone.
// The shape itself, its fillets and its reveal belong to HudSurface.
//
// Its shoulders carry the session's tags: on the left what state it is in
// (paused, latched); on the right the App rules in force, or the ⏎ a spoken
// send pressed. A paused session freezes the voice in the muted colour under
// a pause mark.
Item {
  id: shell

  property var stage: null
  property real dpr: 1
  property string fontFamily: ""
  // Talkify's colours or the theme's, live (HudStage.look).
  readonly property var look: stage.look

  readonly property var cfg: stage.settings
  readonly property real s: cfg.scale
  readonly property var m: Geometry.metrics(s)
  readonly property real housing: stage.sessionHousing
  readonly property real fillet: cfg.fillets ? Geometry.filletSize : 0
  readonly property string visual: cfg.visual

  // Held through the retract so the shape never resizes while it leaves.
  readonly property bool keepsVisualLayout: stage.layoutKind === "session"
  // The words setting resolved for the notch: by default the visual decides,
  // as on the Mac. A status line (a message, the muted warning, a dead
  // microphone) always shows, in the text band.
  readonly property bool wordsOn: cfg.showsWords
  readonly property string status: stage.statusText
  readonly property string shownText: status !== "" ? status : (wordsOn ? stage.draft : "")
  readonly property bool showsRecentDraft: visual === "glow-draft" && keepsVisualLayout && status === ""
  readonly property bool showsTextBand: !keepsVisualLayout || Geometry.showsDraftWhileListening(visual)
    || wordsOn || status !== ""
  // Not gated on listening: swapping the band's structure at the finalize
  // reads as a glitch mid-retract, so the layout stays and the indicator
  // settles instead.
  readonly property bool showsLeadingDraft: visual === "compact"
  readonly property real visualBandTarget: keepsVisualLayout && (visual === "waveform" || visual === "glow")
    ? m.waveBandHeight : 0

  readonly property bool live: stage.listening && stage.voiceAlive
  readonly property string tagText: stage.stateTag
  readonly property bool showsSendKey: stage.sent && stage.landing
  readonly property string ruleText: showsSendKey ? "" : stage.ruleTag
  // Symmetric, so a centered draft stays centered whatever the tags say.
  readonly property real tagInset: Math.max(24, tag.reserve, ruleMeasure.reserve, showsSendKey ? 25 + 12 + 8 : 0) * s
  // The words drawn a word at a time (marks) take the place of Edge Glow +
  // Draft's sliding line.
  readonly property bool richDraft: stage.draftMarks.length > 0

  readonly property real textPadding: 9 * s
  readonly property real wavePadding: 6 * s
  readonly property real indicatorRoom: showsLeadingDraft ? compactIndicator.implicitWidth + 10 * s : 0
  readonly property real draftWidth: Math.max(1, m.contentWidth - 2 * tagInset - indicatorRoom)

  readonly property real textBandTarget: {
    if (showsRecentDraft) return m.glowDraftStageHeight
    if (!showsTextBand) return 0
    return Math.max(m.textBandHeight, Math.max(measure.implicitHeight, draftBody.rich ? draftBody.implicitHeight : 0) + textPadding * 2)
  }

  readonly property real shapeHeight: housing + visualBand.value + textBand.value

  // The text band's spring: a layout change is the shell's 0.25 s spring, a
  // wrap under Grow Down its 0.18 s one; the other long-draft styles keep one
  // line and never change height.
  property string lastLayoutKey: ""
  readonly property string layoutKey: stage.layoutKind + "/" + showsRecentDraft + "/" + showsTextBand

  onTextBandTargetChanged: {
    var layoutChanged = layoutKey !== lastLayoutKey
    lastLayoutKey = layoutKey
    textBand.duration = layoutChanged ? 0.25 : 0.18
    textBand.animated = layoutChanged || cfg.longDraft === "grow-down" || status !== ""
    textBand.target = textBandTarget
  }

  // Where a shoulder item of `height` sits: beside Edge Glow + Draft's line,
  // otherwise just under the housing (and the visual band, over words).
  function tagY(height) {
    if (showsRecentDraft) return Math.round((housing + textBand.value - height) / 2)
    return housing + (showsTextBand && visualBand.value > 0 ? visualBand.value : 0) + 5 * s
  }

  // A shape mounting from nothing starts in its final layout and parked; the
  // reveal is the only motion.
  function settleForMount() {
    lastLayoutKey = layoutKey
    // The visual band's target is a binding; only its value snaps.
    visualBand.snap(visualBandTarget)
    textBand.snap(textBandTarget)
    textBand.target = textBandTarget
    surface.park()
  }

  Connections {
    target: shell.stage
    function onMountSerialChanged() { shell.settleForMount() }
    function onMountedChanged() {
      if (!shell.stage.mounted) {
        surface.park()
        ripple.stop()
        surface.rippleTime = -1
        edgeGlow.reset()
        particleCloud.reset()
      }
    }
    function onEpochChanged() {
      if (Geometry.usesEdgeGlow(shell.visual)) ripple.restart()
    }
  }

  Component.onCompleted: settleForMount()

  SpringValue {
    id: visualBand
    duration: 0.25
    bounce: 0
    target: shell.visualBandTarget
  }

  SpringValue {
    id: textBand
    duration: 0.25
    bounce: 0
  }

  // The session-start ripple across the housing, Edge Glow's alone.
  NumberAnimation {
    id: ripple
    target: surface
    property: "rippleTime"
    from: 0
    to: 1.2
    duration: 1200
    onFinished: surface.rippleTime = -1
  }

  // Measures the draft at the band's width so Grow Down can size the band.
  DraftText {
    textRgb: shell.look.textRgb
    id: measure
    visible: false
    width: shell.draftWidth
    draft: shell.shownText
    solid: true
    longDraft: shell.status !== "" ? "grow-down" : shell.cfg.longDraft
    hudScale: shell.s
    fontFamily: shell.fontFamily
  }

  TagCapsule {
    id: tag
    visible: false
    textRgb: shell.look.textRgb
    text: shell.tagText
    glyph: shell.stage.paused ? "pause" : ""
    hudScale: shell.s
    fontFamily: shell.fontFamily
  }

  TagCapsule {
    id: ruleMeasure
    visible: false
    textRgb: shell.look.textRgb
    text: shell.ruleText
    hudScale: shell.s
    fontFamily: shell.fontFamily
  }

  HudSurface {
    id: surface
    anchors.fill: parent
    shapeWidth: shell.m.contentWidth
    shapeHeight: shell.shapeHeight
    cornerRadius: shell.m.bottomCornerRadius
    filletSize: shell.fillet
    housingHeight: shell.housing
    hudScale: shell.s
    revealStyle: shell.cfg.reveal
    revealed: shell.stage.revealed
    dpr: shell.dpr
    edgeColor: shell.stage.edge
    fillColor: shell.look.fill
    shadowAlpha: shell.look.shadowAlpha
    rippleTint: shell.look.ripple

    // The waveform fills its band edge to edge, 6 points in from its top and
    // bottom. Talkify keeps the 6 fixed, which leaves the smallest sizes a
    // band too thin to draw in; here it scales, and is the same at full size.
    ChartLineWave {
      x: 0
      y: shell.housing + shell.wavePadding
      width: shell.m.contentWidth
      height: Math.max(1, shell.m.waveBandHeight - 2 * shell.wavePadding)
      visible: shell.visual === "waveform" && shell.cfg.waveformStyle === "chart-line" && opacity > 0
      opacity: shell.visualBandTarget > 0 ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 180 } }
      history: shell.stage.history
      level: shell.stage.level
      live: shell.live
      alive: shell.stage.voiceAlive
      paused: shell.stage.paused
      dpr: shell.dpr
      look: shell.look
    }

    // The bar styles keep 28-point side margins; the sheen reaches 8 past
    // them.
    WaveformBars {
      x: 28 * shell.s - margin
      y: shell.housing + shell.wavePadding - margin
      width: Math.max(1, shell.m.contentWidth - 56 * shell.s) + margin * 2
      height: Math.max(1, shell.m.waveBandHeight - 2 * shell.wavePadding) + margin * 2
      visible: shell.visual === "waveform" && shell.cfg.waveformStyle !== "chart-line" && opacity > 0
      opacity: shell.visualBandTarget > 0 ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 180 } }
      waveformStyle: shell.cfg.waveformStyle
      history: shell.stage.history
      level: shell.stage.level
      live: shell.live
      alive: shell.stage.voiceAlive
      paused: shell.stage.paused
      dpr: shell.dpr
      look: shell.look
    }

    // A paused session's mark over its frozen voice band, on a dab of the
    // shape's fill so the still line does not run through it.
    Rectangle {
      visible: shell.stage.paused && shell.visualBandTarget > 0
      x: Math.round((shell.m.contentWidth - width) / 2)
      // On Chart Line's rest line, which sits lifted toward the shape's
      // visual centre (ChartLineWave.restOffset).
      y: shell.housing + Math.round((shell.m.waveBandHeight - height) / 2)
        - (shell.cfg.waveformStyle === "chart-line" ? 10 * Math.min(1, (shell.m.waveBandHeight - 2 * shell.wavePadding) / 52) : 0)
      width: 30 * shell.s
      height: 20 * shell.s
      radius: height / 2
      color: Qt.rgba(shell.look.fill.x, shell.look.fill.y, shell.look.fill.z, 1)

      PauseMark {
        anchors.centerIn: parent
        size: 12 * shell.s
        color: shell.look.muted
      }
    }

    // The draft band below the housing and any visual band.
    Item {
      id: textBandItem
      x: shell.tagInset
      y: shell.housing + visualBand.value + shell.textPadding
      width: shell.m.contentWidth - 2 * shell.tagInset
      height: Math.max(0, textBand.value - 2 * shell.textPadding)
      visible: shell.showsTextBand && !shell.showsRecentDraft

      CompactIndicator {
        id: compactIndicator
        visible: shell.showsLeadingDraft
        x: 0
        y: 3 * shell.s
        listening: shell.stage.listening
        alive: shell.stage.voiceAlive
        paused: shell.stage.paused
        mutedColor: shell.look.muted
        level: shell.stage.level
        hudScale: shell.s
        barColor: shell.look.coreColor
      }

      LiveDraft {
        id: draftBody
        x: shell.indicatorRoom
        y: 0
        width: shell.draftWidth
        textRgb: shell.look.textRgb
        accentRgb: shell.look.accentRgb
        draft: shell.shownText
        committed: shell.stage.committed
        solid: shell.status !== "" || !shell.cfg.twoTone
        leading: shell.showsLeadingDraft
        longDraft: shell.status !== "" ? "grow-down" : shell.cfg.longDraft
        hudScale: shell.s
        fontFamily: shell.fontFamily
        marks: shell.status !== "" ? shell.stage.statusMarks : shell.stage.draftMarks
        fold: shell.stage.fold
        paused: shell.stage.paused
      }

      // The notch keeps the Mac's plain finalize; only a replayed dictation
      // is swept as it lands again.
      FinalizeSweep {
        anchors.fill: parent
        tint: shell.look.sweep
        running: shell.stage.replaying && shell.shownText !== ""
      }
    }

    // Edge Glow + Draft's recent words, centered on the whole island,
    // housing flanks included.
    RecentDraftText {
      textRgb: shell.look.textRgb
      visible: shell.showsRecentDraft && !shell.richDraft
      x: shell.tagInset
      y: 0
      width: shell.m.contentWidth - 2 * shell.tagInset
      height: shell.housing + textBand.value
      draft: shell.showsRecentDraft && shell.wordsOn && !shell.richDraft ? shell.stage.draft : ""
      committed: shell.stage.committed
      twoTone: shell.cfg.twoTone
      hudScale: shell.s
      fontFamily: shell.fontFamily
    }

    // Edge Glow + Draft's line, drawn a word at a time while it carries
    // marks: one line at the same 24 points, its head running off the
    // leading edge.
    Item {
      visible: shell.showsRecentDraft && shell.richDraft && shell.wordsOn
      x: shell.tagInset
      y: 0
      width: shell.m.contentWidth - 2 * shell.tagInset
      height: shell.housing + textBand.value

      LiveDraft {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        textRgb: shell.look.textRgb
        accentRgb: shell.look.accentRgb
        draft: parent.visible ? shell.stage.draft : ""
        committed: shell.stage.committed
        solid: !shell.cfg.twoTone
        longDraft: "tail-only"
        hudScale: shell.s * 24 / 15
        fontFamily: shell.fontFamily
        marks: parent.visible ? shell.stage.draftMarks : []
        fold: shell.stage.fold
        paused: shell.stage.paused
      }
    }

    TagCapsule {
      textRgb: shell.look.textRgb
      x: 12 * shell.s
      y: shell.tagY(height)
      text: shell.tagText
      glyph: shell.stage.paused ? "pause" : ""
      hudScale: shell.s
      fontFamily: shell.fontFamily
    }

    TagCapsule {
      textRgb: shell.look.textRgb
      x: shell.m.contentWidth - 12 * shell.s - width
      y: shell.tagY(height)
      text: shell.ruleText
      hudScale: shell.s
      fontFamily: shell.fontFamily
    }

    SendKey {
      x: shell.m.contentWidth - 12 * shell.s - width
      y: shell.tagY(height)
      active: shell.stage.sent
      pressEpoch: shell.stage.sendEpoch
      textRgb: shell.look.textRgb
      accentRgb: shell.look.accentRgb
      hudScale: shell.s * 0.85
    }

    overlays: [
      ParticleCloud {
        id: particleCloud
        x: 0
        y: 0
        width: shell.m.contentWidth
        height: shell.shapeHeight
        visible: shell.visual === "glow" && effectiveProgress > 0
        listening: shell.stage.listening && shell.visual === "glow"
        alive: shell.stage.voiceAlive
        paused: shell.stage.paused
        epoch: shell.stage.epoch
        cornerRadiusValue: shell.m.bottomCornerRadius
        topFilletRadius: shell.fillet
        colors: shell.stage.particleColors
        dpr: shell.dpr
      },
      EdgeGlow {
        id: edgeGlow
        readonly property real spillWidth: 28 * shell.s
        x: -spillWidth
        y: 0
        width: shell.m.contentWidth + spillWidth * 2
        height: shell.shapeHeight + spillWidth
        spill: spillWidth
        visible: Geometry.usesEdgeGlow(shell.visual) && (progress > 0 || listening)
        listening: shell.stage.listening && Geometry.usesEdgeGlow(shell.visual)
        alive: shell.stage.voiceAlive
        paused: shell.stage.paused
        look: shell.look
        level: shell.stage.level
        epoch: shell.stage.epoch
        hudScale: shell.s
        cornerRadiusValue: shell.m.bottomCornerRadius
        topFilletRadius: shell.fillet
        stops: shell.stage.glowStops
        dpr: shell.dpr
      }
    ]
  }
}
