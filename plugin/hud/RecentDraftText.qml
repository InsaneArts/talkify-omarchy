import QtQuick
import "HudText.js" as HudText

// Edge Glow + Draft's live draft (HUDRecentDraftText): one 24-point line of
// the last eight words, centered when it fits; when it does not, the newest
// words stay and the oldest run off the leading edge as one clip, never as
// eight separate ellipses.
//
// Each word keeps an identity (its index in the whole draft), so only a new
// or departing word slides; a volatile rewrite inside the current word
// updates in place, and a backward correction snaps rather than lingering
// behind a fade. Words live insertion has already put in the window are
// solid; the rest are at half strength.
Item {
  id: line

  property string draft: ""
  property string committed: ""
  // Off draws every word solid: with live insertion off nothing has landed
  // yet, and a draft that is all half-strength only reads as dim.
  property bool twoTone: false
  property var textRgb: [1, 1, 1]
  property real hudScale: 1
  property string fontFamily: ""

  readonly property int wordLimit: 8
  readonly property real pointSize: 24 * hudScale
  readonly property int slideMilliseconds: 140
  readonly property int committedLength: HudText.committedLength(draft, committed)

  clip: true

  // The last window, to tell an advance (a new word, an eviction) from a
  // rewrite.
  property int lastTokenCount: 0
  property int lastEvictionOffset: 0
  property real originX: 0

  TextMetrics {
    id: measure
    font.family: line.fontFamily
    font.pixelSize: Math.max(1, line.pointSize)
    font.weight: Font.Medium
  }

  ListModel {
    id: tokens
  }

  function measureWidth(text) {
    measure.text = text
    return measure.advanceWidth
  }

  // Word tokens of the joined draft, each slice running through the
  // whitespace to the next word so surviving words keep their places.
  function window(text) {
    var starts = []
    var pattern = /\S+/g
    var match
    while ((match = pattern.exec(text)) !== null) starts.push(match.index)
    var count = starts.length
    if (count === 0) {
      return { tokenCount: 0, evictionOffset: 0, visible: text.length > 0 ? [{ id: 0, text: text, start: 0 }] : [] }
    }
    var first = Math.max(0, count - wordLimit)
    var visible = []
    for (var i = first; i < count; i++) {
      var from = i === first ? (first === 0 ? 0 : starts[i]) : starts[i]
      var to = i + 1 < count ? starts[i + 1] : text.length
      visible.push({ id: i, text: text.substring(from, to), start: from })
    }
    return { tokenCount: count, evictionOffset: first === 0 ? 0 : starts[first], visible: visible }
  }

  function relayout(next, animate) {
    var total = 0
    var widths = []
    for (var i = 0; i < next.length; i++) {
      var w = measureWidth(next[i].text)
      widths.push(w)
      total += w
    }
    originX = total > width ? width - total : (width - total) / 2

    var byId = {}
    var x = originX
    for (i = 0; i < next.length; i++) {
      byId[next[i].id] = { text: next[i].text, x: x, width: widths[i], start: next[i].start }
      x += widths[i]
    }

    // Departing words: slide toward the leading edge and fade, or go now.
    for (i = tokens.count - 1; i >= 0; i--) {
      var row = tokens.get(i)
      if (row.leaving) continue
      if (byId[row.tid] === undefined) {
        if (animate) tokens.setProperty(i, "leaving", true)
        else tokens.remove(i)
      }
    }

    for (var key in byId) {
      var id = Number(key)
      var spot = byId[key]
      var found = -1
      for (i = 0; i < tokens.count; i++) {
        if (tokens.get(i).tid === id && !tokens.get(i).leaving) {
          found = i
          break
        }
      }
      if (found >= 0) {
        // The flag first: it decides whether the move below animates.
        tokens.setProperty(found, "animated", animate)
        tokens.setProperty(found, "label", spot.text)
        tokens.setProperty(found, "targetX", spot.x)
        tokens.setProperty(found, "start", spot.start)
      } else {
        tokens.append({ tid: id, label: spot.text, targetX: spot.x, leaving: false, animated: animate, start: spot.start })
      }
    }
  }

  function update() {
    var next = window(draft)
    var advances = next.tokenCount > lastTokenCount || next.evictionOffset > lastEvictionOffset
    lastTokenCount = next.tokenCount
    lastEvictionOffset = next.evictionOffset
    relayout(next.visible, advances)
  }

  onDraftChanged: update()
  onCommittedLengthChanged: update()
  onWidthChanged: relayout(window(draft).visible, false)
  onPointSizeChanged: relayout(window(draft).visible, false)

  Repeater {
    model: tokens

    Text {
      id: word

      required property int index
      required property int tid
      required property string label
      required property real targetX
      required property bool leaving
      required property bool animated
      required property int start

      // Where it sits before the first layout pass lands.
      property bool placed: false

      y: Math.round((line.height - height) / 2)
      text: label
      color: Qt.rgba(line.textRgb[0], line.textRgb[1], line.textRgb[2],
        !line.twoTone || start < line.committedLength ? 1 : HudText.pendingAlpha)
      font.family: line.fontFamily
      font.pixelSize: Math.max(1, line.pointSize)
      font.weight: Font.Medium
      textFormat: Text.PlainText
      renderType: Text.NativeRendering
      // The trailing whitespace is part of the slice; keep it from wrapping.
      wrapMode: Text.NoWrap

      x: targetX
      opacity: 1

      Behavior on x {
        enabled: word.animated && word.placed
        NumberAnimation { duration: line.slideMilliseconds; easing.type: Easing.OutQuad }
      }

      Component.onCompleted: {
        if (animated) {
          // Insertion: in from the trailing side, fading up.
          x = targetX + implicitWidth
          opacity = 0
          placed = true
          x = Qt.binding(function () { return word.targetX })
          enterFade.start()
        } else {
          placed = true
        }
      }

      onLeavingChanged: {
        if (!leaving) return
        x = targetX - implicitWidth
        exitFade.start()
      }

      NumberAnimation {
        id: enterFade
        target: word
        property: "opacity"
        to: 1
        duration: line.slideMilliseconds
        easing.type: Easing.OutQuad
      }

      NumberAnimation {
        id: exitFade
        target: word
        property: "opacity"
        to: 0
        duration: line.slideMilliseconds
        easing.type: Easing.OutQuad
        onFinished: {
          for (var i = 0; i < tokens.count; i++) {
            if (tokens.get(i).tid === word.tid && tokens.get(i).leaving) {
              tokens.remove(i)
              break
            }
          }
        }
      }
    }
  }
}
