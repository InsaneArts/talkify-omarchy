import QtQuick
import qs.Commons
import ".."
import "Format.js" as Format

// This month's dictation as a card to share, in the Omarchy theme's own
// colours: Omarchy users share themed screenshots, so a card in their theme
// is one they would post. Drawn at fixed pixel sizes, not the shell's
// scaled ones, because it becomes an image.
Rectangle {
  id: card

  required property var ctx
  property var insights: null

  readonly property date now: new Date()
  readonly property var heatmap: (insights && insights.heatmap) || []
  // Every day of this month, its words from the 16-week heatmap (which
  // always covers the month so far); the days still to come stay empty.
  readonly property var month: {
    var words = {}
    for (var i = 0; i < heatmap.length; i++) words[heatmap[i].day] = Number(heatmap[i].words) || 0
    var today = new Date(now.getFullYear(), now.getMonth(), now.getDate())
    var length = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate()
    var days = []
    for (var d = 1; d <= length; d++) {
      var date = new Date(now.getFullYear(), now.getMonth(), d)
      var iso = date.getFullYear() + "-" + String(date.getMonth() + 1).padStart(2, "0") + "-" + String(d).padStart(2, "0")
      days.push({ date: date, words: words[iso] || 0, future: date > today })
    }
    return days
  }
  readonly property int words: month.reduce(function(sum, d) { return sum + (d.future ? 0 : d.words) }, 0)
  readonly property int activeDays: month.filter(function(d) { return !d.future && d.words > 0 }).length
  readonly property int busiest: month.reduce(function(most, d) { return Math.max(most, d.words) }, 0)
  // Monday-first column of the month's first day.
  readonly property int lead: month.length ? (month[0].date.getDay() + 6) % 7 : 0
  readonly property color ink: Color.foreground
  readonly property color accent: Color.accent

  width: 640
  height: 340
  radius: Style.cornerRadius > 0 ? 18 : 0
  color: Color.background
  border.width: 2
  border.color: Qt.rgba(accent.r, accent.g, accent.b, 0.8)

  Row {
    x: 32
    y: 30
    spacing: 14

    Ghost {
      width: 28
      height: 32
      color: card.accent
    }

    Column {
      spacing: 2
      Text {
        text: "Talkify"
        color: card.ink
        font.family: Style.font.family
        font.pixelSize: 20
        font.bold: true
      }
      Text {
        text: Format.monthName(card.now.getMonth()) + " " + card.now.getFullYear()
        color: card.ink
        opacity: 0.6
        font.family: Style.font.family
        font.pixelSize: 14
      }
    }
  }

  Column {
    x: 32
    y: 112
    spacing: 4

    Text {
      text: Format.grouped(card.words)
      color: card.accent
      font.family: Style.font.family
      font.pixelSize: 60
      font.bold: true
    }

    Text {
      text: card.words === 1 ? "word dictated this month" : "words dictated this month"
      color: card.ink
      opacity: 0.75
      font.family: Style.font.family
      font.pixelSize: 15
    }
  }

  Row {
    x: 32
    y: 250
    spacing: 30

    Repeater {
      model: [
        { value: card.activeDays, label: card.activeDays === 1 ? "day talking" : "days talking" },
        { value: card.insights ? card.insights.current_streak : 0, label: "day streak" },
        { value: card.insights ? Math.round(card.insights.wpm) : 0, label: "words a minute" }
      ]
      delegate: Column {
        required property var modelData
        spacing: 2
        Text {
          text: Format.grouped(modelData.value)
          color: card.ink
          font.family: Style.font.family
          font.pixelSize: 24
          font.bold: true
        }
        Text {
          text: modelData.label
          color: card.ink
          opacity: 0.6
          font.family: Style.font.family
          font.pixelSize: 12
        }
      }
    }
  }

  // The month as a calendar, Monday first, shaded like the heatmap.
  Item {
    id: calendar
    readonly property real cell: 24
    readonly property real gap: 5
    x: card.width - width - 34
    y: 52
    width: 7 * (cell + gap) - gap
    height: 7 * (cell + gap)

    Repeater {
      model: ["M", "T", "W", "T", "F", "S", "S"]
      delegate: Text {
        required property var modelData
        required property int index
        x: index * (calendar.cell + calendar.gap) + (calendar.cell - width) / 2
        text: modelData
        color: card.ink
        opacity: 0.5
        font.family: Style.font.family
        font.pixelSize: 11
      }
    }

    Repeater {
      model: card.month
      delegate: Rectangle {
        required property var modelData
        required property int index
        readonly property int slot: card.lead + index
        x: (slot % 7) * (calendar.cell + calendar.gap)
        y: 22 + Math.floor(slot / 7) * (calendar.cell + calendar.gap)
        width: calendar.cell
        height: calendar.cell
        radius: card.radius > 0 ? 5 : 0
        color: modelData.future ? "transparent"
          : modelData.words > 0 && card.busiest > 0
            ? Qt.rgba(card.accent.r, card.accent.g, card.accent.b, 0.28 + 0.72 * Math.sqrt(modelData.words / card.busiest))
            : Qt.rgba(card.ink.r, card.ink.g, card.ink.b, 0.08)
        border.width: modelData.future ? 1 : 0
        border.color: Qt.rgba(card.ink.r, card.ink.g, card.ink.b, 0.1)
      }
    }
  }

  Text {
    x: card.width - width - 34
    y: card.height - height - 26
    text: "on-device dictation for Omarchy"
    color: card.ink
    opacity: 0.45
    font.family: Style.font.family
    font.pixelSize: 12
  }
}
