import QtQuick
import qs.Commons

// One page of the Settings menu. TalkifySettings loads it with `ctx`, itself:
// the service, the bar's colours and font, and value()/set() over the
// daemon's config, so a page never reaches past what it was handed.
Column {
  id: page

  required property var ctx
  readonly property var svc: ctx.svc
  readonly property color fg: ctx.fg
  readonly property string fontFamily: ctx.fontFamily

  function value(path, fallback) { return ctx.value(path, fallback) }
  function set(path, next) { ctx.set(path, next) }

  spacing: Style.space(12)
}
