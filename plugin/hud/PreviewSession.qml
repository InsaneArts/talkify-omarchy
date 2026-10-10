import QtQuick
import "PreviewScripts.js" as Scripts

// A stand-in for Service.qml that plays a session instead of listening to
// the daemon: the same properties and `setting()`, so a HudStage fed by it
// drives the real placements. The preview harness scripts it by hand; the
// Settings previews let it loop on its own, through a plain session and
// then each newer reaction in turn (PreviewScripts.js): a tidied draft sent
// to a terminal, a pause, and a replay and a Teach.
//
// The level stream is shaped like speech — syllables about four a second, each
// with its own loudness, over a quiet noise floor, grouped into phrases with
// pauses — and folded into the history exactly as Service.qml folds the
// daemon's level events. With live insertion on, the committed prefix trails
// the draft by a couple of words, as the daemon's does.
Item {
  id: session

  readonly property int barCount: 56

  // Settings come from `source` (the real service, in Settings) unless
  // `overrides` or the local `config` say otherwise.
  property var source: null
  property var overrides: ({})
  property var config: ({
    hud: {
      visual: "waveform",
      waveform_style: "chart-line",
      reveal: "slide",
      long_draft: "grow-down",
      scale: 1.0,
      placement: "pill",
      words: "auto"
    }
  })

  property bool connected: true
  property string trigger: "keyboard"
  property string engineStatus: "ready"
  property string engineDetail: ""
  property real engineProgress: 1
  property bool recording: false
  property string phase: "hidden"
  property bool latched: false
  property string text: ""
  property string committed: ""
  property int sessionEpoch: 0
  property real level: 0
  property var levelHistory: emptyHistory()
  property bool micAlive: true

  // Service.qml's newer session fields, set by `enter` before the phase.
  property bool paused: false
  property string rule: ""
  property var marks: []
  property var lastResult: null
  property var replayed: null
  property int replayEpoch: 0
  property var taught: null
  property int taughtEpoch: 0

  // "off" sends no levels at all (a dead microphone sends none either),
  // "silence" sends the noise floor, "speech" sends phrases.
  property string voice: "off"
  property real clock: 0

  // Loops a whole session on its own while true; Settings sets it only while
  // its preview is on screen.
  property bool playing: false
  property string sentence: "So I was thinking we could ship the port this week and then polish the reveal"

  function emptyHistory() {
    var bars = []
    for (var i = 0; i < barCount; i++) bars.push(0)
    return bars
  }

  function setting(path, fallback) {
    if (overrides && overrides[path] !== undefined) return overrides[path]
    if (source && typeof source.setting === "function") return source.setting(path, fallback)
    var parts = path.split(".")
    var node = config
    for (var i = 0; i < parts.length; i++) {
      if (!node || node[parts[i]] === undefined) return fallback
      node = node[parts[i]]
    }
    return node
  }

  // Service.qml's command surface, so Settings can drive a preview session
  // in the harness.
  function set(key, value) {
    var parts = key.split(".")
    var next = JSON.parse(JSON.stringify(config))
    if (!next[parts[0]]) next[parts[0]] = {}
    next[parts[0]][parts[1]] = value
    config = next
  }
  function toggle() {}
  function cancel() {}
  function loadModel() {}

  function setHud(key, value) {
    var next = JSON.parse(JSON.stringify(config))
    next.hud[key] = value
    config = next
  }

  // Mirrors Service.handle("hud"), in its order: the phase first, then the
  // text and the newer fields, so a HudStage sees what it sees live.
  // `details` carries the newer fields (paused, rule, marks);
  // left out, they reset as an older daemon's events would leave them.
  function enter(nextPhase, nextText, nextCommitted, details) {
    details = details || {}
    if (nextPhase === "listening" && phase !== "listening" && phase !== "live") {
      sessionEpoch += 1
      level = 0
      levelHistory = emptyHistory()
      micAlive = true
    }
    recording = nextPhase === "listening" || nextPhase === "live"
    if (!recording) level = 0
    phase = nextPhase
    text = nextText || ""
    committed = nextCommitted || ""
    paused = !!details.paused
    rule = details.rule || ""
    marks = details.marks || []
  }

  // Service.handle("result"): sent just before the hide, as the daemon does.
  function finish(result) {
    lastResult = {
      text: result.text || "", inserted: result.inserted !== false, note: result.note || "",
      raw: result.raw || "", sent: !!result.sent, rule: result.rule || ""
    }
  }

  // Service.handle("replayed") and ("taught").
  function replayFlash(replayText, inserted, note) {
    replayed = { text: replayText, inserted: inserted !== false, note: note || "" }
    replayEpoch += 1
  }
  function teachFlash(heard, written) {
    taught = { heard: heard, written: written }
    taughtEpoch += 1
  }

  // The committed prefix live insertion would have put in by now: all but the
  // last two words, when live insertion is on.
  function committedFor(words) {
    if (setting("insertion.live", false) !== true) return ""
    if (words.length <= 2) return ""
    return words.slice(0, words.length - 2).join(" ") + " "
  }

  function noise() {
    return 0.012 + Math.random() * 0.02
  }

  property real phraseEnd: 2.2
  property real pauseEnd: 0
  property real syllablePhase: 0
  property real syllableLoudness: 0.5
  function speech(t) {
    if (t > phraseEnd) {
      pauseEnd = t + 0.35 + Math.random() * 0.35
      phraseEnd = pauseEnd + 1.6 + Math.random() * 1.0
    }
    if (t < pauseEnd) return noise()
    var previous = syllablePhase
    syllablePhase += 0.022 * (3.4 + Math.random() * 1.6) * 2 * Math.PI
    if (Math.floor(syllablePhase / Math.PI) !== Math.floor(previous / Math.PI))
      syllableLoudness = 0.25 + Math.random() * 0.5
    var burst = Math.max(0, Math.sin(syllablePhase))
    return 0.05 + burst * syllableLoudness * (0.85 + 0.3 * Math.random())
  }

  function tick() {
    clock += 0.022
    var raw = voice === "speech" ? speech(clock) : noise()
    level = Math.max(raw, level * 0.88)
    var bars = levelHistory.slice(1)
    var last = bars.length ? bars[bars.length - 1] : 0
    bars.push(0.6 * raw + 0.4 * last)
    levelHistory = bars
  }

  Timer {
    interval: 22
    repeat: true
    running: session.voice !== "off" && (session.phase === "listening" || session.phase === "live")
    onTriggered: session.tick()
  }

  // The loop: scene after scene, each a list of steps that wait their turn.
  property int scene: 0
  property var script: []
  property int cursor: 0
  readonly property int sceneCount: 4

  function step(wait, run) {
    return { wait: wait, run: run }
  }

  // The words of `sentence` arriving one at a time; `details(n)` gives each
  // moment's newer fields.
  function speak(steps, words, from, to, details) {
    for (var i = from; i < to; i++) {
      (function (n) {
        steps.push(step(230, function () {
          var shown = words.slice(0, n)
          session.enter("live", shown.join(" "), session.committedFor(shown), details ? details(n) : null)
        }))
      })(i + 1)
    }
  }

  function scenePlain() {
    var words = sentence.split(" ")
    var steps = [step(1300, function () { session.voice = "silence"; session.enter("listening") }),
      step(700, function () { session.voice = "speech" })]
    speak(steps, words, 0, words.length)
    steps.push(step(900, function () { session.voice = "off"; session.enter("finalizing", session.text, session.committed) }))
    steps.push(step(1400, function () { session.enter("hidden") }))
    return steps
  }

  // A tidied draft for a terminal: a filler, a vocabulary hit, a scratched
  // phrase, a spoken comma and the send phrase, folded at the finalize and
  // sent with Enter.
  function sceneTidy() {
    var t = Scripts.tidy
    var words = t.sentence.split(" ")
    var details = function (n) {
      var d = Scripts.draft(t.sentence, t.spec, n)
      return { rule: t.rule, marks: d.marks }
    }
    var steps = [step(900, function () { session.voice = "silence"; session.enter("listening", "", "", { rule: t.rule }) }),
      step(500, function () { session.voice = "speech" })]
    speak(steps, words, 0, words.length, details)
    steps.push(step(800, function () {
      session.voice = "off"
      session.enter("finalizing", session.text, session.committed, details(words.length))
    }))
    steps.push(step(1, function () { session.finish({ text: t.result.text, raw: t.result.raw, sent: true, rule: t.rule }) }))
    steps.push(step(1900, function () { session.enter("hidden") }))
    return steps
  }

  // A latched session paused partway: the voice holds still, then resumes.
  function scenePaused() {
    var t = Scripts.paused
    var words = t.sentence.split(" ")
    var steps = [step(900, function () {
      session.latched = true
      session.voice = "silence"
      session.enter("listening")
    }), step(500, function () { session.voice = "speech" })]
    speak(steps, words, 0, t.before)
    steps.push(step(2200, function () { session.enter("live", session.text, session.committed, { paused: true }) }))
    steps.push(step(300, function () { session.enter("live", session.text, session.committed) }))
    speak(steps, words, t.before, words.length)
    steps.push(step(900, function () {
      session.voice = "off"
      session.enter("finalizing", session.text, session.committed)
    }))
    steps.push(step(1500, function () { session.latched = false; session.enter("hidden") }))
    return steps
  }

  // paste-last landing again, then Teach learning a word.
  function sceneFlashes() {
    return [
      step(1800, function () { session.replayFlash(Scripts.replay, true) }),
      step(2800, function () { session.teachFlash(Scripts.taught.heard, Scripts.taught.written) })
    ]
  }

  function sceneSteps(index) {
    switch (index) {
    case 1: return sceneTidy()
    case 2: return scenePaused()
    case 3: return sceneFlashes()
    default: return scenePlain()
    }
  }

  function replay() {
    loop.stop()
    voice = "off"
    latched = false
    enter("hidden")
    scene = 0
    script = sceneSteps(0)
    cursor = 0
    loop.interval = 600
    if (playing) loop.start()
  }

  onPlayingChanged: {
    if (playing) replay()
    else {
      loop.stop()
      voice = "off"
      latched = false
      enter("hidden")
    }
  }

  Timer {
    id: loop
    interval: 600
    onTriggered: session.advance()
  }

  function advance() {
    if (cursor >= script.length) {
      scene = (scene + 1) % sceneCount
      script = sceneSteps(scene)
      cursor = 0
    }
    var next = script[cursor]
    cursor += 1
    next.run()
    loop.interval = Math.max(1, next.wait)
    if (playing) loop.start()
  }
}
