# The daemon's protocol

`talkify daemon` listens on `$XDG_RUNTIME_DIR/talkify.sock`. A client sends one
JSON command per connection, one line. `{"cmd":"watch"}` keeps the connection
open and streams events, one JSON object per line; any other command gets one
line back, `ok` or `error: …`. The CLI wraps every command (`talkify --help`).
The types are `crates/talkify-core/src/protocol.rs`; this page is the map.

Every event field added after the first release has a default, so a plugin
reads events from an older or newer daemon. Text offsets count UTF-16 code
units, which is what JavaScript strings index by.

## Commands

| Command | JSON | Effect |
|---|---|---|
| `talkify watch` | `{"cmd":"watch"}` | stream events |
| `talkify toggle` | `{"cmd":"toggle"}` | start a latched Direct Dictation session, or finish the one in flight |
| `talkify cancel` | `{"cmd":"cancel"}` | cancel the session in flight |
| `talkify press` / `release` | `{"cmd":"press"}` | the trigger as two commands, for compositor binds |
| `talkify tap` | `{"cmd":"tap"}` | a tap seen by the compositor; a toggle only when the daemon cannot read the keyboard |
| `talkify pause` | `{"cmd":"pause"}` | pause or resume the latched session in flight |
| `talkify set KEY VALUE` | `{"cmd":"config-set","key":…,"value":…}` | change a setting |
| `talkify load-model` | `{"cmd":"load-model"}` | load the Speech Model, downloading it if missing |
| `talkify paste-last [N] [--raw]` | `{"cmd":"paste-last","index":0,"raw":false}` | insert a past dictation again into the window focused now |
| `talkify copy-last [N] [--raw]` | `{"cmd":"copy-last","index":0,"raw":false}` | put it on the clipboard |
| `talkify retry [N]` | `{"cmd":"retry","index":0}` | decode its kept audio again and insert the result |
| `talkify teach` | `{"cmd":"teach"}` | learn the primary selection as the spelling of a word the last dictation got wrong |
| `talkify vocab add LINE` / `remove LINE` | `{"cmd":"vocab-add","line":…}` | edit the vocabulary file |
| `talkify history clear` | `{"cmd":"history-clear"}` | forget the recent dictations and their audio |

`index` 0 is the newest dictation. `raw` is the text before the Tidy pass and
the vocabulary.

## Events

`hello`, `engine`, `recording`, `hud`, `history`, `vocab` and `insights` are
all sent on `watch`, so a new client starts complete.

| Event | Fields | Meaning |
|---|---|---|
| `hello` | `version`, `trigger` (`keyboard`/`commands`), `config` | first event |
| `config` | `config` | the whole config after any change |
| `engine` | `status` (`missing`/`downloading`/`loading`/`ready`/`failed`), `detail`, `progress` | the Speech Model |
| `recording` | `active` | a session is running |
| `hud` | see below | what the HUD shows |
| `level` | `level` 0–1 | about 50 a second while recording |
| `mic` | `alive` | false: a dead or muted microphone |
| `result` | `text`, `inserted`, `note`, `raw`, `sent`, `rule` | a finished session, sent before the HUD is told to hide. `raw`: what the Speech Model heard |
| `replayed` | `text`, `inserted`, `note` | paste-last or retry landed (flash it) |
| `history` | `items[]` | recent dictations, newest first |
| `vocab` | `entries[]` (`line`, `kind`, `hits`), `path` | the vocabulary file |
| `taught` | `heard`, `written` | Teach learned a correction |
| `insights` | `insights` | the Insights snapshot, below |
| `milestone` | `kind` (`words`/`streak`/`sessions`), `value` | reached for the first time: celebrate once |

### `hud`

| Field | Meaning |
|---|---|
| `phase` | `hidden`, `listening`, `live`, `finalizing`, `message` |
| `latched` | a tapped session, listening until the next tap |
| `text` | the live draft, or the message |
| `committed` | the start of `text` live insertion already put in the window |
| `paused` | the session is paused: the mic is open, nothing is kept |
| `rule` | the App rules in force (`terminal`, a window class), or `""` |
| `marks[]` | `{start, end, kind, replacement}` over `text`: `filler`, `scratched`, `punctuation`, `vocabulary` (with `replacement`, what it will become), `send` |

Marks describe the live draft as the Tidy pass and the vocabulary will treat
it: a filler that will be dropped, a phrase "scratch that" will remove, a
"comma" that will become a mark, a word the vocabulary will rewrite, the send
phrase. The HUD can draw them before the text lands.

### `history.items[]`

`id`, `at` (unix seconds), `app` (window class), `text`, `raw`, `words`,
`seconds`, `inserted`, `retryable` (its audio is still kept), `rule` (the App
rules that applied).

### `insights.insights`

```json
{
  "total_words": 12840, "sessions": 412, "speaking_seconds": 5460.0,
  "wpm": 141.1, "words_per_session": 31.2,
  "current_streak": 6, "longest_streak": 11,
  "today_words": 820,
  "momentum": { "current_words": 4210, "previous_words": 3020,
                "active_days": 6, "sessions": 120, "change": 0.394 },
  "heatmap": [ { "day": "2026-06-16", "words": 0, "future": false }, … ],
  "typing_wpm": 40, "minutes_saved": 182.4,
  "milestones": [ { "kind": "words", "value": 10000 }, … ]
}
```

`heatmap` is 16 weeks of days, Monday first, oldest first; the days after
today are `future`. `minutes_saved` assumes `typing_wpm` and says so wherever
it is shown. Nothing in Insights holds text or app names.

## Settings the daemon uses

See `crates/talkify-core/src/config.rs`. Sections: `trigger` (`key`,
`chord_guard_ms`, `preroll`), `engine`, `insertion`, `tidy` (`enabled`,
`fillers`, `stutters`, `spoken_punctuation`, `scratch`, `send_phrases`),
`vocab` (`enabled`, `fuzzy`), `media` (`mode`: `pause`/`duck`/`off`,
`duck_to`), `history` (`size`, `save`), `insights` (`enabled`,
`typing_wpm`), `sounds`, `hud` (plus any `hud.*` key the plugin adds), and
`apps.<class>.<field>` App rules with `tidy`, `final_period`, `case`
(`sentence`/`lower`), `trailing_space`, `send` (`never`/`spoken`/`always`).
A value of `""` clears an App rule field. The class `terminal` matches every
window Omarchy tags as a terminal. Precedence: a window's own class rule,
then the `terminal` rule if it is a terminal, then the global settings; each
field falls through on its own. Outside `hud`, a key the daemon does not know
is ignored when the file is read and left out when it is next written.

The file beside the config: `~/.config/talkify/words.txt` (the vocabulary:
`word`, `heard -> written`, `trigger => expansion`, `#` comments).
