.pragma library

// Which bar widget instance answers Talkify's IPC target. The bar draws a
// widget per monitor and every one would register the same target, which
// works but warns for each extra one; instead the first to join owns it and
// hands it on when it goes. Shared by every instance: a .pragma library
// file is loaded once per engine.

var holders = ({})

// True when `item` is now the owner of `target`.
function join(target, item) {
  var list = holders[target] || []
  if (list.indexOf(item) < 0) list.push(item)
  holders[target] = list
  return list[0] === item
}

// The instance that owns `target` after `item` leaves, or null.
function leave(target, item) {
  var list = (holders[target] || []).filter(function(other) { return other !== item })
  holders[target] = list
  return list.length ? list[0] : null
}
