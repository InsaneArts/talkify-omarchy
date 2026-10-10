import QtQuick
import Quickshell

// A stand-in for Service.qml with every event's state filled from fixtures,
// so each Settings page can be seen full, empty, or in its awkward states
// without the daemon. Commands change the fixtures the way the daemon
// would answer them, and log what a real service would have sent.
Item {
  id: svc

  // Empty fixtures: the first-run states.
  property bool empty: false

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
  property var levelHistory: []
  property bool micAlive: true
  property bool paused: false
  property string rule: ""
  property var marks: []
  property var lastResult: null
  property var replayed: null
  property int replayEpoch: 0
  property var taught: empty ? null : { heard: "omachi", written: "Omarchy" }
  property int taughtEpoch: 0
  property var milestone: null
  property int milestoneEpoch: 0

  property var config: ({
    trigger: { key: "KEY_RIGHTMETA", chord_guard_ms: 150, preroll: true },
    engine: { model: "parakeet-tdt-0.6b-v3-int8", live_draft: true, no_speech_timeout_ms: 0 },
    insertion: { destination: "insert", method: "paste", live: false, live_pause_ms: 600, trailing_space: true },
    tidy: { enabled: true, fillers: true, stutters: true, spoken_punctuation: true, scratch: true, send_phrases: "send it, press enter" },
    vocab: { enabled: true, fuzzy: true },
    media: { mode: "pause", duck_to: 0.3 },
    history: { size: 20, save: false },
    insights: { enabled: true, typing_wpm: 40 },
    sounds: { enabled: true, set: "synth8", volume: 0.5 },
    hud: { visual: "waveform", waveform_style: "chart-line", reveal: "slide", long_draft: "grow-down", scale: 1.0, placement: "pill", words: "auto", glow_palette: "spectrum" },
    apps: {
      terminal: { final_period: false, send: "spoken" },
      "com.mitchellh.ghostty": { case: "lower" }
    }
  })

  readonly property real nowSeconds: Date.now() / 1000

  property var history: empty ? [] : [
    { id: 41, at: nowSeconds - 50, app: "kitty", text: "run the tests and fix whatever breaks in the session machine", raw: "run the tests and uh fix whatever breaks in the the session machine send it", words: 11, seconds: 4.2, inserted: true, retryable: true, rule: "terminal" },
    { id: 40, at: nowSeconds - 60 * 7, app: "zen", text: "Thanks for the notes on the HUD. I moved the island into the bar and kept the pill as the default, so nothing changes unless you pick it.", raw: "thanks for the notes on the hud comma I moved the island into the bar and kept the pill as the default comma so nothing changes unless you pick it period", words: 28, seconds: 9.8, inserted: true, retryable: true },
    { id: 39, at: nowSeconds - 60 * 42, app: "Slack", text: "On my way, five minutes.", raw: "on my way five minutes", words: 5, seconds: 1.9, inserted: false, retryable: false },
    { id: 38, at: nowSeconds - 3600 * 3, app: "org.gnome.Nautilus", text: "Screenshots from the HUD review", raw: "screenshots from the hud review", words: 5, seconds: 2.1, inserted: true, retryable: false },
    { id: 37, at: nowSeconds - 86400 - 3600, app: "code", text: "Hyprland window rules for the picture in picture player", raw: "hyperland window rules for the picture in picture player", words: 9, seconds: 3.1, inserted: true, retryable: false }
  ]

  property var vocab: empty ? [] : [
    { line: "Hyprland", kind: "word", hits: 14 },
    { line: "Quickshell", kind: "word", hits: 3 },
    { line: "omachi -> Omarchy", kind: "replacement", hits: 22 },
    { line: "para key -> Parakeet", kind: "replacement", hits: 0 },
    { line: "my email => tornike@example.com", kind: "snippet", hits: 5 }
  ]
  property string vocabPath: Quickshell.env("HOME") + "/.config/talkify/words.txt"
  property var insights: empty ? null : buildInsights()

  // Sixteen weeks ending this week, Monday first; quieter weekends and a
  // rising trend, so the heatmap's ramp shows its whole range.
  function buildInsights() {
    var today = new Date()
    today.setHours(0, 0, 0, 0)
    var monday = new Date(today)
    monday.setDate(today.getDate() - ((today.getDay() + 6) % 7) - 15 * 7)
    var days = []
    var seed = 7
    function random() {
      seed = (seed * 9301 + 49297) % 233280
      return seed / 233280
    }
    var todayWords = 0
    for (var i = 0; i < 16 * 7; i++) {
      var date = new Date(monday)
      date.setDate(monday.getDate() + i)
      var future = date > today
      var weekend = i % 7 >= 5
      var r = random()
      var words = future || r < (weekend ? 0.6 : 0.18) ? 0 : Math.round((200 + 1400 * random()) * (0.4 + i / 112))
      if (date.getTime() === today.getTime()) { words = 820; todayWords = words }
      var iso = date.getFullYear() + "-" + String(date.getMonth() + 1).padStart(2, "0") + "-" + String(date.getDate()).padStart(2, "0")
      days.push({ day: iso, words: words, future: future })
    }
    return {
      total_words: 12840, sessions: 412, speaking_seconds: 5460.0,
      wpm: 141.1, words_per_session: 31.2,
      current_streak: 6, longest_streak: 11,
      today_words: todayWords,
      momentum: { current_words: 4210, previous_words: 3020, active_days: 6, sessions: 120, change: 0.394 },
      heatmap: days,
      typing_wpm: config.insights.typing_wpm,
      minutes_saved: 182.4,
      milestones: [{ kind: "words", value: 1000 }, { kind: "words", value: 10000 }, { kind: "streak", value: 7 }, { kind: "sessions", value: 100 }]
    }
  }

  function setting(path, fallback) {
    var parts = path.split(".")
    var node = config
    for (var i = 0; i < parts.length; i++) {
      if (!node || node[parts[i]] === undefined) return fallback
      node = node[parts[i]]
    }
    return node
  }

  function log(what) { console.log("fixture:", what) }

  function set(key, value) {
    log("set " + key + " " + JSON.stringify(value))
    var next = JSON.parse(JSON.stringify(config))
    if (key.indexOf("apps.") === 0) {
      // The class is everything between "apps." and the last dot.
      var rest = key.slice(5)
      var dot = rest.lastIndexOf(".")
      var cls = rest.slice(0, dot)
      var field = rest.slice(dot + 1)
      var rule = next.apps[cls] || {}
      if (value === "") delete rule[field]
      else rule[field] = value
      if (Object.keys(rule).length) next.apps[cls] = rule
      else delete next.apps[cls]
    } else {
      var parts = key.split(".")
      if (!next[parts[0]]) next[parts[0]] = {}
      next[parts[0]][parts[1]] = value
    }
    config = next
  }

  function toggle() { log("toggle") }
  function cancel() { log("cancel") }
  function pause() { log("pause") }
  function loadModel() { log("load-model") }
  function teach() { log("teach") }
  function pasteLast(index, raw) {
    log("paste-last " + index + (raw ? " --raw" : ""))
    replayed = { text: history[index] ? history[index].text : "", inserted: true, note: "" }
    replayEpoch += 1
  }
  function copyLast(index, raw) { log("copy-last " + index + (raw ? " --raw" : "")) }
  function retry(index) { log("retry " + index) }
  function vocabAdd(line) {
    log("vocab add " + line)
    var kind = line.indexOf("=>") >= 0 ? "snippet" : line.indexOf("->") >= 0 ? "replacement" : "word"
    vocab = vocab.concat([{ line: line, kind: kind, hits: 0 }])
  }
  function vocabRemove(line) {
    log("vocab remove " + line)
    vocab = vocab.filter(function(e) { return e.line !== line })
  }
  function clearHistory() {
    log("history-clear")
    history = []
  }
}
