import QtQuick
import Quickshell
import Quickshell.Io

// The one connection to the talkify daemon. It runs `talkify watch`, keeps
// every event's latest state as a property, and sends commands. The HUD and
// the bar widget only read from here, so there is a single stream however
// many monitors draw a bar.
Item {
  id: root

  property var shell: null

  readonly property string binary: Quickshell.env("HOME") + "/.local/bin/talkify"
  // Talkify's waveform keeps this many bars of history.
  readonly property int barCount: 56

  property bool connected: false
  // "keyboard" when the daemon reads the trigger itself, "commands" when it
  // needs compositor binds (no input group).
  property string trigger: "keyboard"
  property var config: ({})

  property string engineStatus: "loading"
  property string engineDetail: ""
  property real engineProgress: 0

  property bool recording: false
  // hidden | listening | live | finalizing | message
  property string phase: "hidden"
  property bool latched: false
  property string text: ""
  // The start of `text` live insertion has already put in the window; the
  // rest is still a draft that can change.
  property string committed: ""
  // Bumped when a session starts listening, so visuals reset to a silent
  // baseline instead of carrying the last session's tail.
  property int sessionEpoch: 0

  // 0–1, fast attack and slow release, for anything that pulses.
  property real level: 0
  // The last barCount raw-ish levels, newest last, for the waveform.
  property var levelHistory: emptyHistory()
  // False once buffers stop arriving: a dead microphone, which must look
  // different from silence.
  property bool micAlive: true

  // The latched session is paused: the mic is open but nothing is kept.
  property bool paused: false
  // The App rules in force ("terminal", a window class), or "".
  property string rule: ""
  // {start, end, kind} over `text` (UTF-16 offsets): filler, scratched,
  // punctuation, vocabulary, send. What the Tidy pass and the vocabulary
  // will do to the draft, so the HUD can show it before the text lands.
  property var marks: []

  // {text, inserted, note, raw, sent, rule}. Sent before the HUD is told to
  // hide. raw: what the Speech Model heard.
  property var lastResult: null
  // Bumped with each paste-last or retry, {text, inserted, note}.
  property var replayed: null
  property int replayEpoch: 0
  // Recent dictations, newest first: {id, at, app, text, raw, words,
  // seconds, inserted, retryable, rule}.
  property var history: []
  // The vocabulary file: entries {line, kind, hits} and its path.
  property var vocab: []
  property string vocabPath: ""
  // The last correction Teach learned, {heard, written}, and a counter so
  // the same correction twice still reacts.
  property var taught: null
  property int taughtEpoch: 0
  // The Insights snapshot (see docs/protocol.md).
  property var insights: null
  // The last milestone reached for the first time, {kind, value}, and a
  // counter: celebrate once per bump.
  property var milestone: null
  property int milestoneEpoch: 0

  function emptyHistory() {
    var bars = []
    for (var i = 0; i < barCount; i++) bars.push(0)
    return bars
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

  property bool userDisconnected: false
  property int retryCount: 0
  property int reconnectBackoff: 1500

  function run(args) {
    Quickshell.execDetached([root.binary].concat(args))
  }
  function command(json) { run(["raw", JSON.stringify(json)]) }
  function connect() {
    userDisconnected = false
    run(["connect"])
    retryCount = 0
    reconnectBackoff = 1000
    reconnect.restart()
  }
  function disconnect() {
    userDisconnected = true
    run(["disconnect"])
    reconnect.stop()
    connected = false
    recording = false
    phase = "hidden"
  }
  function toggleConnect() {
    if (connected) disconnect()
    else connect()
  }
  function toggle() { run(["toggle"]) }
  function cancel() { run(["cancel"]) }
  function pause() { run(["pause"]) }
  function loadModel() { run(["load-model"]) }
  function pasteLast(index, raw) { command({ cmd: "paste-last", index: index || 0, raw: !!raw }) }
  function copyLast(index, raw) { command({ cmd: "copy-last", index: index || 0, raw: !!raw }) }
  function retry(index) { command({ cmd: "retry", index: index || 0 }) }
  function teach() { run(["teach"]) }
  function vocabAdd(line) { command({ cmd: "vocab-add", line: line }) }
  function vocabRemove(line) { command({ cmd: "vocab-remove", line: line }) }
  function clearHistory() { command({ cmd: "history-clear" }) }
  function set(key, value) {
    // Optimistic, so a switch does not snap back while the daemon answers;
    // the daemon's `config` event settles it either way. App rules
    // (apps.<class>.<field>, classes with dots) wait for the daemon.
    var parts = key.split(".")
    if (parts[0] !== "apps" && parts.length === 2) {
      var next = JSON.parse(JSON.stringify(config))
      if (next[parts[0]]) next[parts[0]][parts[1]] = value
      config = next
    }
    run(["set", key, String(value)])
  }

  function handle(event) {
    switch (event.t) {
    case "hello":
      connected = true
      userDisconnected = false
      retryCount = 0
      reconnectBackoff = 1500
      trigger = event.trigger
      config = event.config
      break
    case "config":
      config = event.config
      break
    case "engine":
      engineStatus = event.status
      engineDetail = event.detail
      engineProgress = event.progress
      break
    case "recording":
      recording = event.active
      if (!event.active) level = 0
      break
    case "hud":
      if (event.phase === "listening" && phase !== "listening" && phase !== "live") {
        sessionEpoch += 1
        level = 0
        levelHistory = emptyHistory()
        micAlive = true
      }
      phase = event.phase
      latched = event.latched
      text = event.text
      committed = event.committed || ""
      paused = !!event.paused
      rule = event.rule || ""
      marks = event.marks || []
      break
    case "level":
      level = Math.max(event.level, level * 0.88)
      var bars = levelHistory.slice(1)
      var last = bars.length ? bars[bars.length - 1] : 0
      // A light EMA against the previous bar calms per-tick jitter without
      // dulling the speech rhythm.
      bars.push(0.6 * event.level + 0.4 * last)
      levelHistory = bars
      // Whether the microphone is alive is the daemon's call alone (its
      // watchdog and its muted-microphone check); a level arriving says
      // nothing, a muted microphone sends silent levels too.
      break
    case "mic":
      micAlive = event.alive
      break
    case "result":
      lastResult = {
        text: event.text, inserted: event.inserted, note: event.note,
        raw: event.raw || "", sent: !!event.sent, rule: event.rule || ""
      }
      break
    case "replayed":
      replayed = { text: event.text, inserted: event.inserted, note: event.note }
      replayEpoch += 1
      break
    case "history":
      history = event.items || []
      break
    case "vocab":
      vocab = event.entries || []
      vocabPath = event.path || ""
      break
    case "taught":
      taught = { heard: event.heard, written: event.written }
      taughtEpoch += 1
      break
    case "insights":
      insights = event.insights
      break
    case "milestone":
      milestone = { kind: event.kind, value: event.value }
      milestoneEpoch += 1
      break
    }
  }

  Process {
    id: watcher
    command: [root.binary, "watch"]
    running: true
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(line) {
        try {
          root.handle(JSON.parse(line))
        } catch (e) {
          console.warn("talkify: unreadable event", line)
        }
      }
    }
    onRunningChanged: {
      if (!running) {
        root.connected = false
        root.recording = false
        root.phase = "hidden"
        if (!root.userDisconnected) {
          reconnect.restart()
        }
      }
    }
  }

  // Follow the daemon back when it runs, with backoff to avoid CPU load when inactive.
  Timer {
    id: reconnect
    interval: root.reconnectBackoff
    onTriggered: {
      if (root.userDisconnected) return
      if (!watcher.running) {
        root.retryCount += 1
        // Back off to 10s after 3 quick attempts so an inactive daemon does not burn CPU
        if (root.retryCount > 3) {
          root.reconnectBackoff = 10000
        }
        watcher.running = true
      }
    }
  }
}
