import QtQuick
import "HudGeometry.js" as Geometry

// Talkify's own HUD, unchanged: the black shape growing down from the top
// edge under the bar (DictationShell). It used to be a surface of its own;
// now it is drawn in the same frame at the top centre of the shared HUD
// surface, so it looks and moves exactly as before.
Item {
  id: placement

  property var stage: null
  property real dpr: 1
  property string fontFamily: ""

  readonly property var frame: Geometry.windowSize(width, stage.sessionHousing, stage.settings.scale)

  DictationShell {
    x: Math.round((placement.width - width) / 2)
    y: 0
    width: placement.frame.width
    height: placement.frame.height
    stage: placement.stage
    dpr: placement.dpr
    fontFamily: placement.fontFamily
  }
}
