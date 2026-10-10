import QtQuick
import Quickshell
import Quickshell.Hyprland
import "HudGeometry.js" as Geometry
import "HudMarks.js" as Marks
import "HudTokens.js" as Tokens
import "ThemeColors.js" as ThemeColors

// What the HUD is showing and where, derived from the talkify service's phase
// stream. Talkify splits this between HUDStage (who holds the shape, the
// retract and its order-out) and DictationHUDController (what a Direct
// Dictation session puts in it); the daemon already made the controller's
// decisions, so here they collapse into one place that turns phases into the
// shell's state.
//
// The rules it keeps:
// - A session reads its settings once, at its start, so the shape cannot
//   change size or style partway through (Talkify ADR-0004).
// - The display is the one focused when the session starts, and it does not
//   follow focus afterwards.
// - Retracting pins the layout exactly as it stands: the visual stops
//   reacting so a glow can drain, but nothing resizes or relabels under a
//   shape that is already leaving.
// - Once the retract has played, the shape is unmounted and nothing animates.
//
// Past the daemon's phases it adds three moments of its own, each over before
// the shape leaves:
// - the finalize folds what the Tidy pass removes out of the draft (`fold`);
// - the session's result, which the daemon sends just before it hides the
//   HUD, holds the shape a moment longer when there is something to see
//   land (`landing`): the fold finishing, the Enter a spoken send pressed;
// - a paste-last or retry, and a word Teach learned, flash the HUD in its
//   current placement with no session at all.
Item {
  id: stage

  property var service: null
  // The housing band's height: the Omarchy bar's, so content sits below it.
  property real housingHeight: 26
  // Settings that win over the service's, for the previews in Settings that
  // each show one placement.
  property var overrides: ({})
  // The Omarchy theme's colours (ThemePalette), shared by whoever owns this
  // stage; without one, Talkify's own colours.
  property var themePalette: null
  // Whether the surface holding the shape has its full size yet; the reveal
  // waits for it, so the first frames of the motion are not drawn into a
  // surface that is still being resized.
  property bool surfaceReady: true

  // Talkify's dismiss duration: a perceptual length rather than the spring's
  // settling time, and long enough for the drift and slide retracts.
  readonly property int dismissMilliseconds: 350

  readonly property string phase: service ? String(service.phase || "hidden") : "hidden"

  // Whether a shape is up (or still retracting) on `screenName`'s window.
  property bool mounted: false
  property bool revealed: false
  property string screenName: ""
  // Bumped each time a shape mounts from nothing, so the surface snaps to
  // its parked pose and the new layout before it reveals.
  property int mountSerial: 0

  // Talkify's showsVoiceVisual: true only while listening.
  property bool listening: false
  property bool dismissing: false
  property bool finalizing: false
  // "session" keeps the voice visual's bands; "message" is the text band.
  property string layoutKind: "session"
  property string text: ""
  // The start of `text` live insertion has already put in the window.
  property string committed: ""
  property int epoch: 0
  // When the session started listening, for the latched clock.
  property real startedAt: 0
  // Read once per mount, like the session's settings.
  property real sessionHousing: 26
  property var settings: snapshot()

  // The session's details from the daemon's `hud` event (docs/protocol.md),
  // pinned while retracting like the text.
  property bool pauseRequested: false
  property string rule: ""
  property var marks: []

  // Live inputs, pinned while retracting so a drain plays against the values
  // the session ended on.
  readonly property bool latched: !!(service && service.latched) && layoutKind === "session"
  // A paused session keeps its microphone open and nothing it hears: the
  // voice holds still, so neither the level nor the history moves.
  readonly property bool paused: pauseRequested && layoutKind === "session" && listening && !finalizing
  readonly property real level: listening && !finalizing && !paused && service ? Number(service.level) || 0 : 0
  readonly property var history: paused ? heldHistory : (service && service.levelHistory ? service.levelHistory : [])
  property var heldHistory: []
  onPausedChanged: if (paused && service && service.levelHistory) heldHistory = service.levelHistory
  property bool alive: true

  // The daemon reports a microphone that only delivers silence as a live
  // draft that says so. It is a status line, not words: it shows whatever the
  // words setting, and the visual turns to the dead-microphone amber, because
  // the level events that keep arriving would otherwise read as a quiet room.
  readonly property bool muted: layoutKind === "session" && listening
    && /is sending silence\. Is it muted\?$/.test(text) && committed === ""
  // The colours everything draws in, live rather than per session, so a theme
  // switch reaches a shape already on screen: Talkify's black and silver, or
  // the theme's (hud.colors).
  readonly property string colorsMode: String(setting("hud.colors", "theme")) === "talkify" ? "talkify" : "theme"
  readonly property var look: {
    if (colorsMode === "theme" && themePalette) return themePalette.look
    return themePalette ? themePalette.talkifyLook : ThemeColors.talkify()
  }
  readonly property vector4d edge: ThemeColors.edge(look, Number(setting("hud.edge", 0.09)))
  // The glow's colours: a named palette when one is picked, otherwise the
  // look's own. "spectrum" is the daemon's default and so means no pick: it
  // follows the colours setting, as "theme" (and the older "accent") do.
  readonly property bool glowFollowsLook: ["spectrum", "theme", "accent", ""].indexOf(String(settings.palette)) !== -1
  readonly property var glowStops: glowFollowsLook && look.glowStops ? look.glowStops
    : Tokens.glowStops(glowFollowsLook ? "spectrum" : settings.palette)
  readonly property var particleColors: glowFollowsLook && look.particles ? look.particles
    : Tokens.particleColors(glowFollowsLook ? "spectrum" : settings.palette)

  // What the voice visuals read: alive, and not the muted warning.
  readonly property bool voiceAlive: alive && !muted
  // Whether the voice moves at all: listening, alive, not finalizing, not
  // paused. The ghosts float and blink only then.
  readonly property bool voiceLive: listening && voiceAlive && !finalizing && !paused
  // A line the HUD shows whatever the words setting: a message, the muted
  // warning, or a dead microphone saying so.
  readonly property string statusText: {
    if (layoutKind === "message") return text
    if (muted) return text
    if (listening && !finalizing && !alive) return "No audio from the microphone"
    return ""
  }
  // The live draft, without the status lines that travel in the same field.
  readonly property string draft: layoutKind === "session" && !muted ? text : ""
  // The marks over the draft (HudMarks.js), and over a status line of the
  // HUD's own (a Teach message). A landing keeps the draft as the fold left
  // it.
  readonly property var draftMarks: layoutKind === "session" && !muted ? marks : []
  property var statusMarks: []

  // The tags a session wears, the one that matters most first: a pause must
  // not be missed, and latched is how a hands-free session differs from a
  // held one.
  readonly property string stateTag: {
    if (layoutKind !== "session" || (!listening && !landing)) return ""
    if (paused) return "PAUSED"
    if (latched && listening) return "LATCHED"
    return ""
  }
  // The App rules in force, named from the session's start.
  readonly property string ruleTag: layoutKind === "session" ? Marks.ruleLabel(rule) : ""

  // 0 to 1 over the finalize: what the Tidy pass removes folds out of the
  // draft as the final pass runs, so the user sees it go.
  property real fold: 0
  readonly property int foldMilliseconds: 560

  // The landed result, held a moment before the retract: the fold finishing,
  // and the Enter a spoken send pressed.
  property bool landing: false
  property bool sent: false
  property int sendEpoch: 0

  // A flash of the HUD's own (a replay, a Teach) rather than the daemon's.
  property bool localFlash: false
  // A paste-last or retry landing: its text shows with the finalize's sweep.
  property bool replaying: false
  // Bumped when Teach learns a word: the ghost nods.
  property int nodEpoch: 0

  function setting(path, fallback) {
    if (overrides && overrides[path] !== undefined) return overrides[path]
    if (service && typeof service.setting === "function") return service.setting(path, fallback)
    return fallback
  }

  function snapshot() {
    var visual = Geometry.pick(String(setting("hud.visual", "waveform")), Geometry.visuals, "waveform")
    var fillets = setting("hud.fillets", true)
    var placement = Geometry.pick(String(setting("hud.placement", "pill")), Geometry.placements, "pill")
    var words = Geometry.pick(String(setting("hud.words", "auto")), ["auto", "on", "off"], "auto")
    var insertionLive = setting("insertion.live", false) === true
      && String(setting("insertion.destination", "insert")) !== "clipboard"
    return {
      placement: placement,
      words: words,
      showsWords: Geometry.showsWords(placement, visual, words, insertionLive),
      // Live insertion splits the draft into what has landed and what can
      // still change; without it there is one tone.
      twoTone: insertionLive,
      pointerMark: Geometry.pick(String(setting("hud.pointer_mark", "ring")), ["ring", "ghost"], "ring"),
      visual: visual,
      waveformStyle: Geometry.pick(String(setting("hud.waveform_style", "chart-line")), Geometry.waveformStyles, "chart-line"),
      reveal: Geometry.pick(String(setting("hud.reveal", "slide")), Geometry.reveals, "slide"),
      longDraft: Geometry.pick(String(setting("hud.long_draft", "grow-down")), Geometry.longDrafts, "grow-down"),
      scale: Geometry.sessionScale(setting("hud.scale", 1.0), visual),
      palette: String(setting("hud.glow_palette", "spectrum")),
      fillets: fillets !== false && fillets !== "false"
    }
  }

  // The window size for a display: the mounted session's while one is up,
  // so a mapped surface never resizes under a shape, otherwise the current
  // pick's.
  function windowSize(screenWidth) {
    var scale = mounted
      ? settings.scale
      : Geometry.sessionScale(setting("hud.scale", 1.0), String(setting("hud.visual", "waveform")))
    return Geometry.windowSize(screenWidth, mounted ? sessionHousing : housingHeight, scale)
  }

  function focusedScreenName() {
    var monitor = Hyprland.focusedMonitor
    var name = monitor ? String(monitor.name) : ""
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) {
      if (screens[i].name === name) return name
    }
    return screens.length > 0 ? screens[0].name : ""
  }

  // Claims the shape. From nothing, it mounts on the focused display with
  // this moment's settings; mid-retract it turns the shape around where it
  // stands, as Talkify's claim cancels the order-out. Callers set the new
  // layout first, so a fresh mount settles straight into it.
  function claim(newSession) {
    retractTimer.stop()
    var focused = focusedScreenName()
    var fresh = !mounted || (newSession && focused !== screenName)
    // A session reads its settings at its start; a message mid-session keeps
    // the session's.
    if (fresh || newSession) settings = snapshot()
    if (fresh) {
      sessionHousing = housingHeight
      screenName = focused
      revealed = false
      mounted = true
      mountSerial += 1
    }
    // Committed after the parked frame exists, so the reveal has something
    // to animate from rather than drawing itself already open.
    revealTimer.restart()
  }

  function beginSession() {
    var wasHolding = mounted && !dismissing && layoutKind === "session" && listening
    endMoments()
    layoutKind = "session"
    dismissing = false
    finalizing = false
    alive = true
    text = ""
    committed = ""
    marks = []
    claim(!wasHolding)
    listening = true
    epoch += 1
    startedAt = Date.now()
  }

  function showMessage(message) {
    endMoments()
    layoutKind = "message"
    dismissing = false
    finalizing = false
    listening = false
    alive = true
    text = message
    committed = ""
    marks = []
    claim(false)
  }

  function retract() {
    if (!mounted) return
    revealTimer.stop()
    landTimer.stop()
    flashTimer.stop()
    localFlash = false
    if (layoutKind === "session") dismissing = true
    listening = false
    revealed = false
    retractTimer.restart()
  }

  // Stops the stage's own moments: a new session or message takes the shape
  // over from whatever was holding it.
  function endMoments() {
    landTimer.stop()
    flashTimer.stop()
    folding.stop()
    fold = 0
    landing = false
    sent = false
    localFlash = false
    replaying = false
    statusMarks = []
  }

  // Whether a Direct Dictation session holds the HUD, which a flash must
  // not interrupt.
  function busy() {
    return phase === "listening" || phase === "live" || phase === "finalizing"
      || landing || (mounted && !dismissing && layoutKind === "session")
  }

  // The result of the session that just finalized, which arrives before
  // the hide. Held on screen only while there is something to see: the
  // fold finishing, a send.
  function land(result) {
    if (!result || !mounted || dismissing || layoutKind !== "session" || !finalizing) return
    // The fold always plays out once it has something to fold.
    var folds = Marks.pieces(text, marks).some(function (piece) {
      return Marks.folds(piece.kind) || piece.glyph !== ""
    })
    if (folds && !folding.running && fold < 1) folding.restart()
    var foldLeft = folds && folding.running ? Math.round((1 - fold) * foldMilliseconds) + 150 : 0
    if (!result.sent && foldLeft === 0) return
    landing = true
    finalizing = false
    listening = false
    sent = !!result.sent
    if (sent) sendEpoch += 1
    landTimer.interval = Math.max(foldLeft, sent ? 700 : 0)
    landTimer.restart()
  }

  // paste-last or retry: the text that landed, swept once, then gone; or why
  // it did not land.
  function flashReplay(replayed) {
    if (!replayed || busy()) return
    var inserted = !!replayed.inserted && String(replayed.text || "") !== ""
    showMessage(inserted ? String(replayed.text) : String(replayed.note || "Nothing was pasted"))
    localFlash = true
    replaying = inserted
    flashTimer.interval = inserted ? 900 : 1800
    flashTimer.restart()
  }

  // Teach learned a correction: "heard omachi → Omarchy", and a nod.
  function flashTaught(taught) {
    if (!taught || busy()) return
    var message = Marks.taughtMessage(taught.heard, taught.written)
    showMessage(message.text)
    statusMarks = message.marks
    localFlash = true
    nodEpoch += 1
    flashTimer.interval = 2100
    flashTimer.restart()
  }

  property string _lastPhase: "hidden"

  function sync() {
    var previous = _lastPhase
    _lastPhase = phase
    switch (phase) {
    case "listening":
    case "live":
    case "finalizing":
      // A listening phase that does not follow one is a new session, even
      // when the last one never reached hidden.
      var restarted = phase === "listening" && previous !== "listening" && previous !== "live"
      if (!listening || dismissing || landing || restarted) beginSession()
      var wasFinalizing = finalizing
      finalizing = phase === "finalizing"
      if (finalizing && !wasFinalizing) folding.restart()
      pauseRequested = !!service.paused
      rule = String(service.rule || "")
      marks = phase === "listening" ? [] : (service.marks || [])
      // Talkify forces the microphone alive for the finalize: the silence
      // after the last word is not a dead microphone.
      alive = finalizing || !service || !!service.micAlive
      if (phase !== "listening") {
        text = String(service.text || "")
        committed = String(service.committed || "")
      }
      break
    case "message":
      showMessage(String(service.text || ""))
      break
    default:
      // A flash or a landing of the stage's own retracts on its own clock.
      if (localFlash || landing) break
      retract()
    }
  }

  onPhaseChanged: sync()
  onServiceChanged: sync()

  Connections {
    target: stage.service
    ignoreUnknownSignals: true
    function onTextChanged() {
      if (stage.phase === "live" || stage.phase === "finalizing" || stage.phase === "message")
        stage.text = String(stage.service.text || "")
    }
    function onCommittedChanged() {
      if (stage.phase === "live" || stage.phase === "finalizing")
        stage.committed = String(stage.service.committed || "")
    }
    function onMicAliveChanged() {
      if (stage.listening && !stage.finalizing) stage.alive = !!stage.service.micAlive
    }
    function onPausedChanged() {
      if (stage.inSession()) stage.pauseRequested = !!stage.service.paused
    }
    function onRuleChanged() {
      if (stage.inSession()) stage.rule = String(stage.service.rule || "")
    }
    function onMarksChanged() {
      if (stage.phase === "live" || stage.phase === "finalizing") stage.marks = stage.service.marks || []
    }
    function onLastResultChanged() { stage.land(stage.service.lastResult) }
    function onReplayEpochChanged() { stage.flashReplay(stage.service.replayed) }
    function onTaughtEpochChanged() { stage.flashTaught(stage.service.taught) }
  }

  function inSession() {
    return (phase === "listening" || phase === "live" || phase === "finalizing") && !landing
  }

  NumberAnimation {
    id: folding
    target: stage
    property: "fold"
    from: 0
    to: 1
    duration: stage.foldMilliseconds
    easing.type: Easing.InOutQuad
  }

  Timer {
    id: landTimer
    onTriggered: stage.retract()
  }

  Timer {
    id: flashTimer
    onTriggered: stage.retract()
  }

  Timer {
    id: revealTimer
    interval: 30
    property int waited: 0
    onTriggered: {
      // A surface grown for this session takes a configure round trip to
      // reach its size; a few frames at most, then reveal regardless.
      if (!stage.surfaceReady && waited < 12) {
        waited += 1
        restart()
        return
      }
      waited = 0
      stage.revealed = true
    }
  }

  Timer {
    id: retractTimer
    interval: stage.dismissMilliseconds
    onTriggered: {
      // Only once it is off screen: clearing any of this earlier would show
      // through the retract.
      stage.mounted = false
      stage.dismissing = false
      stage.finalizing = false
      stage.text = ""
      stage.committed = ""
      stage.endMoments()
      stage.marks = []
    }
  }
}
