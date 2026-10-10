import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "settings"

// Preview harness for the Settings menu and the bar ghost, fed by fixtures
// (FixtureService.qml) instead of the daemon:
//
//   quickshell -p plugin/settings-dev
//
// Environment:
//   SETTINGS_SECTION=insights   the page to open on (default recent)
//   SETTINGS_EMPTY=1            empty fixtures: the first-run states
//   SETTINGS_THEME=path         read that colors.toml instead of the current
//                               theme, e.g. /usr/share/omarchy/themes/flexoki-light/colors.toml
//   SETTINGS_SCREEN=name        the output to draw on (default: HEADLESS-1
//                               when there is one, so the desk stays clear;
//                               else the focused one)
//
// While it runs, `quickshell ipc -p plugin/settings-dev call settingsDev <fn>`:
// section <name>, scroll <y>, shot <file> (grim of the output it draws on),
// celebrate, rewind, nod, celebrateShot <file> <ms>, empty <bool>,
// page <property> <json>, call <function> <json>.
ShellRoot {
  id: root

  readonly property string themePath: Quickshell.env("SETTINGS_THEME") || ""

  FixtureService {
    id: fixtures
    empty: Quickshell.env("SETTINGS_EMPTY") === "1"
  }

  // A stock theme's colours, poured into the shell's own Color so every
  // kit control follows them, as a theme switch would.
  FileView {
    path: root.themePath
    printErrors: false
    onLoaded: {
      Color.loadColors(text())
      Color.loadShell("")
    }
  }

  readonly property var screen: {
    var wanted = Quickshell.env("SETTINGS_SCREEN") || ""
    var screens = Quickshell.screens
    var focused = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
    var pick = null
    for (var i = 0; i < screens.length; i++) {
      if (wanted !== "" && screens[i].name === wanted) return screens[i]
      if (wanted === "" && screens[i].name.indexOf("HEADLESS") === 0) pick = screens[i]
      if (!pick && screens[i].name === focused) pick = screens[i]
    }
    return pick || (screens.length ? screens[0] : null)
  }

  function shot(file) {
    if (root.screen) Quickshell.execDetached(["grim", "-o", root.screen.name, file])
  }

  PanelWindow {
    id: window
    screen: root.screen
    anchors.top: true
    anchors.right: true
    margins.top: Style.bar.sizeHorizontal + 12
    margins.right: 24
    implicitWidth: card.width
    implicitHeight: card.height
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "talkify-settings-dev"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"

    // The KeyboardPanel card, as the bar draws it.
    BorderSurface {
      id: card
      readonly property real inset: Style.spacing.popupPadding
      width: Style.space(settings.wide ? 920 : 680) + inset * 2 + borderLeft + borderRight
      // As BarWidget sizes the panel, and held inside the output as
      // KeyboardPanel holds it.
      height: Math.min(root.screen ? root.screen.height - Style.bar.sizeHorizontal - 36 : 100000,
        (settings.wide
          ? Math.max(Style.space(440), settings.implicitHeight)
          : Math.min(Style.space(720), Math.max(Style.space(520), settings.implicitHeight)))
        + inset * 2 + borderTop + borderBottom)
      // Opaque: the real panel is blurred by Hyprland, this namespace is not.
      color: Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b, 1)
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      padding: inset
      radius: Style.cornerRadius

      TalkifySettings {
        id: settings
        x: card.contentLeftInset
        y: card.contentTopInset
        width: card.width - card.contentLeftInset - card.contentRightInset
        height: card.height - card.contentTopInset - card.contentBottomInset
        svc: fixtures
        section: Quickshell.env("SETTINGS_SECTION") || "recent"
        active: true
        fg: Color.foreground
      }
    }
  }

  // A stand-in bar strip with the ghost, for its reactions.
  PanelWindow {
    screen: root.screen
    anchors.top: true
    anchors.left: true
    margins.top: Style.bar.sizeHorizontal + 12
    margins.left: 24
    implicitWidth: 220
    implicitHeight: Style.bar.sizeHorizontal + 16
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "talkify-settings-dev-bar"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"

    Rectangle {
      anchors.fill: parent
      color: Color.bar.background
      radius: Style.cornerRadius

      Row {
        anchors.centerIn: parent
        spacing: 26

        Repeater {
          model: 3
          delegate: Item {
            required property int index
            width: Style.bar.iconSlot
            height: Style.bar.sizeHorizontal

            BarGhost {
              id: ghost
              anchors.centerIn: parent
              width: Style.bar.iconCanvas
              height: Style.bar.iconCanvas
              color: Color.bar.text
              sparkColors: [Color.accent, Color.foreground, Color.urgent]
            }

            Connections {
              target: root
              function onCelebrate() { if (index === 0) ghost.celebrate() }
              function onRewind() { if (index === 1) ghost.rewind() }
              function onNod() { if (index === 2) ghost.nod() }
            }
          }
        }
      }
    }
  }

  signal celebrate()
  signal rewind()
  signal nod()

  Timer {
    id: delayedShot
    property string file: ""
    onTriggered: root.shot(file)
  }

  IpcHandler {
    target: "settingsDev"

    function section(name: string): string {
      settings.show(name)
      return settings.section
    }
    function scroll(y: real): string {
      settings.scrollTo(y)
      return "ok"
    }
    function shot(file: string): string {
      root.shot(file)
      return "ok"
    }
    function celebrateShot(file: string, ms: int): string {
      root.celebrate()
      root.rewind()
      root.nod()
      delayedShot.file = file
      delayedShot.interval = ms
      delayedShot.restart()
      return "ok"
    }
    function empty(on: bool): string {
      fixtures.empty = on
      fixtures.history = on ? [] : fixtures.history
      fixtures.vocab = on ? [] : fixtures.vocab
      fixtures.insights = on ? null : fixtures.buildInsights()
      return "ok"
    }
    // Pokes the open page, for states only a click reaches: `page expanded
    // '"terminal"'` opens an App rule; `call <function> <json>` runs one of
    // the page's functions with that argument.
    function page(name: string, json: string): string {
      settings.currentPage[name] = JSON.parse(json)
      return "ok"
    }
    function call(name: string, json: string): string {
      settings.currentPage[name](JSON.parse(json))
      return "ok"
    }
  }
}
