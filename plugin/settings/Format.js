.pragma library

// The Settings pages' wording rules, kept pure (values in, strings out) so
// every page says a number, a time or an app the same way.

// 12840 -> "12,840". Grouped by hand: the menu is English throughout, and a
// locale-grouped number inside an English sentence reads as a typo.
function grouped(value) {
  var n = Math.round(Number(value) || 0)
  var sign = n < 0 ? "-" : ""
  return sign + String(Math.abs(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ",")
}

// "1 session", "412 sessions".
function count(value, singular, plural) {
  var n = Math.round(Number(value) || 0)
  return grouped(n) + " " + (n === 1 ? singular : (plural || singular + "s"))
}

// A duration as a value and a unit, the way the Mac's Insights shows voice
// time: seconds under a minute, minutes under an hour, then tenths of hours.
function duration(seconds) {
  var s = Math.max(0, Number(seconds) || 0)
  if (s < 60) return { value: String(Math.round(s)), unit: "sec" }
  if (s < 3600) return { value: grouped(s / 60), unit: "min" }
  return { value: (s / 3600).toFixed(1), unit: "hr" }
}

// Unix seconds against now (milliseconds) as "just now", "4 min ago",
// "2 hr ago", "yesterday", "3 days ago", then a date.
function timeAgo(at, nowMs) {
  var then = Number(at) * 1000
  var seconds = Math.max(0, (nowMs - then) / 1000)
  if (seconds < 45) return "just now"
  if (seconds < 3600) return Math.max(1, Math.round(seconds / 60)) + " min ago"
  if (seconds < 86400) return Math.round(seconds / 3600) + " hr ago"
  if (seconds < 172800) return "yesterday"
  if (seconds < 7 * 86400) return Math.floor(seconds / 86400) + " days ago"
  var date = new Date(then)
  return date.getDate() + " " + monthShort(date.getMonth())
}

var months = ["January", "February", "March", "April", "May", "June", "July",
  "August", "September", "October", "November", "December"]
var weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

function monthShort(index) {
  return months[index].slice(0, 3)
}

function monthName(index) {
  return months[index]
}

// "2026-06-16" -> a local Date at midnight. Parsed by hand: `new Date(iso)`
// reads a bare date as UTC midnight, which is the day before west of Greenwich.
function dayDate(day) {
  var parts = String(day || "").split("-")
  if (parts.length !== 3) return null
  return new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
}

// "Tue 16 Jun".
function dayLabel(day) {
  var date = dayDate(day)
  if (!date) return String(day || "")
  return weekdays[date.getDay()] + " " + date.getDate() + " " + monthShort(date.getMonth())
}

// The window class a dictation went into, as a person would name the app:
// the last part of a reverse-domain class, first letter raised.
// "com.mitchellh.ghostty" -> "Ghostty", "terminal" -> "Terminals".
function appLabel(cls) {
  var name = String(cls || "")
  if (name === "") return "Unknown app"
  if (name === "terminal") return "Terminals"
  var parts = name.split(".")
  var last = parts[parts.length - 1] || name
  return last.charAt(0).toUpperCase() + last.slice(1)
}

// A vocabulary line read the way the daemon reads words.txt:
// `trigger => expansion` is a snippet, `heard -> written` a replacement,
// anything else a word to prefer; `#` starts a comment.
function vocabLine(line) {
  var text = String(line || "").trim()
  if (text === "") return { kind: "empty" }
  if (text.charAt(0) === "#") return { kind: "comment" }
  var snippet = text.indexOf("=>")
  if (snippet >= 0) {
    return {
      kind: "snippet",
      heard: text.slice(0, snippet).trim(),
      written: text.slice(snippet + 2).trim()
    }
  }
  var replacement = text.indexOf("->")
  if (replacement >= 0) {
    return {
      kind: "replacement",
      heard: text.slice(0, replacement).trim(),
      written: text.slice(replacement + 2).trim()
    }
  }
  return { kind: "word", written: text }
}

// What adding the line will do, in one sentence, or what is missing.
function vocabHint(line, fuzzy) {
  var parsed = vocabLine(line)
  switch (parsed.kind) {
  case "empty":
    return { ok: false, text: "" }
  case "comment":
    return { ok: false, text: "A line starting with # is a comment; Talkify ignores it." }
  case "snippet":
    if (parsed.heard === "" || parsed.written === "")
      return { ok: false, text: "A snippet needs what you say before => and what to insert after it." }
    return { ok: true, text: "Snippet: saying “" + parsed.heard + "” inserts “" + parsed.written + "”." }
  case "replacement":
    if (parsed.heard === "" || parsed.written === "")
      return { ok: false, text: "A replacement needs what Talkify hears before -> and what to write after it." }
    return { ok: true, text: "Replacement: “" + parsed.heard + "” is written as “" + parsed.written + "”." }
  default:
    return {
      ok: true,
      text: "Word: “" + parsed.written + "” wins over words that "
        + (fuzzy ? "sound or are spelled like it." : "are spelled like it.")
    }
  }
}

// "10,000 words", "7-day streak", "100 sessions".
function milestone(kind, value) {
  switch (String(kind)) {
  case "streak": return grouped(value) + "-day streak"
  case "sessions": return count(value, "session")
  default: return count(value, "word")
  }
}

// Momentum against the week before, the Mac's sentence: under 5% either way
// is "about the same"; no previous week says so instead of claiming +100%.
function momentum(m) {
  if (!m || !(Number(m.previous_words) > 0)) return "Nothing to compare with the week before"
  var change = Number(m.change)
  if (!isFinite(change)) return "Nothing to compare with the week before"
  var percent = Math.round(Math.abs(change) * 100)
  if (percent < 5) return "About the same as the week before"
  return percent + "% " + (change > 0 ? "more" : "fewer") + " than the week before"
}
