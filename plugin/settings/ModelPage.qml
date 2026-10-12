import QtQuick
import qs.Commons
import qs.Ui

SettingsPage {
  id: page

  PageTitle {
    ctx: page.ctx
    text: "Speech Model"
  }

  Caption {
    ctx: page.ctx
    text: "NVIDIA Parakeet TDT 0.6B v3, int8, running on this machine's CPU. It never leaves this computer. It understands 25 European languages and finds the one you speak by itself."
  }

  Heading {
    ctx: page.ctx
    text: "STATUS"
  }

  Text {
    width: parent.width
    wrapMode: Text.Wrap
    textFormat: Text.PlainText
    text: {
      if (!page.svc || !page.svc.connected) return "The daemon is not running."
      switch (page.svc.engineStatus) {
      case "ready": return "Loaded and warm."
      case "loading": return "Loading…"
      case "downloading": return "Downloading, " + Math.round(page.svc.engineProgress * 100) + "% of 670 MB."
      default: return page.svc.engineDetail || "Not available."
      }
    }
    color: page.svc && page.svc.engineStatus === "failed" ? Color.urgent : page.fg
    font.family: page.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Button {
    visible: !!page.svc && page.svc.connected
      && (page.svc.engineStatus === "failed" || page.svc.engineStatus === "missing")
    text: "Download and load"
    bordered: true
    focusable: true
    foreground: page.fg
    fontFamily: page.fontFamily
    fontSize: Style.font.bodySmall
    onClicked: page.svc.loadModel()
  }

  Heading {
    ctx: page.ctx
    text: "DAEMON & SYSTEM LOAD"
  }

  Caption {
    ctx: page.ctx
    text: "While connected, the Speech Model is kept warm in RAM (~1 GB) for fast voice recognition. Disconnecting Talkify stops the daemon completely to save memory and CPU load."
  }

  Row {
    spacing: Style.space(8)
    Button {
      text: page.svc && page.svc.connected ? "Disconnect (save RAM & CPU)" : "Connect daemon"
      bordered: true
      focusable: true
      selected: !(page.svc && page.svc.connected)
      foreground: !(page.svc && page.svc.connected) ? Color.accent : page.fg
      fontFamily: page.fontFamily
      fontSize: Style.font.bodySmall
      onClicked: if (page.svc) page.svc.toggleConnect()
    }
  }
}
