# Talkify for Omarchy

Talkify for Omarchy is Talkify's Direct Dictation, rebuilt for Omarchy on
Hyprland: hold a key, speak, let go, and the words land in the window you were
typing in. It runs only on Omarchy. Nothing it hears leaves the machine.

It is a port of the macOS app's behaviour and look, not of its code. The Mac
app's rules (the session machine, the tap threshold, the dead-microphone
watchdog, the clipboard restore, the HUD's shape and visuals) are carried over
as written; everything Apple underneath them is replaced.

## Architecture

- `talkify`, one Rust binary: `talkify daemon` runs under systemd as a user
  service; every other subcommand is a client of its Unix socket
  (`$XDG_RUNTIME_DIR/talkify.sock`, one JSON command per connection, `watch`
  streams JSON events)
- `crates/talkify-core` holds every rule that can be pinned without a
  microphone or a window: the session machine, the chord guard, levels and the
  watchdog, the resampler, the chunker, the protocol, the config. It is pure
  and fully unit-tested
- `crates/talkify` is the impure half. One loop owns the session machine;
  keyboard, microphone, engine, insertion and socket each run on a thread and
  report back as messages. Every session has an id, and anything that comes
  back with an old id is dropped, which settles the races
- `plugin/` is an Omarchy shell plugin (Quickshell QML) with three entry
  points: a service that runs `talkify watch`, the bar widget (the ghost and
  the settings menu), and the HUD
- The Speech Model is NVIDIA Parakeet TDT 0.6B v3, int8 ONNX, run on the CPU
  through `parakeet-rs`. It is loaded once and kept warm

## Language

**Direct Dictation**:
A session that turns the user's speech into text for the window that had focus
when it started.
_Avoid_: Voice typing, transcription mode

**Dictation Trigger**:
The key that controls Direct Dictation: hold to talk, tap to latch, tap again
to finish. Right Super by default.
_Avoid_: Hotkey, shortcut

**Chord guard**:
The rule that keeps a modifier trigger from starting a session when it is the
first key of a shortcut. The trigger must be held alone for the guard time, or
tapped alone; any other key or button in between makes it a chord.
_Avoid_: Debounce, delay

**Latched session**:
A session started by a tap rather than a hold. It keeps listening until the
next tap, Escape, or a toggle.
_Avoid_: Hands-free mode, toggle mode

**Live draft**:
The text the HUD shows while the user is still speaking, from re-decoding the
recording so far. It is a preview; the final pass decides what is inserted.
_Avoid_: Partial result, interim transcript

**Speech Model**:
The on-device model that turns speech into text: Parakeet TDT 0.6B v3.
_Avoid_: Engine, Whisper, the AI

**HUD**:
What a session shows while it runs: the voice visual, the live draft, and
messages. It appears in one **HUD placement**.
_Avoid_: OSD, popup, overlay

**HUD placement**:
Where the HUD appears: a pill at the bottom centre (the default), a caption
on the window being dictated into, a halo around that window, an island
inside the Omarchy bar, a dot at the pointer, or Talkify's notch from the
top edge.
_Avoid_: Position, mode, style

**Live insertion**:
Text landing in the window while the user is still speaking, in a latched
session. A word goes in once two passes agree on it and it is no longer at
the edge of the audio; a pause puts the whole phrase in. Only text that will
not change is inserted, because a paste cannot be taken back. A held session
inserts on release instead: a synthetic paste mid-chord confuses the
compositor's record of which keys are down.
_Avoid_: Streaming paste, typewriter mode, real-time typing

**Tidy pass**:
Rule-based cleanup of what the Speech Model heard: fillers and stutters
removed, spoken punctuation ("comma", "new line") turned into marks, "scratch
that" removing the phrase before it. It only removes and punctuates; it never
writes a word that was not spoken. Everything that depends on how words were
said is gated on pauses read from the word timestamps. On by default, unlike
the Mac's rule that anything changing what lands is off: platforms now clean
up by default, and a pass that cannot invent words carries none of the
over-editing risk that rule guards against. Paste again with `--raw` is the way
back.
_Avoid_: AI cleanup, autocorrect, formatting

**Vocabulary**:
The user's words file: words to prefer (matched by sound and spelling),
corrections (`heard -> written`) and snippets (`trigger => expansion`),
applied after decoding because Parakeet takes no hints.
_Avoid_: Dictionary, custom words, glossary

**Teach**:
Learning a correction: the user fixes a misheard word in the app, selects the
fix, and runs `talkify teach`; the daemon finds what the last dictation heard
there and adds `heard -> written` to the Vocabulary.
_Avoid_: Auto-learn, training

**App rules**:
What changes when the text is for one app, chosen by window class: the Tidy
pass, the final period, case, the trailing space, Spoken send. `terminal`
matches every window Omarchy tags as a terminal.
_Avoid_: Profiles, per-app modes, contexts

**Spoken send**:
A send phrase ("send it", "press enter") said last, after a pause, that
presses Enter after the text lands, where App rules allow it.
_Avoid_: Auto-submit, voice enter

**Paste again**:
Inserting a recent dictation once more into the window focused now, as it
landed or as it was heard (`--raw`). **Retry** decodes its kept audio again
first.
_Avoid_: Undo, redo, replay

**Pre-roll**:
Opening the microphone the moment the Dictation Trigger goes down, while the
Chord guard decides, so the first word is never lost; the audio is thrown away
if the press turns out to be a shortcut.
_Avoid_: Buffering, warm mic

**Insights**:
Local usage aggregates per day (words, speaking time, sessions; never text or
app names) and what they add up to: streaks, speed, momentum, the heatmap,
milestones.
_Avoid_: Stats, analytics, telemetry

**Insertion destination**:
Where a finished session's text goes: into the window (the clipboard is put
back afterwards), only onto the clipboard, or both.
_Avoid_: Output mode
