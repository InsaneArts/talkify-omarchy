import QtQuick
import qs.Commons
import qs.Ui
import "Format.js" as Format

// Sixteen weeks of dictation, a column per week, Monday at the top, oldest
// on the left, as the Mac draws it. A day's square is the theme's accent at
// an intensity that rises with the square root of its words against the
// busiest day, so one long day does not wash every other day out; days
// without words are a faint wash of the foreground and days still to come
// are left empty.
Item {
  id: map

  required property var ctx
  // [{day: "2026-06-16", words, future}], Monday first, oldest first.
  property var days: []

  readonly property int weeks: Math.max(1, Math.ceil(days.length / 7))
  readonly property real labelWidth: Style.space(30)
  readonly property real monthHeight: Style.font.caption + Style.space(6)
  readonly property real gap: Style.space(3)
  readonly property real cell: Math.max(6, Math.min(Style.space(24), (width - labelWidth) / weeks - gap))
  readonly property real gridWidth: labelWidth + weeks * (cell + gap) - gap
  // Centred in whatever width it is given.
  readonly property real offset: Math.max(0, (width - gridWidth) / 2)
  readonly property real busiest: {
    var most = 0
    for (var i = 0; i < days.length; i++) if (!days[i].future) most = Math.max(most, Number(days[i].words) || 0)
    return most
  }
  // The last day that is not in the future: today.
  readonly property int today: {
    for (var i = days.length - 1; i >= 0; i--) if (!days[i].future) return i
    return -1
  }
  property int hovered: -1

  // A month's name over the first week that starts in it.
  readonly property var monthLabels: {
    var labels = []
    var previous = -1
    for (var w = 0; w < weeks; w++) {
      var date = Format.dayDate(days[w * 7] ? days[w * 7].day : "")
      if (!date) continue
      if (date.getMonth() !== previous) labels.push({ week: w, text: Format.monthShort(date.getMonth()) })
      previous = date.getMonth()
    }
    // A label squeezed against the left edge by a month that started
    // mid-week reads as the next one's; drop it.
    if (labels.length > 1 && labels[1].week - labels[0].week < 2) labels.shift()
    return labels
  }

  function intensity(words) {
    if (!(words > 0) || busiest <= 0) return 0
    return 0.28 + 0.72 * Math.sqrt(words / busiest)
  }

  function tint(day) {
    if (day.future) return "transparent"
    var level = intensity(Number(day.words) || 0)
    if (level === 0) return Qt.rgba(ctx.fg.r, ctx.fg.g, ctx.fg.b, 0.08)
    return Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, level)
  }

  implicitWidth: gridWidth
  implicitHeight: monthHeight + 7 * (cell + gap)

  Repeater {
    model: map.monthLabels
    delegate: Text {
      required property var modelData
      x: map.offset + map.labelWidth + modelData.week * (map.cell + map.gap)
      textFormat: Text.PlainText
      text: modelData.text
      color: map.ctx.fg
      opacity: 0.6
      font.family: map.ctx.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Repeater {
    model: [{ row: 0, text: "Mon" }, { row: 2, text: "Wed" }, { row: 4, text: "Fri" }]
    delegate: Text {
      required property var modelData
      x: map.offset
      y: map.monthHeight + modelData.row * (map.cell + map.gap) + (map.cell - height) / 2
      textFormat: Text.PlainText
      text: modelData.text
      color: map.ctx.fg
      opacity: 0.6
      font.family: map.ctx.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Repeater {
    id: cells
    model: map.days

    delegate: Rectangle {
      id: square
      required property var modelData
      required property int index
      x: map.offset + map.labelWidth + Math.floor(index / 7) * (map.cell + map.gap)
      y: map.monthHeight + (index % 7) * (map.cell + map.gap)
      width: map.cell
      height: map.cell
      radius: Math.min(3, Style.cornerRadius)
      color: map.tint(modelData)
      border.width: index === map.today || index === map.hovered ? 1 : 0
      border.color: index === map.hovered ? map.ctx.fg : Qt.rgba(map.ctx.fg.r, map.ctx.fg.g, map.ctx.fg.b, 0.5)

      MouseArea {
        anchors.fill: parent
        enabled: !square.modelData.future
        hoverEnabled: true
        onContainsMouseChanged: {
          if (containsMouse) map.hovered = square.index
          else if (map.hovered === square.index) map.hovered = -1
        }
      }
    }
  }

  // One tooltip, moved to the hovered day, rather than a popup per square.
  PanelToolTip {
    id: tip
    parent: map.hovered >= 0 && map.hovered < cells.count ? cells.itemAt(map.hovered) : map
    visible: map.hovered >= 0
    delay: 150
    fontFamily: map.ctx.fontFamily
    text: {
      var day = map.hovered >= 0 ? map.days[map.hovered] : null
      if (!day) return ""
      return Format.dayLabel(day.day) + "  ·  " + (day.words > 0 ? Format.count(day.words, "word") : "no dictation")
        + (map.hovered === map.today ? "  ·  today" : "")
    }
  }
}
