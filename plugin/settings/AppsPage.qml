import QtQuick
import qs.Commons
import qs.Ui

// App rules: how dictation lands in one app. The apps listed are the ones
// with a rule and the ones recently dictated into, so a rule is picked from
// what you use rather than typed as a window class.
SettingsPage {
  id: page

  readonly property var apps: value("apps", ({})) || ({})
  // Classes typed in below, shown until they get a rule of their own.
  property var added: []
  property string expanded: ""

  readonly property var ruled: {
    var list = Object.keys(apps).filter(function(c) { return c !== "terminal" }).sort()
    for (var i = 0; i < added.length; i++) if (list.indexOf(added[i]) < 0 && added[i] !== "terminal") list.push(added[i])
    // Terminals always lead: they carry the shipped rule, and clearing it
    // must leave a way back.
    return ["terminal"].concat(list)
  }

  readonly property var recent: {
    var seen = []
    var items = (svc && svc.history) || []
    for (var i = 0; i < items.length; i++) {
      var cls = String(items[i].app || "")
      if (cls === "" || ruled.indexOf(cls) >= 0 || seen.indexOf(cls) >= 0) continue
      seen.push(cls)
    }
    return seen
  }

  // Classes the daemon applied the terminal rule to, as Recent recorded it:
  // for those the terminal rule, not the globals, is what a field inherits.
  readonly property var terminals: {
    var found = []
    var items = (svc && svc.history) || []
    for (var i = 0; i < items.length; i++) {
      if (items[i].rule === "terminal" && found.indexOf(items[i].app) < 0) found.push(items[i].app)
    }
    return found
  }

  function toggle(cls) { expanded = expanded === cls ? "" : cls }

  function addClass() {
    var cls = classField.text.trim()
    if (cls === "") return
    if (ruled.indexOf(cls) < 0 && recent.indexOf(cls) < 0) added = added.concat([cls])
    expanded = cls
    classField.text = ""
  }

  PageTitle {
    ctx: page.ctx
    text: "App rules"
  }

  Caption {
    ctx: page.ctx
    text: "Change how dictation lands in one app. Each field is decided on its own: an app's own rule first, then the Terminals rule if it is a terminal, then the global settings. The HUD names the rules in force when a session starts."
  }

  Heading {
    ctx: page.ctx
    text: "RULES"
  }

  Repeater {
    model: page.ruled
    delegate: AppRule {
      required property var modelData
      ctx: page.ctx
      cls: modelData
      fields: page.apps[modelData]
      fallback: modelData !== "terminal" && page.terminals.indexOf(modelData) >= 0 ? page.apps.terminal : undefined
      expanded: page.expanded === modelData
      onToggled: page.toggle(modelData)
    }
  }

  Heading {
    visible: page.recent.length > 0
    ctx: page.ctx
    topPadding: Style.space(6)
    text: "RECENTLY DICTATED INTO"
  }

  Repeater {
    model: page.recent
    delegate: AppRule {
      required property var modelData
      ctx: page.ctx
      cls: modelData
      fields: page.apps[modelData]
      fallback: modelData !== "terminal" && page.terminals.indexOf(modelData) >= 0 ? page.apps.terminal : undefined
      expanded: page.expanded === modelData
      onToggled: page.toggle(modelData)
    }
  }

  Heading {
    ctx: page.ctx
    topPadding: Style.space(6)
    text: "ANOTHER APP"
  }

  Item {
    width: parent.width
    implicitHeight: Math.max(classField.implicitHeight, addClass.implicitHeight)

    TextField {
      id: classField
      anchors.left: parent.left
      anchors.right: addClass.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      placeholderText: "A window class, e.g. org.gnome.Nautilus"
      foreground: page.fg
      font.family: page.fontFamily
      font.pixelSize: Style.font.bodySmall
      onAccepted: page.addClass()
    }

    Button {
      id: addClass
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: "Add"
      bordered: true
      focusable: true
      enabled: classField.text.trim() !== ""
      opacity: enabled ? 1 : 0.45
      foreground: page.fg
      fontFamily: page.fontFamily
      fontSize: Style.font.bodySmall
      onClicked: page.addClass()
    }
  }

  Caption {
    ctx: page.ctx
    strength: 0.6
    text: "hyprctl activewindow prints the class of the focused window. Browsers share one class for every site."
  }
}
