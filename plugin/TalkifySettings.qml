import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "hud"

// Talkify's settings, opened from the bar. Every change goes to the daemon,
// which owns the one config file and answers with the new config, so this
// form only ever shows what the daemon actually holds.
//
// Appearance is drawn here; every other page lives in settings/ and is
// loaded by URL rather than imported. plugin/dev links this file into its
// harness without that folder, and a missing import would fail the whole
// menu there, where a page loaded by URL fails only if it is opened.
//
// Pages are handed this item as `ctx`: the service, the bar's colours and
// font, value()/set() over the config, and the menu's own verbs (show a
// page, confirm, act once the menu has closed, scroll).
Item {
  id: root

  required property var svc
  property QtObject bar: null
  property color fg: Color.foreground
  property string fontFamily: Style.font.family
  property string section: "recent"
  // Whether the menu is open; the Appearance previews only play while it is
  // and their section is showing.
  property bool active: true
  // The Appearance page needs a wider menu for its previews.
  readonly property bool wide: section === "appearance"
  signal closeRequested()

  readonly property real dpr: root.QsWindow.window ? root.QsWindow.window.devicePixelRatio : 1

  readonly property var sections: [
    { value: "recent", label: "Recent", page: "settings/RecentPage.qml" },
    { value: "dictation", label: "Dictation", page: "settings/DictationPage.qml" },
    { value: "trigger", label: "Trigger", page: "settings/TriggerPage.qml" },
    { value: "appearance", label: "Appearance", page: "" },
    { value: "vocabulary", label: "Vocabulary", page: "settings/VocabularyPage.qml" },
    { value: "apps", label: "App rules", page: "settings/AppsPage.qml" },
    { value: "sounds", label: "Sounds", page: "settings/SoundsPage.qml" },
    { value: "insights", label: "Insights", page: "settings/InsightsPage.qml" },
    { value: "model", label: "Speech Model", page: "settings/ModelPage.qml" }
  ]

  readonly property var placements: [
    { value: "pill", label: "Pill", blurb: "Bottom centre" },
    { value: "window", label: "Window", blurb: "On the window" },
    { value: "halo", label: "Halo", blurb: "Glow round the window" },
    { value: "island", label: "Island", blurb: "Inside the bar" },
    { value: "pointer", label: "Pointer", blurb: "By the pointer" },
    { value: "notch", label: "Notch", blurb: "From the top edge" }
  ]

  // What "Auto" means for the current pick.
  readonly property string wordsNote: {
    var placement = value("hud.placement", "pill")
    var words = value("hud.words", "auto")
    if (words === "on") return "Words show on every placement."
    if (words === "off") return "Words stay hidden; status lines still show."
    switch (placement) {
    case "pill": return "Auto: the pill shows the words unless they are already going into the window as you speak."
    case "window": return "Auto: the caption shows the words."
    case "notch": return "Auto: the voice visual decides, as on the Mac."
    default: return "Auto: no words here, only the voice and status lines."
    }
  }

  // The theme's colours, for every preview on the page.
  ThemePalette {
    id: previewTheme
  }

  // One scripted session for every preview on the page.
  PreviewSession {
    id: previewSession
    source: root.svc
    playing: root.active && root.section === "appearance" && root.visible
  }

  // A changed setting shows from the start of a session, as a real one would
  // read it.
  Connections {
    target: root.svc
    ignoreUnknownSignals: true
    function onConfigChanged() { if (previewSession.playing) previewSession.replay() }
  }

  function value(path, fallback) { return svc ? svc.setting(path, fallback) : fallback }
  function set(path, next) { if (svc) svc.set(path, next) }

  readonly property var triggerKeys: [
    { value: "KEY_RIGHTMETA", label: "Right Super" },
    { value: "KEY_RIGHTCTRL", label: "Right Ctrl" },
    { value: "KEY_RIGHTALT", label: "Right Alt" },
    { value: "KEY_F13", label: "F13" },
    { value: "BTN_SIDE", label: "Mouse back" },
    { value: "BTN_EXTRA", label: "Mouse forward" }
  ]

  function keyLabel(name) {
    for (var i = 0; i < triggerKeys.length; i++) {
      if (triggerKeys[i].value === name) return triggerKeys[i].label
    }
    return String(name).replace(/^KEY_/, "")
  }

  function pageFor(name) {
    for (var i = 0; i < sections.length; i++) if (sections[i].value === name) return sections[i].page
    return null
  }

  // Opens a page; an unknown name (a typo over IPC) lands on Recent.
  function show(name) {
    section = pageFor(name) === null ? "recent" : name
  }

  // The page on show, for the settings harness to drive.
  readonly property Item currentPage: pageLoader.item

  property bool ready: false
  onSectionChanged: if (ready) loadPage()
  Component.onCompleted: {
    ready = true
    loadPage()
  }

  function loadPage() {
    if (pageFor(section) === null) {
      section = "recent"
      return
    }
    // Taking the focus off a field before its page goes saves what was typed
    // in it: fields save as they are left.
    var focused = root.Window.activeFocusItem
    while (focused && focused !== pageLoader) focused = focused.parent
    if (focused) root.forceActiveFocus()
    scroller.contentY = 0
    var page = pageFor(section)
    if (page === "") pageLoader.source = ""
    else pageLoader.setSource(Qt.resolvedUrl(page), { ctx: root })
  }

  // Asks before something that cannot be undone; `onConfirm` runs on yes.
  property var pendingConfirm: null
  function confirm(message, confirmText, onConfirm) {
    pendingConfirm = onConfirm
    confirmDialog.message = message
    confirmDialog.confirmText = confirmText || "Confirm"
    confirmDialog.selectedIndex = 1
    confirmDialog.opened = true
    // Keys go to the dialog, not to a button behind its scrim.
    root.forceActiveFocus()
  }
  function closeConfirm() {
    confirmDialog.opened = false
    pendingConfirm = null
  }

  // Runs `action` once the menu has closed and handed the keyboard back:
  // a paste while the menu holds the focus would land in the menu.
  property var pendingAction: null
  function afterClose(action) {
    pendingAction = action
    closeRequested()
    afterCloseTimer.restart()
  }

  Timer {
    id: afterCloseTimer
    interval: 180
    onTriggered: {
      var action = root.pendingAction
      root.pendingAction = null
      if (action) action()
    }
  }

  function scrollTo(y) {
    scroller.contentY = Math.max(0, Math.min(y, scroller.contentHeight - scroller.height))
  }
  function scrollBy(wheelDelta) {
    if (scroller.interactive) scrollTo(scroller.contentY - wheelDelta / 120 * Style.space(48))
  }

  // Tabbing onto a control below the fold scrolls it into view. A focused
  // control that goes away (a removed entry, a page switched out) leaves the
  // focus on the bare window, where Escape and Tab reach nothing; the menu
  // takes it back.
  readonly property Item focusItem: root.Window.activeFocusItem
  onFocusItemChanged: {
    var item = focusItem
    if (active && visible && (!item || item === root.Window.contentItem)) {
      Qt.callLater(function() { if (root.active) root.forceActiveFocus() })
      return
    }
    if (!item || !scroller.interactive) return
    var ancestor = item.parent
    while (ancestor && ancestor !== formColumn) ancestor = ancestor.parent
    if (!ancestor) return
    var top = item.mapToItem(formColumn, 0, 0).y
    var margin = Style.space(12)
    if (top < scroller.contentY) scrollTo(top - margin)
    else if (top + item.height > scroller.contentY + scroller.height) scrollTo(top + item.height - scroller.height + margin)
  }

  readonly property string statusLine: {
    if (!svc || !svc.connected) return "Not running · systemctl --user start talkify"
    if (svc.engineStatus === "downloading")
      return "Downloading the Speech Model · " + Math.round(svc.engineProgress * 100) + "%"
    if (svc.engineStatus === "loading") return "Loading the Speech Model…"
    if (svc.engineStatus === "failed" || svc.engineStatus === "missing") return svc.engineDetail || "Speech Model unavailable"
    if (svc.recording) return svc.latched ? "Listening (latched)" : "Listening…"
    if (svc.trigger === "commands") return "Ready · tap " + keyLabel(value("trigger.key", "")) + " to dictate"
    return "Ready · hold " + keyLabel(value("trigger.key", "")) + " to dictate"
  }

  implicitHeight: header.implicitHeight + Style.space(16)
    + Math.max(navigation.implicitHeight, formColumn.implicitHeight + Style.space(8))

  Keys.onPressed: function(event) {
    if (confirmDialog.opened) {
      if (confirmDialog.handleKey(event)) event.accepted = true
      return
    }
    if (event.key !== Qt.Key_Escape) return
    event.accepted = true
    closeRequested()
  }

  Column {
    id: header
    width: parent.width
    spacing: Style.space(12)

    Item {
      width: parent.width
      implicitHeight: heading.implicitHeight

      Ghost {
        id: mark
        width: Style.space(28)
        height: Style.space(32)
        anchors.verticalCenter: parent.verticalCenter
        color: root.svc && root.svc.recording ? Color.accent : root.fg
      }

      Column {
        id: heading
        anchors.left: mark.right
        anchors.leftMargin: Style.space(12)
        anchors.right: actions.left
        anchors.rightMargin: Style.space(12)
        spacing: Style.space(3)
        Text {
          text: "Talkify"
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }
        Text {
          width: parent.width
          elide: Text.ElideRight
          text: root.statusLine
          color: root.svc && root.svc.engineStatus === "failed" ? Color.urgent : root.fg
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Row {
        id: actions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)
        Button {
          text: root.svc && root.svc.recording ? "Stop dictation" : "Start dictation"
          bordered: true
          focusable: true
          enabled: !!root.svc && root.svc.connected && root.svc.engineStatus === "ready"
          foreground: root.fg
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          onClicked: { root.svc.toggle(); root.closeRequested() }
        }
        Button {
          text: "Close"
          focusable: true
          foreground: root.fg
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          onClicked: root.closeRequested()
        }
      }
    }

    PanelSeparator { foreground: root.fg }
  }

  Column {
    id: navigation
    anchors.top: header.bottom
    anchors.topMargin: Style.space(16)
    width: Style.space(132)
    spacing: Style.space(6)
    Repeater {
      model: root.sections
      delegate: Button {
        required property var modelData
        width: navigation.width
        leftAlign: true
        text: modelData.label
        selected: root.section === modelData.value
        bordered: true
        focusable: true
        foreground: root.fg
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        onClicked: root.show(modelData.value)
      }
    }
  }

  Flickable {
    id: scroller
    anchors.top: header.bottom
    anchors.topMargin: Style.space(16)
    anchors.left: navigation.right
    anchors.leftMargin: Style.space(20)
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    contentWidth: width
    contentHeight: formColumn.implicitHeight + Style.space(8)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    interactive: contentHeight > height + 1
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    Column {
      id: formColumn
      // Room for the scroll bar, kept whether it shows or not, so a page
      // never reflows as it starts to scroll.
      width: scroller.width - Style.space(12)
      spacing: Style.space(12)

      Column {
        width: parent.width
        spacing: Style.space(12)
        visible: root.section === "appearance"

        SectionTitle { text: "Appearance" }

        PanelSectionHeader {
          text: "WHERE THE HUD APPEARS"
          foreground: root.fg
          fontFamily: root.fontFamily
        }

        // Every placement playing the same session on a small copy of this
        // desktop, drawn by the components the HUD itself uses.
        Row {
          id: placementRow
          width: parent.width
          spacing: Style.space(8)
          readonly property real cardWidth: (width - spacing * (root.placements.length - 1)) / root.placements.length

          Repeater {
            model: root.placements
            delegate: PlacementCard {
              required property var modelData
              width: placementRow.cardWidth
              placementId: modelData.value
              title: modelData.label
              blurb: modelData.blurb
            }
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(18)

          Column {
            id: previewColumn
            width: Math.round((parent.width - parent.spacing) * 0.54)
            spacing: Style.space(12)

            Column {
              width: parent.width
              spacing: Style.space(8)

              PanelSectionHeader {
                text: "PREVIEW"
                foreground: root.fg
                fontFamily: root.fontFamily
              }

              Rectangle {
                width: parent.width
                height: largePreview.implicitHeight + 2
                radius: Style.cornerRadius
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.25)
                clip: true

                PlacementPreview {
                  id: largePreview
                  x: 1
                  y: 1
                  width: parent.width - 2
                  session: previewSession
                  themePalette: previewTheme
                  dpr: root.dpr
                  fontFamily: Style.font.family
                }
              }

              Item {
                width: parent.width
                implicitHeight: Math.max(replay.implicitHeight, wordsHint.implicitHeight)

                Button {
                  id: replay
                  text: "Replay"
                  bordered: true
                  focusable: true
                  foreground: root.fg
                  fontFamily: root.fontFamily
                  fontSize: Style.font.bodySmall
                  onClicked: previewSession.replay()
                }

                Text {
                  id: wordsHint
                  anchors.left: replay.right
                  anchors.leftMargin: Style.space(10)
                  anchors.right: parent.right
                  anchors.verticalCenter: replay.verticalCenter
                  wrapMode: Text.Wrap
                  text: root.wordsNote
                  color: root.fg
                  opacity: 0.6
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }

            ChoiceSetting {
              title: "LONG DRAFTS"
              key: "hud.long_draft"
              fallback: "grow-down"
              options: [
                { value: "grow-down", label: "Grow" },
                { value: "tail-only", label: "Tail only" },
                { value: "shrink-to-fit", label: "Shrink" }
              ]
            }

            SliderSetting {
              title: "HUD SIZE"
              key: "hud.scale"
              minimum: 20
              maximum: 100
              step: 5
              suffix: "%"
              percent: true
            }
          }

          Column {
            width: parent.width - previewColumn.width - parent.spacing
            spacing: Style.space(12)

            ChoiceSetting {
              title: "WORDS"
              key: "hud.words"
              fallback: "auto"
              options: [
                { value: "auto", label: "Auto" },
                { value: "on", label: "Show" },
                { value: "off", label: "Hide" }
              ]
            }

            ChoiceSetting {
              title: "COLOURS"
              key: "hud.colors"
              fallback: "theme"
              options: [
                { value: "theme", label: "Theme" },
                { value: "talkify", label: "Talkify" }
              ]
            }

            ChoiceSetting {
              title: "VOICE VISUAL"
              key: "hud.visual"
              fallback: "waveform"
              options: [
                { value: "waveform", label: "Waveform" },
                { value: "glow", label: "Edge Glow" },
                { value: "glow-draft", label: "Glow + Draft" },
                { value: "compact", label: "Compact" }
              ]
            }

            ChoiceSetting {
              visible: root.value("hud.visual", "waveform") !== "compact"
              title: "WAVEFORM"
              key: "hud.waveform_style"
              fallback: "chart-line"
              options: [
                { value: "chart-line", label: "Chart Line" },
                { value: "capsules", label: "Capsules" },
                { value: "silver", label: "Silver" },
                { value: "dots", label: "Dots" },
                { value: "curve", label: "Curve" },
                { value: "filled", label: "Filled" }
              ]
            }

            ChoiceSetting {
              title: "REVEAL"
              key: "hud.reveal"
              fallback: "slide"
              options: [
                { value: "slide", label: "Slide" },
                { value: "unfurl", label: "Unfurl" },
                { value: "bloom", label: "Bloom" },
                { value: "drift", label: "Drift" }
              ]
            }

            ChoiceSetting {
              visible: root.value("hud.placement", "pill") === "pointer"
              title: "POINTER MARK"
              key: "hud.pointer_mark"
              fallback: "ring"
              options: [
                { value: "ring", label: "Ring" },
                { value: "ghost", label: "Ghost" }
              ]
            }

            ChoiceSetting {
              visible: root.value("hud.placement", "pill") === "halo"
                || String(root.value("hud.visual", "waveform")).indexOf("glow") === 0
              title: "GLOW COLOURS"
              key: "hud.glow_palette"
              fallback: "spectrum"
              // The first pick is the daemon's default ("spectrum"), which
              // follows the colours above: the theme's palette, or Talkify's
              // spectrum.
              options: [
                { value: "spectrum", label: root.value("hud.colors", "theme") === "talkify" ? "Spectrum" : "Theme" },
                { value: "silver", label: "Silver" },
                { value: "aurora", label: "Aurora" },
                { value: "sunset", label: "Sunset" },
                { value: "ocean", label: "Ocean" },
                { value: "mono", label: "Mono" }
              ]
            }
          }
        }
      }

      Loader {
        id: pageLoader
        visible: root.section !== "appearance"
        width: parent.width
      }
    }
  }

  ConfirmDialog {
    id: confirmDialog
    anchors.fill: parent
    z: 10
    foreground: root.fg
    fontFamily: root.fontFamily
    onCanceled: root.closeConfirm()
    onConfirmed: {
      var action = root.pendingConfirm
      root.closeConfirm()
      if (action) action()
    }
  }

  // A placement to pick, playing on its own small desktop.
  component PlacementCard: Item {
    id: card
    property string placementId: ""
    property string title: ""
    property string blurb: ""
    readonly property bool chosen: String(root.value("hud.placement", "pill")) === placementId

    implicitHeight: frame.height + captionColumn.implicitHeight + Style.space(6)

    Rectangle {
      id: frame
      width: parent.width
      height: cardPreview.implicitHeight + 4
      radius: Style.cornerRadius
      color: "transparent"
      border.width: card.chosen ? 2 : 1
      border.color: card.chosen ? Color.accent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, cardMouse.containsMouse ? 0.45 : 0.2)
      clip: true

      PlacementPreview {
        id: cardPreview
        x: 2
        y: 2
        width: parent.width - 4
        session: previewSession
        themePalette: previewTheme
        placement: card.placementId
        dpr: root.dpr
        fontFamily: Style.font.family
      }
    }

    Column {
      id: captionColumn
      anchors.top: frame.bottom
      anchors.topMargin: Style.space(6)
      width: parent.width
      spacing: Style.space(1)
      Text {
        text: card.title
        color: card.chosen ? Color.accent : root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
        text: card.blurb
        color: root.fg
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    MouseArea {
      id: cardMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.set("hud.placement", card.placementId)
    }
  }

  component SectionTitle: Text {
    color: root.fg
    font.family: root.fontFamily
    font.pixelSize: Style.font.subtitle
    font.bold: true
  }

  component ChoiceSetting: Column {
    id: choice
    property string title: ""
    property string key: ""
    property var fallback: ""
    property var options: []

    width: parent ? parent.width : 0
    spacing: Style.space(8)

    PanelSectionHeader {
      text: choice.title
      foreground: root.fg
      fontFamily: root.fontFamily
    }

    Flow {
      width: parent.width
      spacing: Style.space(6)
      Repeater {
        model: choice.options
        delegate: Button {
          required property var modelData
          text: modelData.label
          selected: String(root.value(choice.key, choice.fallback)) === String(modelData.value)
          bordered: true
          foreground: root.fg
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          focusable: true
          onClicked: root.set(choice.key, modelData.value)
        }
      }
    }
  }

  component SliderSetting: Column {
    id: sliderSetting
    property string title: ""
    property string key: ""
    property string description: ""
    property real minimum: 0
    property real maximum: 10
    property real step: 1
    property string suffix: ""
    // Stored 0–1, shown and dragged as a percentage.
    property bool percent: false

    width: parent ? parent.width : 0
    spacing: Style.space(8)

    Item {
      width: parent.width
      implicitHeight: sliderHeader.implicitHeight
      PanelSectionHeader {
        id: sliderHeader
        text: sliderSetting.title
        foreground: root.fg
        fontFamily: root.fontFamily
      }
      Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: Math.round(slider.liveValue) + sliderSetting.suffix
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }
    }

    PanelSlider {
      id: slider
      width: parent.width
      bar: root.bar
      minimum: sliderSetting.minimum
      maximum: sliderSetting.maximum
      step: sliderSetting.step
      integer: true
      value: Number(root.value(sliderSetting.key, 0)) * (sliderSetting.percent ? 100 : 1)
      onReleased: function(value) {
        var stored = Math.round(value)
        root.set(sliderSetting.key, sliderSetting.percent ? stored / 100 : stored)
      }

      // The wheel scrolls the page rather than changing the setting under
      // the pointer.
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: function(wheel) { root.scrollBy(wheel.angleDelta.y) }
      }
    }

    Text {
      visible: sliderSetting.description !== ""
      width: parent.width
      wrapMode: Text.Wrap
      text: sliderSetting.description
      color: root.fg
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
