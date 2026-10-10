import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Format.js" as Format

// Insights, ported from the Mac's pane: how much you dictate, how fast, how
// steadily, and the sixteen-week heatmap. Only counts are kept: no text and
// no app names. "Time saved" is only ever shown with the typing speed it
// assumes.
SettingsPage {
  id: page

  readonly property var insights: svc ? svc.insights : null
  readonly property bool keeping: value("insights.enabled", true) === true
  readonly property bool hasData: !!insights && Number(insights.sessions) > 0
  readonly property var momentum: (insights && insights.momentum) || ({})
  readonly property real columnWidth: (width - Style.space(8) * 2) / 3
  property string savedTo: ""
  property bool saveFailed: false

  function saveCard() {
    var dir = Quickshell.env("HOME") + "/Pictures"
    var now = new Date()
    var month = now.getFullYear() + "-" + (now.getMonth() < 9 ? "0" : "") + (now.getMonth() + 1)
    var path = dir + "/talkify-" + month + ".png"
    Quickshell.execDetached(["mkdir", "-p", dir])
    // The folder is made by another process; give it a moment before the
    // write that needs it.
    saveDelay.path = path
    saveDelay.restart()
  }

  Timer {
    id: saveDelay
    property string path: ""
    interval: 150
    onTriggered: monthCard.grabToImage(function(result) {
      page.saveFailed = !result.saveToFile(saveDelay.path)
      page.savedTo = page.saveFailed ? "" : saveDelay.path
    }, Qt.size(monthCard.width * 2, monthCard.height * 2))
  }

  PageTitle {
    ctx: page.ctx
    text: "Insights"
  }

  Caption {
    ctx: page.ctx
    text: "Counted on this machine, per day: words, sessions and speaking time. No text and no app names."
  }

  ToggleRow {
    ctx: page.ctx
    label: "Keep Insights"
    description: page.keeping ? "Counting every finished Direct Dictation session" : "Off: nothing is counted, and the ghost does not celebrate milestones"
    key: "insights.enabled"
    fallback: true
  }

  Card {
    visible: page.keeping && !page.hasData
    ctx: page.ctx
    inset: Style.space(18)

    Text {
      textFormat: Text.PlainText
      text: "No dictation data yet"
      color: page.fg
      font.family: page.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
    }

    Caption {
      ctx: page.ctx
      text: "Insights appear after your first finished Direct Dictation session."
    }
  }

  Grid {
    id: stats
    // Every card as tall as the tallest, so a row ends level whatever its
    // sentences wrap to.
    readonly property real cardHeight: {
      var tallest = 0
      for (var i = 0; i < children.length; i++) tallest = Math.max(tallest, children[i].implicitHeight || 0)
      return tallest
    }
    visible: page.hasData
    columns: 3
    columnSpacing: Style.space(8)
    rowSpacing: Style.space(8)

    StatCard {
      title: "WORDS THIS WEEK"
      value: Format.grouped(page.momentum.current_words)
      comparison: Format.momentum(page.momentum)
      caption: "On " + Format.count(page.momentum.active_days, "day") + " · " + Format.count(page.momentum.sessions, "session")
    }
    StatCard {
      title: "AVERAGE PACE"
      value: page.insights ? Format.grouped(page.insights.wpm) : "0"
      unit: "wpm"
      comparison: "Weighted by speaking time"
      caption: (page.insights ? Format.grouped(page.insights.words_per_session) : "0") + " words a session"
    }
    StatCard {
      readonly property var spoken: Format.duration(page.insights ? page.insights.speaking_seconds : 0)
      title: "VOICE TIME"
      value: spoken.value
      unit: spoken.unit
      comparison: (page.insights ? Format.count(page.insights.total_words, "word") : "") + " in total"
      caption: page.insights ? Format.count(page.insights.sessions, "session") : ""
    }
    StatCard {
      title: "STREAK"
      value: page.insights ? Format.grouped(page.insights.current_streak) : "0"
      unit: page.insights && page.insights.current_streak === 1 ? "day" : "days"
      comparison: "Days in a row with a dictation"
      caption: "Longest: " + (page.insights ? Format.count(page.insights.longest_streak, "day") : "")
    }
    StatCard {
      title: "TODAY"
      value: page.insights ? Format.grouped(page.insights.today_words) : "0"
      unit: "words"
      comparison: page.insights && page.insights.today_words > 0 ? "Dictated so far today" : "Nothing dictated yet today"
      caption: ""
    }
    StatCard {
      readonly property var saved: Format.duration((page.insights ? page.insights.minutes_saved : 0) * 60)
      title: "TIME SAVED"
      value: saved.value
      unit: saved.unit
      // The figure means nothing without what it is measured against.
      comparison: "Against typing at " + page.value("insights.typing_wpm", page.insights ? page.insights.typing_wpm : 40) + " wpm"
      caption: "Change the speed below"
    }
  }

  Card {
    visible: page.hasData
    ctx: page.ctx
    spacing: Style.space(10)

    Item {
      width: parent.width
      implicitHeight: activityTitle.implicitHeight

      Heading {
        id: activityTitle
        ctx: page.ctx
        text: "ACTIVITY"
      }

      Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: page.insights
          ? Format.count(page.insights.current_streak, "day") + " streak  ·  longest " + Format.count(page.insights.longest_streak, "day")
          : ""
        color: page.fg
        opacity: 0.7
        font.family: page.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Heatmap {
      width: parent.width
      ctx: page.ctx
      days: (page.insights && page.insights.heatmap) || []
    }

    Row {
      anchors.right: parent.right
      spacing: Style.space(5)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "Less"
        color: page.fg
        opacity: 0.6
        font.family: page.fontFamily
        font.pixelSize: Style.font.caption
      }
      Repeater {
        model: [0, 0.28, 0.52, 0.76, 1]
        delegate: Rectangle {
          required property real modelData
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(11)
          height: width
          radius: Math.min(2, Style.cornerRadius)
          color: modelData === 0 ? Qt.rgba(page.fg.r, page.fg.g, page.fg.b, 0.08)
            : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, modelData)
        }
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "More"
        color: page.fg
        opacity: 0.6
        font.family: page.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  Column {
    visible: page.hasData
    width: parent.width
    spacing: Style.space(8)

    Heading {
      ctx: page.ctx
      text: "MILESTONES"
    }

    Caption {
      readonly property var reached: (page.insights && page.insights.milestones) || []
      visible: reached.length === 0
      ctx: page.ctx
      strength: 0.6
      text: "None yet. The ghost in the bar celebrates each one the first time you reach it."
    }

    Flow {
      width: parent.width
      spacing: Style.space(6)

      Repeater {
        model: (page.insights && page.insights.milestones) || []
        delegate: Rectangle {
          required property var modelData
          implicitWidth: milestoneText.implicitWidth + Style.space(18)
          implicitHeight: milestoneText.implicitHeight + Style.space(8)
          radius: Style.cornerRadius
          color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.14)
          border.width: 1
          border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.5)

          Text {
            id: milestoneText
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: Format.milestone(parent.modelData.kind, parent.modelData.value)
            color: page.fg
            font.family: page.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }
      }
    }
  }

  SliderRow {
    visible: page.keeping
    ctx: page.ctx
    title: "YOUR TYPING SPEED"
    key: "insights.typing_wpm"
    fallback: 40
    minimum: 20
    maximum: 120
    step: 5
    suffix: " wpm"
    description: "Time saved compares speaking with typing at this speed. 40 wpm is a common estimate; a large study measured an average near 52."
  }

  Column {
    visible: page.hasData
    width: parent.width
    spacing: Style.space(8)

    Heading {
      ctx: page.ctx
      topPadding: Style.space(6)
      text: "THIS MONTH, AS A CARD"
    }

    // The card at its own size, shown scaled to the page; the saved image is
    // drawn from the card itself, at twice its size.
    Item {
      width: parent.width
      height: monthCard.height * scaleFactor
      readonly property real scaleFactor: Math.min(1, width / monthCard.width)

      MonthCard {
        id: monthCard
        ctx: page.ctx
        insights: page.insights
        transformOrigin: Item.TopLeft
        scale: parent.scaleFactor
      }
    }

    Item {
      width: parent.width
      implicitHeight: Math.max(saveButton.implicitHeight, savedText.implicitHeight)

      Button {
        id: saveButton
        text: "Save as PNG"
        bordered: true
        focusable: true
        foreground: page.fg
        fontFamily: page.fontFamily
        fontSize: Style.font.bodySmall
        onClicked: page.saveCard()
      }

      Text {
        id: savedText
        anchors.left: saveButton.right
        anchors.leftMargin: Style.space(10)
        anchors.right: parent.right
        anchors.verticalCenter: saveButton.verticalCenter
        elide: Text.ElideMiddle
        textFormat: Text.PlainText
        text: page.saveFailed ? "Could not write to ~/Pictures"
          : page.savedTo !== "" ? "Saved to " + page.savedTo.replace(Quickshell.env("HOME"), "~") : ""
        color: page.saveFailed ? Color.urgent : page.fg
        opacity: page.saveFailed ? 1 : 0.7
        font.family: page.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  component StatCard: Card {
    id: stat
    property string title: ""
    property string value: ""
    property string unit: ""
    property string comparison: ""
    property string caption: ""

    ctx: page.ctx
    width: page.columnWidth
    height: stats.cardHeight
    spacing: Style.space(5)

    Text {
      textFormat: Text.PlainText
      text: stat.title
      color: Color.accent
      font.family: page.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    Row {
      spacing: Style.space(4)

      Text {
        id: statValue
        textFormat: Text.PlainText
        text: stat.value
        color: page.fg
        font.family: page.fontFamily
        font.pixelSize: Style.font.display
        font.bold: true
      }

      Text {
        anchors.baseline: statValue.baseline
        visible: stat.unit !== ""
        textFormat: Text.PlainText
        text: stat.unit
        color: page.fg
        opacity: 0.7
        font.family: page.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }
    }

    Text {
      width: parent.width
      wrapMode: Text.Wrap
      maximumLineCount: 2
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: stat.comparison
      color: page.fg
      opacity: 0.75
      font.family: page.fontFamily
      font.pixelSize: Style.font.caption
    }

    Text {
      width: parent.width
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: stat.caption
      color: page.fg
      opacity: 0.5
      font.family: page.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
