import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import "hud"
import "hud/PreviewScripts.js" as Scripts

// Preview harness for the HUD: the real Hud.qml, driven by the scripted
// session the Settings previews use (hud/PreviewSession.qml), through every
// placement, phase, visual, waveform style, long-draft style and reveal.
// The window placements use whatever window has focus, and the pointer
// placement the real pointer. The bar island, which lives in the bar, is
// drawn here on a stand-in bar strip at the top centre.
//
//   quickshell -p plugin/dev
//
// Environment:
//   HUD_TOUR=loop       (default) cycle every scenario until killed
//   HUD_TOUR=none       no script; drive it over IPC
//   HUD_TOUR=shots      play the capture tour once, screenshot the focused
//                       display into HUD_SHOTS (a directory) with grim, then quit
//   HUD_TOUR=reactions  the same for the newer reactions only (marks, App
//                       rules and send, pause, replay, Teach), every
//                       placement; HUD_SHOTS_FILTER narrows it
//   HUD_TOUR=quiet      every reaction in every placement, each followed by
//                       two quiet seconds between "quiet: start" and "quiet:
//                       end" log lines; run with QSG_RENDER_TIMING=1 and
//                       --log-times to check nothing renders once the HUD
//                       has retracted (dev/quiet.sh does it)
//   HUD_SHOTS_FILTER    a regular expression; only matching shots are taken
//   HUD_BACKDROP=blue   draw a stand-in wallpaper behind the top centre
//                       (blue, light, dark); default is the real desktop
//   HUD_THEME=path      read that colors.toml instead of the current theme,
//                       e.g. /usr/share/omarchy/themes/white/colors.toml
//   HUD_COLORS=talkify  play every scripted session in Talkify's own colours
//                       rather than the theme's
//   HUD_SETTINGS=1      also open the Settings menu (the plugin's own
//                       TalkifySettings.qml) on its Appearance page, fed by a
//                       second scripted session
//
// While it runs, `quickshell ipc -p plugin/dev call hudDev <fn> ...` drives it
// by hand: scene <placement>, reaction <name> <placement> (tidy, paused,
// replay, taught), set <key> <value>, phase <phase> <text>, voice
// <off|silence|speech>, mic <true|false>, latch <bool>, loop, stop.
ShellRoot {
  id: root

  readonly property string tour: Quickshell.env("HUD_TOUR") || "loop"
  readonly property string shotsDir: Quickshell.env("HUD_SHOTS") || "/tmp"
  property string backdrop: Quickshell.env("HUD_BACKDROP") || "none"

  readonly property string sentence: "So I was thinking we could ship the port this week and then spend "
    + "the next one polishing the reveal and the glow until the whole thing feels right"

  PreviewSession {
    id: fake
  }

  Hud {
    id: hud
    service: fake
    themePath: Quickshell.env("HUD_THEME") || ""
  }

  // The stand-in island and the Settings window read the same theme.
  ThemePalette {
    id: devTheme
    path: Quickshell.env("HUD_THEME") || (Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml")
    followShell: !Quickshell.env("HUD_THEME")
  }

  // The display the HUD will pick, for the captures.
  readonly property var focusedScreen: {
    var name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) if (screens[i].name === name) return screens[i]
    return screens.length ? screens[0] : null
  }

  function shot(name) {
    var s = focusedScreen
    if (!s) return
    Quickshell.execDetached(["grim", "-o", s.name, root.shotsDir + "/" + name + ".png"])
  }

  function configure(settings, insertionLive) {
    var next = JSON.parse(JSON.stringify(fake.config))
    next.hud = {
      visual: "waveform",
      waveform_style: "chart-line",
      reveal: "slide",
      long_draft: "grow-down",
      scale: 1.0,
      placement: "pill",
      words: "auto"
    }
    if (Quickshell.env("HUD_COLORS")) next.hud.colors = Quickshell.env("HUD_COLORS")
    for (var key in settings) next.hud[key] = settings[key]
    next.insertion = { live: !!insertionLive, destination: "insert" }
    fake.config = next
  }

  // Steps run in order; each waits `wait` ms before the next one starts.
  function step(wait, run) {
    return { wait: wait, run: run }
  }

  // A whole Direct Dictation session: silence, speech with the draft
  // arriving word by word, the finalize, the retract. `shots` names the
  // moments to capture: silent, speaking, live, finalizing, dead, muted.
  function session(settings, options) {
    options = options || {}
    var steps = []
    var words = root.sentence.split(" ").slice(0, options.words || 12)
    var shots = options.shots || {}
    var live = !!options.liveInsertion
    steps.push(step(250, function () { configure(settings, live); fake.latched = !!options.latched }))
    steps.push(step(options.silentMs || 1400, function () {
      fake.voice = options.deadMic ? "off" : "silence"
      fake.enter("listening")
      if (options.deadMic) fake.micAlive = false
    }))
    if (shots.silent) steps.push(step(900, function () { root.shot(shots.silent) }))
    if (options.deadMic) {
      if (shots.dead) steps.push(step(600, function () { root.shot(shots.dead) }))
      steps.push(step(900, function () { fake.enter("hidden") }))
      return steps
    }
    if (options.muted) {
      // The daemon's muted microphone: silence arriving, a warning as the draft.
      steps.push(step(900, function () {
        // A real device name, long enough that the warning needs two lines:
        // a status line must wrap whole, never lose its head.
        fake.enter("live", "INZONE H5 Mono Wireless Gaming Headset is sending silence. Is it muted?")
        fake.micAlive = false
      }))
      if (shots.muted) steps.push(step(600, function () { root.shot(shots.muted) }))
      steps.push(step(900, function () { fake.enter("hidden") }))
      return steps
    }
    steps.push(step(1200, function () { fake.voice = "speech" }))
    if (shots.speaking) steps.push(step(400, function () { root.shot(shots.speaking) }))
    for (var i = 0; i < words.length; i++) {
      (function (n) {
        steps.push(step(240, function () {
          var shown = words.slice(0, n + 1)
          fake.enter("live", shown.join(" "), live ? fake.committedFor(shown) : "")
        }))
      })(i)
    }
    if (shots.live) steps.push(step(300, function () { root.shot(shots.live) }))
    steps.push(step(700, function () { fake.voice = "off"; fake.enter("finalizing", fake.text, fake.committed) }))
    if (shots.finalizing) steps.push(step(250, function () { root.shot(shots.finalizing) }))
    steps.push(step(900, function () { fake.enter("hidden") }))
    return steps
  }

  // The newer reactions, from the scripts the Settings previews play
  // (PreviewScripts.js). `shots` names the moments to capture.

  // A tidied draft for a terminal: the App rules' tag at the start, the marks
  // over the words, the fold at the finalize, Enter pressed as it lands.
  // Moments: start, vocab (just after the vocabulary hit), live, fold, send.
  function tidyScene(settings, shots) {
    shots = shots || {}
    var t = Scripts.tidy
    var words = t.sentence.split(" ")
    var details = function (n) { return { rule: t.rule, marks: Scripts.draft(t.sentence, t.spec, n).marks } }
    var steps = [step(250, function () { configure(settings, false); fake.latched = false })]
    steps.push(step(900, function () { fake.voice = "silence"; fake.enter("listening", "", "", { rule: t.rule }) }))
    if (shots.start) steps.push(step(300, function () { root.shot(shots.start) }))
    steps.push(step(300, function () { fake.voice = "speech" }))
    for (var i = 0; i < words.length; i++) {
      (function (n) {
        steps.push(step(200, function () { fake.enter("live", words.slice(0, n).join(" "), "", details(n)) }))
        if (words[n - 1] === "omachi" && shots.vocab) steps.push(step(150, function () { root.shot(shots.vocab) }))
      })(i + 1)
    }
    if (shots.live) steps.push(step(600, function () { root.shot(shots.live) }))
    steps.push(step(shots.fold ? 300 : 700, function () {
      fake.voice = "off"
      fake.enter("finalizing", fake.text, "", details(words.length))
    }))
    if (shots.fold) steps.push(step(450, function () { root.shot(shots.fold) }))
    // The daemon sends the result, then hides the HUD.
    steps.push(step(1, function () { fake.finish({ text: t.result.text, raw: t.result.raw, sent: true, rule: t.rule }) }))
    steps.push(step(shots.send ? 290 : 1600, function () { fake.enter("hidden") }))
    if (shots.send) steps.push(step(1400, function () { root.shot(shots.send) }))
    return steps
  }

  // A latched session paused partway. Moments: paused.
  function pausedScene(settings, shots) {
    shots = shots || {}
    var t = Scripts.paused
    var words = t.sentence.split(" ")
    var steps = [step(250, function () { configure(settings, false); fake.latched = true })]
    steps.push(step(800, function () { fake.voice = "silence"; fake.enter("listening") }))
    steps.push(step(300, function () { fake.voice = "speech" }))
    for (var i = 0; i < t.before; i++) {
      (function (n) {
        steps.push(step(200, function () { fake.enter("live", words.slice(0, n).join(" "), "") }))
      })(i + 1)
    }
    steps.push(step(700, function () { fake.enter("live", fake.text, "", { paused: true }) }))
    if (shots.paused) steps.push(step(500, function () { root.shot(shots.paused) }))
    steps.push(step(400, function () { fake.enter("live", fake.text, "") }))
    steps.push(step(700, function () { fake.voice = "off"; fake.enter("finalizing", fake.text, "") }))
    steps.push(step(1300, function () { fake.latched = false; fake.enter("hidden") }))
    return steps
  }

  // paste-last's flash, and one that did not land. Moments: replay, failed.
  function replayScene(settings, shots) {
    shots = shots || {}
    var steps = [step(300, function () { configure(settings, false) })]
    steps.push(step(shots.replay ? 380 : 1600, function () { fake.replayFlash(Scripts.replay, true) }))
    if (shots.replay) steps.push(step(1300, function () { root.shot(shots.replay) }))
    if (shots.failed) {
      steps.push(step(700, function () { fake.replayFlash("", false, "Nothing to paste yet") }))
      steps.push(step(2000, function () { root.shot(shots.failed) }))
    }
    return steps
  }

  // Teach: the message and the ghost's nod. Moments: nod, taught.
  function taughtScene(settings, shots) {
    shots = shots || {}
    var steps = [step(300, function () { configure(settings, false) })]
    steps.push(step(shots.nod ? 390 : 900, function () { fake.teachFlash(Scripts.taught.heard, Scripts.taught.written) }))
    if (shots.nod) steps.push(step(600, function () { root.shot(shots.nod) }))
    if (shots.taught) steps.push(step(1800, function () { root.shot(shots.taught) }))
    else steps.push(step(2000, null))
    return steps
  }

  function reaction(name, settings, shots) {
    switch (name) {
    case "tidy": return tidyScene(settings, shots)
    case "paused": return pausedScene(settings, shots)
    case "replay": return replayScene(settings, shots)
    case "taught": return taughtScene(settings, shots)
    }
    return []
  }

  // Each reaction in every placement, with the words on where a reaction is
  // about the words. Named <reaction>-<moment>-<placement>.
  function reactionsScript() {
    var entries = []
    for (var i = 0; i < placements.length; i++) {
      var p = placements[i]
      var on = { placement: p, words: "on" }
      var auto = { placement: p }
      entries.push([["marks-vocab-" + p, "marks-live-" + p, "marks-fold-" + p],
        tidyScene(on, { vocab: "marks-vocab-" + p, live: "marks-live-" + p, fold: "marks-fold-" + p })])
      entries.push([["rule-start-" + p, "rule-send-" + p], tidyScene(auto, { start: "rule-start-" + p, send: "rule-send-" + p })])
      entries.push([["paused-" + p], pausedScene(auto, { paused: "paused-" + p })])
      entries.push([["replay-" + p, "replay-failed-" + p], replayScene(auto, { replay: "replay-" + p, failed: "replay-failed-" + p })])
      entries.push([["taught-nod-" + p, "taught-" + p], taughtScene(auto, { nod: "taught-nod-" + p, taught: "taught-" + p })])
    }
    return filtered(entries)
  }

  // Each reaction, then a quiet window the frame log is checked over: the
  // shape has retracted 1.2 s before it opens.
  function quietScript() {
    var names = ["tidy", "paused", "replay", "taught"]
    var lists = []
    for (var i = 0; i < placements.length; i++) {
      for (var j = 0; j < names.length; j++) {
        (function (placement, name) {
          lists.push(reaction(name, { placement: placement, words: "on" }, {}))
          lists.push([
            step(1200, null),
            step(2000, function () { console.log("quiet: start " + name + " " + placement) }),
            step(1, function () { console.log("quiet: end") })
          ])
        })(placements[i], names[j])
      }
    }
    lists.push([step(400, function () { Quickshell.execDetached(["pkill", "-f", "^(qs|quickshell) (-p|--path) \\S*dev/?( |$)"]) })])
    return concat(lists)
  }

  function filtered(entries) {
    var filter = Quickshell.env("HUD_SHOTS_FILTER") || ""
    var pattern = filter.length ? new RegExp(filter) : null
    var lists = []
    for (var k = 0; k < entries.length; k++) {
      var keep = !pattern
      for (var j = 0; j < entries[k][0].length && !keep; j++) keep = pattern.test(entries[k][0][j])
      if (keep) lists.push(entries[k][1])
    }
    // Quickshell connects nothing to Qt.quit(), so the tour ends the harness
    // itself.
    lists.push([step(400, function () { Quickshell.execDetached(["pkill", "-f", "^(qs|quickshell) (-p|--path) \\S*dev/?( |$)"]) })])
    return concat(lists)
  }

  function message(settings, text, shotName) {
    var steps = [step(120, function () { configure(settings, false) })]
    steps.push(step(shotName ? 700 : 1800, function () { fake.enter("message", text) }))
    if (shotName) steps.push(step(1100, function () { root.shot(shotName) }))
    steps.push(step(900, function () { fake.enter("hidden") }))
    return steps
  }

  function concat(lists) {
    var out = []
    for (var i = 0; i < lists.length; i++) out = out.concat(lists[i])
    return out
  }

  readonly property var placements: ["pill", "window", "halo", "island", "pointer", "notch"]

  function loopScript() {
    var lists = []
    for (var i = 0; i < placements.length; i++) {
      lists.push(session({ placement: placements[i] }))
      lists.push(session({ placement: placements[i], words: "on" }, { liveInsertion: true }))
    }
    lists.push(message({ placement: "pill" }, "Speech model is still loading"))
    lists.push(session({ placement: "pill" }, { muted: true }))
    lists.push(session({ placement: "pill", visual: "compact" }, { latched: true }))
    return concat(lists)
  }

  // Each entry is [shot names, steps]; HUD_SHOTS_FILTER (a regular
  // expression) keeps only the entries with a matching shot.
  function shotsScript() {
    var entries = []
    for (var i = 0; i < placements.length; i++) {
      var p = placements[i]
      entries.push([[p + "-off"], session({ placement: p, words: "off" }, { shots: { speaking: p + "-off" } })])
      entries.push([[p + "-on"], session({ placement: p, words: "on" }, { liveInsertion: true, shots: { live: p + "-on" } })])
      // Under the long-draft pick that elides heads, which status lines ignore.
      entries.push([[p + "-status"], session({ placement: p, long_draft: "tail-only" }, { muted: true, shots: { muted: p + "-status" } })])
      entries.push([[p + "-latched-final"], session({ placement: p, words: "on" }, { latched: true, words: 6, shots: { finalizing: p + "-latched-final" } })])
      entries.push([[p + "-message"], message({ placement: p }, "Couldn't paste into that field, so it's on the clipboard", p + "-message")])
      entries.push([[p + "-dead"], session({ placement: p }, { deadMic: true, shots: { dead: p + "-dead" } })])
    }
    // The colours: the same scenes under whatever theme HUD_THEME names.
    entries.push([["look-pill"], session({ placement: "pill", words: "on" }, { liveInsertion: true, shots: { live: "look-pill" } })])
    entries.push([["look-halo"], session({ placement: "halo" }, { shots: { speaking: "look-halo" } })])
    entries.push([["look-notch"], session({ placement: "notch", visual: "glow" }, { shots: { speaking: "look-notch" } })])
    entries.push([["look-capsules"], session({ placement: "pill", waveform_style: "capsules", words: "off" }, { shots: { speaking: "look-capsules" } })])
    entries.push([["look-talkify"], session({ placement: "pill", words: "on", colors: "talkify" }, { shots: { live: "look-talkify" } })])
    return filtered(entries)
  }

  QtObject {
    id: director

    property var steps: []
    property int index: 0
    property bool looping: false

    function play(list, loop) {
      steps = list
      index = 0
      looping = loop
      stepTimer.interval = 1
      stepTimer.restart()
    }

    function stop() {
      stepTimer.stop()
    }

    function advance() {
      if (index >= steps.length) {
        if (!looping) return
        index = 0
      }
      var next = steps[index]
      index += 1
      if (next.run) next.run()
      stepTimer.interval = Math.max(1, next.wait || 0)
      stepTimer.restart()
    }

    property Timer stepTimer: Timer {
      onTriggered: director.advance()
    }
  }

  // Give the surfaces a moment to map before the first reveal.
  Timer {
    interval: 800
    running: true
    onTriggered: {
      if (root.tour === "shots") director.play(root.shotsScript(), false)
      else if (root.tour === "reactions") director.play(root.reactionsScript(), false)
      else if (root.tour === "quiet") director.play(root.quietScript(), false)
      else if (root.tour === "loop") director.play(root.loopScript(), true)
    }
  }

  IpcHandler {
    target: "hudDev"

    function scene(name: string): string {
      director.play(root.session({ placement: name }), false)
      return "ok"
    }
    function reaction(name: string, placement: string): string {
      director.play(root.reaction(name, { placement: placement, words: "on" }, {}), false)
      return "ok"
    }
    function loop(): string {
      director.play(root.loopScript(), true)
      return "ok"
    }
    function stop(): string {
      director.stop()
      return "ok"
    }
    function set(key: string, value: string): string {
      var parsed = value
      if (value === "true" || value === "false") parsed = value === "true"
      else if (!isNaN(Number(value))) parsed = Number(value)
      fake.setHud(key, parsed)
      return "ok"
    }
    function phase(next: string, text: string): string {
      fake.enter(next, text)
      return "ok"
    }
    function voice(mode: string): string {
      fake.voice = mode
      return "ok"
    }
    function mic(alive: bool): string {
      fake.micAlive = alive
      return "ok"
    }
    function latch(on: bool): string {
      fake.latched = on
      return "ok"
    }
    function backdrop(mode: string): string {
      root.backdrop = mode
      return "ok"
    }
    function capture(name: string): string {
      root.shot(name)
      return "ok"
    }
  }

  // The Settings menu, for checking the Appearance page's previews.
  PreviewSession {
    id: settingsService
  }

  PanelWindow {
    visible: Quickshell.env("HUD_SETTINGS") === "1"
    screen: root.focusedScreen
    anchors.top: true
    anchors.right: true
    margins.top: Style.bar.sizeHorizontal + 10
    margins.right: 20
    implicitWidth: Style.space(920) + 40
    implicitHeight: Math.min(1060, settingsView.implicitHeight + 40)
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "talkify-hud-dev-settings"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b, 1)

    TalkifySettings {
      id: settingsView
      x: 20
      y: 20
      width: parent.width - 40
      height: parent.height - 40
      svc: settingsService
      section: "appearance"
      active: true
    }
  }

  // The bar island lives in the bar (BarWidget.qml); here it is drawn on a
  // stand-in strip at the top centre, fed by the same session.
  HudStage {
    id: islandStage
    service: fake
    housingHeight: Style.bar.sizeHorizontal
    themePalette: devTheme
  }

  PanelWindow {
    visible: islandStage.mounted && islandStage.settings.placement === "island" || root.backdrop !== "none"
    screen: root.focusedScreen
    anchors.top: true
    implicitWidth: 760
    implicitHeight: root.backdrop !== "none" ? 250 : Style.bar.sizeHorizontal
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "talkify-hud-dev-backdrop"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}
    color: "transparent"

    Rectangle {
      anchors.fill: parent
      visible: root.backdrop !== "none"
      gradient: Gradient {
        GradientStop {
          position: 0
          color: root.backdrop === "light" ? "#e9e6df" : (root.backdrop === "dark" ? "#16181b" : Qt.rgba(0.25, 0.4, 0.8, 1))
        }
        GradientStop {
          position: 1
          color: root.backdrop === "light" ? "#cfd6dc" : (root.backdrop === "dark" ? "#0d0e10" : Qt.rgba(0.1, 0.15, 0.35, 1))
        }
      }
    }

    // A transparent bar strip: the clock, and the island beside it.
    Rectangle {
      width: parent.width
      height: Style.bar.sizeHorizontal
      color: Qt.rgba(0, 0, 0, 0.35)
      visible: islandStage.settings.placement === "island" && islandStage.mounted

      Text {
        id: clockText
        anchors.verticalCenter: parent.verticalCenter
        x: 24
        text: Qt.formatDateTime(new Date(), "dddd HH:mm")
        color: Color.bar.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }

      IslandPill {
        anchors.right: parent.right
        anchors.rightMargin: 120
        stage: islandStage
        barHeight: parent.height
        active: true
        fontFamily: Style.font.family
        dpr: 1.25
      }
    }
  }
}
