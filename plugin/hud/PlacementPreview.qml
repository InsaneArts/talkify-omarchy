import QtQuick
import qs.Commons

// One placement playing on a mock display, for Settings: the same placement
// components the HUD draws, fed by a scripted session, on a 1600×900 screen
// scaled to this item's width. `placement` empty shows the current pick.
Item {
  id: preview

  property var session: null
  property string placement: ""
  property real dpr: 1
  property string fontFamily: Style.font.family
  // The theme's colours (ThemePalette), shared by every preview on the page.
  property var themePalette: null

  readonly property real factor: width / mock.width
  // Antialiasing in the shaders is measured in device pixels, which the
  // scaling shrinks.
  readonly property real effectiveDpr: dpr * factor
  readonly property string shown: previewStage.settings.placement

  implicitHeight: width * mock.height / mock.width
  clip: true

  HudStage {
    id: previewStage
    service: preview.session
    housingHeight: mock.barHeight
    overrides: preview.placement !== "" ? ({ "hud.placement": preview.placement }) : ({})
    themePalette: preview.themePalette
  }

  Item {
    width: mock.width
    height: mock.height
    scale: preview.factor
    transformOrigin: Item.TopLeft

    MockScreen {
      id: mock
      showPointer: preview.shown === "pointer"
      ghostHidden: preview.shown === "island" && island.visible
    }

    IslandPill {
      id: island
      visible: preview.shown === "island" && implicitWidth > slotWidth + 0.5
      x: mock.ghostSlot.x + 7 - width / 2
      y: 0
      stage: previewStage
      active: preview.shown === "island"
      barHeight: mock.barHeight
      slotWidth: 27
      dpr: preview.effectiveDpr
      fontFamily: preview.fontFamily
    }

    Loader {
      anchors.fill: parent
      active: preview.shown !== "island"
      visible: previewStage.mounted
      sourceComponent: {
        switch (preview.shown) {
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
        stage: previewStage
        dpr: preview.effectiveDpr
        fontFamily: preview.fontFamily
      }
    }
    Component {
      id: pill
      PillPlacement {
        stage: previewStage
        dpr: preview.effectiveDpr
        fontFamily: preview.fontFamily
        bottomMargin: 40
      }
    }
    Component {
      id: caption
      WindowPlacement {
        stage: previewStage
        dpr: preview.effectiveDpr
        fontFamily: preview.fontFamily
        target: mock.windowRect
      }
    }
    Component {
      id: halo
      HaloPlacement {
        stage: previewStage
        dpr: preview.effectiveDpr
        fontFamily: preview.fontFamily
        target: mock.windowRect
        windowRadius: Math.max(Style.cornerRadius, 4)
      }
    }
    Component {
      id: dot
      PointerPlacement {
        stage: previewStage
        dpr: preview.effectiveDpr
        fontFamily: preview.fontFamily
        pointer: mock.pointerAt
      }
    }
  }
}
