import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "hud"
import "hud/HudGeometry.js" as Geometry

// The Direct Dictation HUD, in whichever place the user picked:
// - pill: a small capsule at the bottom centre (the default);
// - window: a caption on the window the session started in;
// - halo: Edge Glow around that window;
// - island: the bar's ghost widening into a pill (drawn by BarWidget.qml);
// - pointer: a dot beside the mouse pointer;
// - notch: Talkify's own shape growing from the top edge under the bar.
// Each placement lives in hud/; this file only decides which one draws,
// where, and on which display.
//
// One overlay surface per display, mapped for as long as the shell runs:
// Hyprland fades a layer surface in each time it maps, which would wash out
// every reveal. Idle, a surface is one transparent pixel; for a session it
// grows to cover its display, with an empty input region so it never takes
// a click, and every placement is just a position inside it. Once a shape
// has retracted nothing on it animates.
Item {
  id: root

  property var shell: null
  property var service: null

  readonly property string pluginId: "tornikegomareli.talkify"
  property var foundService: null
  readonly property var talkify: service || foundService

  // The shell injects `service` when it has loaded one; if this panel loaded
  // first, ask for it until it exists.
  Timer {
    interval: 1000
    repeat: true
    running: !root.service && !root.foundService
    triggeredOnStart: true
    onTriggered: {
      if (root.shell && typeof root.shell.serviceFor === "function")
        root.foundService = root.shell.serviceFor(root.pluginId)
    }
  }

  readonly property var bar: shell && shell.bar ? shell.bar : null
  readonly property bool barAtTop: !bar || (bar.barHidden !== true && (!bar.position || bar.position === "top"))
  readonly property bool barAtBottom: !!bar && bar.barHidden !== true && bar.position === "bottom"
  readonly property real barSize: {
    var size = bar ? Number(bar.barSize) || 0 : 0
    return size > 0 ? size : Style.bar.sizeHorizontal
  }

  // The notch's housing band: the top bar's height, so its content starts
  // below the bar. With the bar hidden or on another edge there is nothing to
  // clear, and the band falls back to Talkify's simulated notch, 32 points.
  readonly property real housingHeight: barAtTop ? barSize : 32

  // The colours: the current Omarchy theme's, read and kept current here
  // (hud.colors picks between them and Talkify's own). The harness points
  // `themePath` at a stock theme to preview it without switching themes.
  property string themePath: ""
  ThemePalette {
    id: themePalette
    path: root.themePath !== "" ? root.themePath : Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    followShell: root.themePath === ""
  }

  readonly property string fontFamily: {
    var family = String(hudStage.setting("hud.font", ""))
    return family.length > 0 ? family : Style.font.family
  }
  // The pill keeps Omarchy's spacing from the bottom edge, and clears a
  // bottom bar.
  readonly property real pillMargin: Style.space(40) + (barAtBottom ? barSize : 0)

  HudStage {
    id: hudStage
    service: root.talkify
    housingHeight: root.housingHeight
    surfaceReady: root.surfaceReady
    themePalette: themePalette
  }

  // Where this session draws, decided when a shape mounts: the pick, or the
  // pill when the pick has nothing to stand on (no window, a window too small
  // for a caption, no bar at the top for the island).
  property string placement: "pill"
  property string wanted: "pill"

  function decide() {
    wanted = hudStage.settings.placement
    if (wanted === "window" || wanted === "halo") windows.capture()
    if (wanted === "pointer") pointer.request()
    resolve()
  }

  function resolve() {
    switch (wanted) {
    case "island":
      placement = barAtTop ? "island" : "pill"
      break
    case "window":
      placement = !windows.settled || windows.fitsCaption ? "window" : "pill"
      break
    case "halo":
      placement = !windows.settled || windows.valid ? "halo" : "pill"
      break
    default:
      placement = wanted
    }
  }

  Connections {
    target: hudStage
    function onMountSerialChanged() { root.decide() }
  }

  WindowTracker {
    id: windows
    running: hudStage.mounted && (root.placement === "window" || root.placement === "halo")
    readonly property bool fitsCaption: valid && Geometry.windowFitsCaption(rect, 36)
    onSettledChanged: if (settled && hudStage.mounted) root.resolve()
  }

  PointerTracker {
    id: pointer
    running: hudStage.mounted && root.placement === "pointer"
  }

  readonly property var holder: {
    var list = surfaces.instances
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].holdsShape) return list[i]
    }
    return null
  }
  readonly property bool surfaceReady: {
    if (placement === "island") return true
    if ((wanted === "window" || wanted === "halo") && !windows.settled) return false
    if (placement === "pointer" && !pointer.valid) return false
    return !!holder && holder.sized
  }

  Variants {
    id: surfaces
    model: Quickshell.screens

    PanelWindow {
      id: window

      required property var modelData
      readonly property bool holdsShape: hudStage.screenName === modelData.name
      readonly property bool drawing: holdsShape && hudStage.mounted && root.placement !== "island"
      readonly property bool sized: width >= modelData.width - 1 && height >= modelData.height - 1

      screen: modelData
      anchors.top: true
      anchors.left: true
      implicitWidth: drawing ? modelData.width : 1
      implicitHeight: drawing ? modelData.height : 1
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "talkify-hud"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      // Visual only: an empty input region, so the HUD never takes a click.
      mask: Region {}

      // The target window and the pointer in this display's coordinates.
      readonly property rect localWindow: Qt.rect(windows.rect.x - modelData.x, windows.rect.y - modelData.y,
        windows.rect.width, windows.rect.height)
      readonly property point localPointer: Qt.point(pointer.pointerX - modelData.x, pointer.pointerY - modelData.y)
      readonly property bool pointerHere: pointer.valid && localPointer.x >= 0 && localPointer.y >= 0
        && localPointer.x < modelData.width && localPointer.y < modelData.height
      // It follows the pointer only while the pointer is on this display.
      property point lastPointer: Qt.point(modelData.width / 2, modelData.height / 2)
      function followPointer() {
        if (pointerHere) lastPointer = localPointer
      }
      onLocalPointerChanged: followPointer()
      onPointerHereChanged: followPointer()

      Loader {
        anchors.fill: parent
        // Built when this display first holds a shape and kept while it does.
        active: window.holdsShape && root.placement !== "island"
        visible: window.drawing
        sourceComponent: {
          switch (root.placement) {
          case "notch": return notch
          case "window": return caption
          case "halo": return halo
          case "pointer": return dot
          default: return pill
          }
        }
      }

      Component {
        id: notch
        NotchPlacement {
          stage: hudStage
          dpr: window.devicePixelRatio
          fontFamily: root.fontFamily
        }
      }
      Component {
        id: pill
        PillPlacement {
          stage: hudStage
          dpr: window.devicePixelRatio
          fontFamily: root.fontFamily
          bottomMargin: root.pillMargin
        }
      }
      Component {
        id: caption
        WindowPlacement {
          stage: hudStage
          dpr: window.devicePixelRatio
          fontFamily: root.fontFamily
          target: window.localWindow
        }
      }
      Component {
        id: halo
        HaloPlacement {
          stage: hudStage
          dpr: window.devicePixelRatio
          fontFamily: root.fontFamily
          target: windows.fullscreen ? Qt.rect(0, 0, window.modelData.width, window.modelData.height) : window.localWindow
          fullscreen: windows.fullscreen
          windowRadius: Style.cornerRadius
        }
      }
      Component {
        id: dot
        PointerPlacement {
          stage: hudStage
          dpr: window.devicePixelRatio
          fontFamily: root.fontFamily
          pointer: window.lastPointer
        }
      }
    }
  }
}
