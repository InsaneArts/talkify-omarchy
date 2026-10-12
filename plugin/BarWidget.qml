import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "hud"
import "settings"
import "settings/Format.js" as Format
import "settings/IpcOwner.js" as IpcOwner

// The ghost in the bar. It mirrors the session the way Talkify's menu bar
// icon does: it pulses between full and dim in the accent while recording,
// fills from the bottom like a battery while the Speech Model downloads, and
// dims when the daemon is not there. Here it also floats with the voice, so
// the bar shows that it is hearing you even with the HUD on another screen.
// Left click opens the settings on Recent; right click starts or finishes a
// session.
//
// Outside a session it reacts, once each time and then holds still: a hop
// and a few sparkles for a milestone reached for the first time, a rewind
// blink when a past dictation is pasted again, a nod when Teach learns a
// word.
//
// With the HUD placed in the bar ("island"), the ghost widens into a black
// pill inside the bar for the session, on the display the session started
// on, and shrinks back to the ghost when it ends (hud/IslandPill.qml).
Panel {
  id: root
  moduleName: "tornikegomareli.talkify"
  ipcTarget: "tornikegomareli.talkify"
  manageIpc: false

  readonly property var svc: bar && bar.shell ? bar.shell.serviceFor("tornikegomareli.talkify") : null
  readonly property bool connected: !!svc && svc.connected
  readonly property bool recording: connected && svc.recording
  readonly property bool finalizing: connected && svc.phase === "finalizing"
  readonly property bool modelBusy: connected
    && (svc.engineStatus === "downloading" || svc.engineStatus === "loading")
  readonly property bool modelFailed: connected
    && (svc.engineStatus === "failed" || svc.engineStatus === "missing")
  // No session anywhere: the only time the ghost may celebrate.
  readonly property bool idle: connected && !svc.recording && svc.phase === "hidden"
  // Talkify's dead-microphone amber: a microphone that stopped delivering
  // must not look like a quiet room.
  readonly property color deadMicAmber: Qt.rgba(1.0, 0.6, 0.16, 1)

  property bool blinkDimmed: false

  readonly property color ghostColor: {
    if (recording && !svc.micAlive) return deadMicAmber
    // A paused session holds still in the theme's muted colour, like the HUD.
    if (recording && svc.paused) return Color.muted
    if (recording || finalizing) return Color.accent
    if (modelFailed) return Color.urgent
    return root.barForeground
  }

  // The theme's own colours for the sparks, so a celebration matches the
  // HUD's glow.
  readonly property var sparkColors: {
    var list = islandTheme.look && islandTheme.look.particles ? islandTheme.look.particles : []
    var out = []
    for (var i = 0; i < list.length; i++) out.push(Qt.rgba(list[i][0], list[i][1], list[i][2], 1))
    return out.length ? out : [Color.accent]
  }

  // The island's own session state, read the way the HUD reads it, so both
  // agree on which display holds the session.
  HudStage {
    id: islandStage
    service: root.svc
    housingHeight: root.barSize
    themePalette: islandTheme
  }

  ThemePalette {
    id: islandTheme
  }

  readonly property real barSize: root.bar && root.bar.barSize > 0 ? root.bar.barSize : Style.bar.sizeHorizontal
  readonly property bool barAtTop: !!root.bar && root.bar.barHidden !== true
    && (!root.bar.position || root.bar.position === "top")
  readonly property string screenName: {
    var window = button.QsWindow.window
    return window && window.screen ? String(window.screen.name) : ""
  }
  readonly property bool islandHere: islandStage.settings.placement === "island" && barAtTop
    && islandStage.screenName === root.screenName

  implicitWidth: island.visible ? Math.max(button.implicitWidth, island.implicitWidth) : button.implicitWidth
  implicitHeight: button.implicitHeight

  // The page the menu opens on: Recent, unless openAt asked for another.
  property string nextSection: "recent"
  onOpenedChanged: {
    if (!opened) return
    settings.show(nextSection)
    nextSection = "recent"
  }

  function openAt(section) {
    if (opened) settings.show(section)
    else {
      nextSection = section
      open()
    }
  }

  // The instance on the focused monitor, which is where a keyboard-summoned
  // menu belongs; the IPC target only ever reaches one instance.
  function focusedInstance() {
    var item = root.bar && typeof root.bar.findPanelWidget === "function"
      ? root.bar.findPanelWidget(root.moduleName) : null
    return item && typeof item.openAt === "function" ? item : root
  }

  property bool ownsIpc: false
  function claimIpc() { Qt.callLater(function() { root.ownsIpc = true }) }
  Component.onCompleted: ownsIpc = IpcOwner.join(root.moduleName, root)
  Component.onDestruction: {
    var next = IpcOwner.leave(root.moduleName, root)
    if (next && next !== root) next.claimIpc()
  }

  IpcHandler {
    enabled: root.ownsIpc
    target: "tornikegomareli.talkify"
    function open(): void { root.focusedInstance().openAt("recent") }
    function close(): void { root.broadcast("close") }
    function toggle(): void {
      var item = root.focusedInstance()
      if (item.opened) item.close()
      else item.openAt("recent")
    }
    // Opens on one page, e.g. `omarchy-shell tornikegomareli.talkify openAt
    // insights`: recent, dictation, trigger, appearance, vocabulary, apps,
    // sounds, insights or model.
    function openAt(section: string): void { root.focusedInstance().openAt(section) }
    function connect(): void { if (root.svc) root.svc.connect() }
    function disconnect(): void { if (root.svc) root.svc.disconnect() }
    function toggleConnect(): void { if (root.svc) root.svc.toggleConnect() }
  }

  Timer {
    interval: 450
    repeat: true
    running: root.recording && !root.finalizing && root.svc.micAlive && !root.svc.paused
    onRunningChanged: if (!running) root.blinkDimmed = false
    onTriggered: root.blinkDimmed = !root.blinkDimmed
  }

  signal celebrateRequested()
  signal rewindRequested()
  signal nodRequested()

  // A milestone usually arrives as a session ends, so it waits for the HUD
  // to be gone and a beat more: never during a session.
  property string pendingMilestone: ""
  property string milestoneText: ""

  Connections {
    target: root.svc
    ignoreUnknownSignals: true
    function onMilestoneEpochChanged() {
      var m = root.svc.milestone
      if (!m) return
      root.pendingMilestone = Format.milestone(m.kind, m.value)
      if (root.idle) celebrateDelay.restart()
    }
    function onReplayEpochChanged() { if (!root.recording) root.rewindRequested() }
    function onTaughtEpochChanged() { if (!root.recording) root.nodRequested() }
  }

  onIdleChanged: {
    if (idle && pendingMilestone !== "") celebrateDelay.restart()
    else if (!idle) celebrateDelay.stop()
  }

  Timer {
    id: celebrateDelay
    interval: 700
    onTriggered: {
      if (!root.idle || root.pendingMilestone === "") return
      root.milestoneText = root.pendingMilestone
      root.pendingMilestone = ""
      root.celebrateRequested()
      milestoneTooltip.restart()
    }
  }

  // The tooltip says what was reached for a while after, for whoever hovers
  // to see why the ghost hopped.
  Timer {
    id: milestoneTooltip
    interval: 10000
    onTriggered: root.milestoneText = ""
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.opened ? "" : (root.milestoneText !== "" ? "Talkify · " + root.milestoneText : (!root.connected ? "Talkify · Disconnected" : "Talkify"))
    dimmed: !root.connected
    onPressed: function(b) {
      if (b === Qt.MiddleButton) {
        if (root.svc) root.svc.toggleConnect()
      } else if (b === Qt.RightButton) {
        if (root.connected) root.svc.toggle()
        else if (root.svc) root.svc.connect()
      } else {
        root.toggle()
      }
    }

    iconComponent: Component {
      Item {
        BarGhost {
          id: ghost
          anchors.fill: parent
          // Float with the voice: up to two pixels at full level.
          rise: root.recording ? 2 * root.svc.level : 0
          color: root.ghostColor
          // The island draws its own ghost while it is open.
          baseOpacity: island.visible ? 0 : (root.blinkDimmed ? 0.4 : (root.connected ? 1 : 0.5))
          fill: root.modelBusy && root.svc.engineStatus === "downloading" ? root.svc.engineProgress : 1
          sparkColors: root.sparkColors

          Behavior on rise { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
          Behavior on baseOpacity { NumberAnimation { duration: 180 } }
          Behavior on color { ColorAnimation { duration: 160 } }
        }

        Connections {
          target: root
          function onCelebrateRequested() { ghost.celebrate() }
          function onRewindRequested() { ghost.rewind() }
          function onNodRequested() { ghost.nod() }
        }
      }
    }
  }

  IslandPill {
    id: island
    anchors.verticalCenter: parent.verticalCenter
    anchors.horizontalCenter: parent.horizontalCenter
    stage: islandStage
    active: root.islandHere
    barHeight: root.barSize
    slotWidth: button.implicitWidth
    dpr: button.QsWindow.window ? button.QsWindow.window.devicePixelRatio : 1
    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: settings
    // The Appearance page carries live previews and needs the room; the
    // other pages scroll past a comfortable height instead of growing to
    // the screen's.
    contentWidth: panel.fittedContentWidth(Style.space(settings.wide ? 920 : 680))
    contentHeight: panel.fittedContentHeight(settings.wide
      ? Math.max(Style.space(440), settings.implicitHeight)
      : Math.min(Style.space(720), Math.max(Style.space(520), settings.implicitHeight)))

    TalkifySettings {
      id: settings
      anchors.fill: parent
      focus: true
      svc: root.svc
      bar: root.bar
      active: root.opened
      fg: root.bar ? root.bar.foreground : Color.foreground
      fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
      onCloseRequested: root.close()
    }
  }

  // Run `method` on every instance: close means the menu wherever it is.
  function broadcast(method) {
    var items = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(moduleName) : [root]
    if (items.length === 0) items = [root]
    for (var i = 0; i < items.length; i++) {
      if (items[i] && typeof items[i][method] === "function") items[i][method]()
    }
  }
}
