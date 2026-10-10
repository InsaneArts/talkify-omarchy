# How dictation apps design the HUD

Research for Talkify for Omarchy's HUD variants. Gathered 2026-10-08 from
product docs, changelogs, help centres, feedback boards and, for the
open-source apps, the source code itself. Where a claim comes from a reviewer
or a user rather than the vendor, the text says so. Where something is my
inference rather than a sourced fact, it is marked **(inferred)**.

Not verifiable from primary sources, and so left thin or out: the look of
MacWhisper's dictation indicator, where Aqua Voice's toolbar sits, where the
Windows voice typing toolbar opens, and the OpenAI help page on ChatGPT voice
(it returned HTTP 403; only the search-engine excerpt was readable).

## Summary

- **Bottom-centre pill is the default for most products.** Wispr Flow, VoiceInk (mini),
  Handy, hyprwhspr and whisrs all put a small dark capsule with level bars
  near the bottom centre. Wispr Flow's users complained enough that a
  third-party app exists only to move the pill, and in July 2026 Wispr made it
  draggable to the left and right edges.
- **The second most common placement is a notch extension at the top.** VoiceInk's notch recorder
  and Willow's "Notch View" grow out of the camera housing. Talkify's current HUD
  belongs here.
- **Some products put the indicator where the text will land.** macOS dictation
  draws a microphone and language tag at the text cursor. Monologue's 2026
  "Dot" sits beside the active text field and follows the pointer when the user
  switches apps. A Superwhisper feature request asks for the same thing (24
  votes).
- **Live words are now common.** VoiceInk, Handy, Superwhisper, Aqua, OpenWhispr
  and hyprwhspr all show what is being heard, in the HUD. Almost none of them
  insert text into the target app while the user speaks. Aqua says why:
  "nothing half-said ever shows up in the box."
- **Apps that do insert while speaking need a commit rule.** On Linux, Voxtype
  holds a word back until two consecutive re-transcriptions agree on it.
  whisrs types a phrase only after a pause, and decodes each phrase once. Both
  found that typing while the hold key is still down breaks key tracking on
  Hyprland. Voxtype therefore turns hold-to-talk into toggle whenever it
  streams.
- **Committed and volatile text are styled differently, usually by opacity.**
  Apple's SpeechAnalyzer sample draws volatile text at 40% opacity. OpenWhispr
  puts a "shimmer" on the last six words. Handy keeps an append-only committed
  prefix but draws the tentative tail in the same colour.
- **Hyprland allows placements that macOS does not.** The target window's
  rectangle is known, the bar can host a widget, and a layer-shell surface can
  draw anywhere. The recommendations below use these: a caption that sits on
  the target window, a halo around the target window, an island inside the bar,
  a dot at the pointer, a bottom pill, and a draft sheet that only appears for
  long Latched sessions.

## Comparison

"Streams into app" means text reaches the target application while the user
is still speaking.

| Product | Placement | Voice visual | Words while speaking | Streams into app |
|---|---|---|---|---|
| Wispr Flow (desktop) | Bottom-centre pill above the Dock; draggable to left/right edge since 2026-07 | White level bars | None documented | No: pastes after release |
| Superwhisper | Floating draggable window, "classic" or "mini" pill; position saved | Waveform | Yes, with realtime models (since 2.10.0) | No: processes after Stop |
| VoiceInk | User picks: notch recorder (top centre) or mini recorder (bottom centre, the default) | 15 white level bars | Yes, scrolling 3-line panel (on by default) | No: pastes final text |
| MacWhisper | Unverified | Unverified | Unverified | Unverified |
| Aqua Voice | "Aqua toolbar" (position unverified); older builds used a floating editable box | Not documented | Yes, in the toolbar: raw tail first, then cleaned text | No: "lands in the app once you finish" |
| Willow Voice | Floating bar, draggable to corners/sides, snaps to edges; optional Notch View | Not documented | Not documented | No: inserts after release |
| Monologue | User picks: Classic (peeks in from the right edge), Mini, or Dot (beside the text field, follows pointer) | Teal waveform (Classic) | Not documented | No (inferred) |
| Raycast Dictation | Pill "above your current app" | Waveform and timer | Only inside Raycast's AI Chat composer | No: pastes on finish |
| Handy | Top or bottom centre, or none; off by default on Linux | 9 level bars, pulsing dot | "Live" style: committed and tentative text, blinking caret | No: preview only, final paste |
| OpenWhispr | Floating draggable pill; starts bottom-right, centre or bottom-left | Small waveform; glow only while "thinking" | Live transcript panel, last 6 words shimmer | No: auto-paste on finish |
| Voxtype (Linux) | OSD card in the system OSD band; also a Waybar icon | Configurable: bars, waveform, ring, pulse, meter, orb | Status only | Optional: agreement-gated or type-and-revise |
| hyprwhspr (Linux) | Bottom centre, 130 px up; notifications on GNOME | Waveform, VU meter or pill | Optional last 4 words in the pill (realtime backends) | Experimental |
| whisrs (Linux) | 100×40 pill, 6 positions, bottom centre by default | Themed pill | No | Yes, phrase by phrase at pauses |
| macOS dictation | At the text cursor | Pulsing highlighted cursor; mic and language tag | Text appears in the field | Yes, in the field (ambiguous words underlined blue) |
| Siri with Apple Intelligence | Full-screen edge glow (iPhone, iPad, CarPlay); a placeable window on Mac | Glow that reacts to voice | Not applicable | Not applicable |
| Windows voice typing | Small floating mic toolbar (Win+H); launcher when a text box has focus | Mic button turns blue; "Listening..." | Text goes into the field | Yes |
| Gboard Assistant voice typing | In the keyboard | Mic icon glows while on | Text in the field, underlined until settled | Yes |
| Pixel Recorder | In-app | Waveform coloured by sound class | Live transcript in the app | Not applicable |
| ChatGPT voice | Full screen "blue orb", or inside the chat | Orb | Transcript in chat (integrated mode) | Not applicable |
| Dragon (Windows) | Results box: a small floating window; Dictation Box for other apps | Recognition icon | Yes, in the Results box first | Yes, after recognition |
| Talon HUD | Status bar plus a speech-history log; widgets remember positions | Mode icon; bar look changes in sleep mode | Past commands, fading out | Not applicable |

## Products

### Wispr Flow

- **Placement.** On Mac the Flow Bar sits "just above the Dock across Spaces,
  whichever side the Dock is on". In full-screen apps it "sits flush against the
  screen edge" ([troubleshooting](https://docs.wisprflow.ai/articles/5002934560-why-is-the-wispr-bar-is-not-appearing-or-disappearing)).
  It follows the display the pointer is on, not the focused window
  ([move and dock](https://docs.wisprflow.ai/articles/1790396454-move-and-dock-the-flow-bar-on-desktop)).
- **Moving it.** Since 2026-07-09 the bar "can now be dragged to the left or
  right edge of your screen instead of staying fixed at the bottom". The reason
  given is to keep it "out of the way of important UI elements like send
  buttons". The position persists ([release note](https://releases.sh/release/rel_ENZi2keTYaYfNSsvVSsAC-flow-bar-drags-to-left-or-right-screen-edge)).
- **Visual and states.** The docs do not describe the visuals beyond this. A
  third-party design reference that quotes Wispr's docs
  ([agent-native corpus](https://cdn.jsdelivr.net/npm/@agent-native/core@0.124.6/corpus/templates/clips/desktop/design-refs/wispr-ux.md))
  says the bar is a dark capsule. When it listens it "expands to display moving
  white vertical bars", and the setup guide says the bars "should stay low when
  you're silent and rise when you speak". Between sessions it can stay on
  screen as an idle bubble that also starts dictation; the setting is "Show
  Flow Bar at all times". A "Hide for 1 hour" snooze has an Undo button. The
  sources disagree on whether the idle bar is on by default.
- **Hands-free.** In hands-free mode the bar shows Cancel and Stop. The user can
  "click the stop (■) icon in the Flow Bar"
  ([hands-free](https://docs.wisprflow.ai/articles/6391241694-Use-Flow-hands-free)).
- **Insertion.** "Release the shortcut and wait for your formatted text to
  appear." Flow pastes through the clipboard and restores the previous contents
  "about half a second after the target app reads the text"
  ([first dictation](https://docs.wisprflow.ai/articles/6409258247-starting-your-first-dictation)).
  It shows no live words.
- **Dead or missing microphone.** Messages such as "Is your microphone muted? /
  We couldn't hear you" and "Microphone unavailable". "Silence warnings clear
  when audio returns" ([mic troubleshooting](https://docs.wisprflow.ai/articles/4351452717-troubleshooting-mic-issues)).
- **Criticism.** PillFloat (launched 2026-04-09) is a separate product whose
  only job is to "Move the Wispr Flow pill anywhere on your screen". Its pitch
  is that the bottom-centre pill covers content
  ([PillFloat](https://webmail.hunted.space/product/pillfloat)). Wispr's own
  July change answers the same complaint.

### Superwhisper

- **Two window styles.** The "classic" recording window has a waveform, a mode
  display, Stop and Cancel. The mini window is "a compact version with the same
  core controls". Superwhisper can keep the mini window visible as a small
  indicator. Hovering it lets the user change mode, start recording or expand
  it. While recording it shows the waveform, and hovering reveals Stop
  ([recording window](https://ai.superwhisper.com/docs/get-started/interface-rec-window.md)).
- **Feedback rules.** "A moving waveform means your microphone is working." If
  it stays still, the docs tell the user to check the input device. Cancel is
  immediate under 30 seconds; longer recordings ask for confirmation. An
  indicator lights when clipboard or selection context is captured.
- **Live words.** "With a realtime-capable voice model, the window shows your
  words as you speak." The changelog has "New realtime streaming UI with live
  transcription display" in 2.10.0 (2026-02-23). Other entries: "Recording
  window now saves position & minification state" (1.40.0), "New Recording
  window Mini mode" (1.46.0), and "Polished mini-mode pill with refined
  animations" (2.16.2) ([changelog](https://superwhisper.com/changelog)). Neither
  the docs nor the changelog document a notch style.
- **User feedback.**
  - "I never want it to go into 'classic' recording mode that covers a ton of
    the screen" (11 votes, [board](https://superwhisper.userjot.com/board/p/can-i-lock-mini-mode)).
  - "the waveform display does not look good; instead, consider implementing a
    simple animation at the bottom of the screen" (11 votes,
    [board](https://superwhisper.userjot.com/board/p/ux-improvement)).
  - A request for a "minimal small recording indicator next to cursor" has 24
    votes. A reply there points to VoiceInk's notch, which "slides in and out of
    view without getting in the way"
    ([board](https://superwhisper.userjot.com/board/p/minimal-small-recording-indicator-next-to-cursor)).

### VoiceInk (open source, macOS)

Read from the source on `main`
([NotchRecorderView](https://github.com/Beingpax/VoiceInk/blob/main/VoiceInk/Features/Recording/Views/NotchRecorderView.swift),
[MiniRecorderView](https://github.com/Beingpax/VoiceInk/blob/main/VoiceInk/Features/Recording/Views/MiniRecorderView.swift),
[AudioVisualizerView](https://github.com/Beingpax/VoiceInk/blob/main/VoiceInk/Features/Recording/Components/AudioVisualizerView.swift),
[RecorderComponents](https://github.com/Beingpax/VoiceInk/blob/main/VoiceInk/Features/Recording/Components/RecorderComponents.swift),
[RecorderUIManager](https://github.com/Beingpax/VoiceInk/blob/main/VoiceInk/Features/Recording/Presentation/RecorderUIManager.swift)).

- **Choice of style.** A setting picks `notch` or `mini`; `mini` is the default.
  Both render on the screen that has keyboard focus, then the screen under the
  pointer, then the first screen.
- **Notch recorder.**
  - **Shape.** A black shape hangs from the top centre. Its width is the notch
    width (or 180 pt with no notch) plus 90 pt on each side while active, and
    110 pt on each side when showing live text.
  - **Height.** The notch height plus 6 pt, plus a 57 pt transcript panel when
    there is text. Corner radii grow from 8/16 to 12/22 when text shows.
  - **Motion.** Expansion is a spring (response 0.42, damping 0.80). Collapse is
    a critically damped spring (0.45, 1.0). Side content fades in 0.09 s after
    the shape starts growing.
  - **Content.** The record button and mode button go on the left wing and the
    visualiser on the right, so the camera housing in the middle stays empty.
- **Mini recorder.**
  - **Shape.** A black pill, 184 × 40 pt with radius 20, centred 24 pt above the
    bottom of the visible frame.
  - **Live text.** It widens to 300 pt and drops to radius 14 when live text
    appears, with an easeInOut 0.3 s animation. The user can drag it.
- **Visualiser.** 15 rounded bars, each 3 pt wide with 2 pt gaps, 4 to 28 pt
  tall. Height comes from the microphone level raised to the power 0.7, times a
  per-bar sine at about 1.3 Hz, with a boost toward the centre. When idle the
  bars are flat 4 pt dots at 50% opacity.
- **Processing.** The bars give way to a "Transcribing" or "Enhancing" label
  above a row of stepping dots, kept at the visualiser's height "to prevent
  layout shift".
- **Live transcript.** 12 pt white text at 80% opacity in a 56 pt panel that
  scrolls to the newest line. Older lines fade under a top gradient mask, and
  text updates are not animated. It is on by default.
- **Insertion.** Streaming providers deliver committed segments, which VoiceInk
  joins; the final text is pasted once at the end
  ([TranscriptionDelivery](https://github.com/Beingpax/VoiceInk/blob/main/VoiceInk/Features/Recording/Workflows/TranscriptionDelivery.swift)).

### MacWhisper

The dictation help article only says the feature "lets you transcribe audio
into any text field directly"
([docs](https://docs.macwhisper.com/article/14-how-to-use-the-dictation-feature)).
A Superwhisper user says MacWhisper, like macOS dictation, uses a small
indicator near the cursor
([board](https://superwhisper.userjot.com/board/p/minimal-small-recording-indicator-next-to-cursor)).
That is unverified.

### Aqua Voice

- **Modes.** "Instant Mode": press, talk, release, then see text. "Realtime
  mode", formerly "Streaming Mode": "words appear in real time as you talk"
  ([llms.txt](https://aquavoice.com/llms.txt)).
- **Where the words go.** "The live transcript stays in the Aqua toolbar. Your
  message only lands in the app once you finish, so nothing half-said ever shows
  up in the box." The styling of the words: "The raw tail arrives soft at the end of the line, then
  resolves into clean, punctuated text a beat behind your voice"
  ([realtime](https://aquavoice.com/realtime)).
- **Earlier design.** A reviewer describes "a floating text box on your
  desktop" that the user could edit before pasting. The reviewer's criticism:
  "The floating text box, while clean, can feel discordant compared to
  dictating directly into your intended app"
  ([aestumanda review, 2025-08](https://www.aestumanda.com/reviews/2025/08/aqua-voice-delivers-what-apples-dictation-still-lacks/)).
  The current toolbar's position on screen is not documented.

### Willow Voice

- **The bar.** Holding the hotkey shows "a small floating bar", and text lands
  "right where your cursor was" after release. A double tap starts hands-free
  ([help](https://help.willowvoice.com/en/articles/10876920-dictating-with-willow-voice)).
- **Moving and hiding it.** The user can "Drag it to any corner" or "Move it
  along either side of your display". An "Enable Notch View" setting replaces
  the floating bar ([help](https://help.willowvoice.com/en/articles/13706888-how-do-i-get-rid-of-the-floating-app-icon-or-the-bar)).
  Mac v1.9 (2026-01-17) added a "Draggable Highlight Bar with Snap-to-Edge"
  ([changelog](https://internal-changelog.willowvoice.com/)). A "Hide dictation
  bar when not recording" setting exists, according to the help-centre search
  excerpt.

### Monologue

Monologue has three indicator styles.

- **Classic.** A reviewer describes a small "monophone" window "peeking in from
  the right". When the shortcut is pressed it "pops out from the side and starts
  dictating, with the waveform reacting as you speak". The waveform is teal and
  the colour can be changed
  ([Cassinelli](https://matthewcassinelli.com/recommended-apps-monologue-mac-ios/)).
- **Mini.** Added in macOS 1.4.2, alongside a menu-bar recording indicator that
  was made "easier to see at different display scales"
  ([changelog](https://www.monologue.to/changelog)).
- **Following Cursor and Dot.** Following Cursor mode arrived in 1.2.0
  (2026-05-25). 1.2.1 refined it around screen edges, multiple displays, the
  Dock and the menu bar, and added an option to hide the idle indicator. Dot
  came in 1.5.0 (2026-08-24): "Dot sits beside the active writing field and
  shows when Monologue is listening and turning your speech into text."
  "Switch apps while you record and Dot follows your pointer." The user can hide
  Dot, turn it off per app, or go back to Classic, and can report placement
  problems from the indicator itself
  ([Dot release](https://www.monologue.to/changelog/2026-08-24-meet-the-dot)).
  The point of Dot, per the release: "See where your text will appear."

### Raycast Dictation

The "Dictation Pill" appears "above your current app" with a live waveform and
a timer. Holding the hotkey makes it push-to-talk: the session ends on release.
Live text appears only in Raycast's own AI Chat composer. Elsewhere the output
is pasted, copied, or both. "Context-Aware Paste" adjusts the leading space and
capitalisation to the text before the cursor
([manual](https://manual.raycast.com/ai/dictation.md)).

### Handy (open source, Tauri; macOS, Windows, Linux)

Read from the source on `main`
([RecordingOverlay.tsx](https://github.com/cjpais/Handy/blob/main/src/overlay/RecordingOverlay.tsx),
[RecordingOverlay.css](https://github.com/cjpais/Handy/blob/main/src/overlay/RecordingOverlay.css),
[overlay.rs](https://github.com/cjpais/Handy/blob/main/src-tauri/src/overlay.rs),
[transcription.rs](https://github.com/cjpais/Handy/blob/main/src-tauri/src/managers/transcription.rs),
[README](https://github.com/cjpais/Handy)).

- **Settings.** Style `none`, `minimal` or `live`; position `top` or `bottom`.
- **Linux.** The window is a gtk-layer-shell surface on the overlay layer.
  Top margin is 4 px on Linux and Windows (46 px on macOS, to clear the menu
  bar); bottom margin is 40 px. It opens on the monitor under the pointer. The
  README says it is "disabled by default on Linux ('Overlay Position: None')
  because certain compositors treat it as the active window". When visible it
  "can steal focus, which prevents Handy from pasting back into the
  application". For Hyprland and Omarchy the README suggests running with
  `GDK_BACKEND=wayland`.
- **Minimal style.**
  - **Shape.** A 40 px tall pill. Its width animates between 172 px (listening)
    and 216 px (working), and it fades in over 200 ms.
  - **Rows.** One row at a time. Listening shows a pulsing dot, 9 level bars
    (3 to 18 px, smoothed 0.7/0.3) and a cancel button. Working shows a
    spinner and a "Transcribing" or "Processing" label.
- **Live style.**
  - **Shape.** The pill "sculpts open" into a 392 px panel, with its radius
    going from 24 to 16. It pops in with a 460 ms `cubic-bezier(0.22, 1, 0.36, 1)`
    scale from 0.92. The scale is anchored at the screen edge, so the card never
    moves past that edge.
  - **Text.** Text grows away from the edge: down from a top placement, up from
    a bottom one. It is capped at 64 px and scrolls. A blinking accent caret
    follows the text, and older lines fade out under the pill only once the
    text overflows. The text stays pinned to the newest line unless the user
    scrolls back.
  - **Controls.** An elapsed timer and a cancel button.
- **Arming state.** Until the first real microphone sample arrives, the dot is
  muted and the bars show "a muted travelling pulse". The code says this
  "acknowledges the shortcut without pretending that audio levels are already
  being received".
- **Model loading.** If loading the model takes more than 2 s, the panel shows a
  notice where the text would go, "so speech that isn't transcribing yet doesn't
  look ignored". A fast load never flashes the notice.
- **Committed and tentative text.** The engine emits a `committed` string, "the
  append-only, flicker-free prefix", and a `tentative` string, "the volatile
  suffix the model may still rewrite". The overlay styles the tentative span
  with `color: inherit`, so the two look the same.
- **Finalizing.** The panel stays open with the text in place under a spinner:
  "instead of collapsing and squishing the text mid-stream". The caret is
  dropped. The final paste re-decodes; "The preview is cosmetic".

### OpenWhispr (open source, Electron)

Read from the source
([VoicePill.tsx](https://github.com/OpenWhispr/openwhispr/blob/main/src/components/dictation/VoicePill.tsx),
[voicePillPresentation.js](https://github.com/OpenWhispr/openwhispr/blob/main/src/helpers/voicePillPresentation.js),
[windowConfig.js](https://github.com/OpenWhispr/openwhispr/blob/main/src/helpers/windowConfig.js),
[liveTranscriptPresentation.ts](https://github.com/OpenWhispr/openwhispr/blob/main/src/utils/liveTranscriptPresentation.ts),
[settingsStore.ts](https://github.com/OpenWhispr/openwhispr/blob/main/src/stores/settingsStore.ts)).

- **Placement.** A floating, draggable pill. `panelStartPosition` is
  `bottom-right` (default), `center` or `bottom-left`, and there is an
  auto-hide option. The pill docks 12 px from the window's bottom corner.
- **Size and motion.** The idle pill is 40 × 40. Recording makes it 98 × 36: a
  22 px icon and a 52 px waveform. The entrance holds for 260 ms ("reads as an
  acknowledged press"), expands over 300 ms, then reveals the waveform 100 ms
  later. Hovering brings out a cancel control beside the pill.
- **Design rationale in the code.**
  - The "comet orbit over a breathing halo" glow appears only in the thinking
    state, because "glowing during the entrance or while listening would read as
    work already in flight before any transcript exists".
  - A previous "wide recording bar made the control feel like a different
    surface".
- **Live transcript.** A panel shows the transcript. The trailing six words are
  the "active" part with a shimmer, and the rest is "settled": the code keeps
  "the newest phrase visually active without making the completed body flicker".
  The assistant feature streams into a floating panel only "when no writable
  cursor is available" ([README](https://github.com/OpenWhispr/openwhispr)).

### Voxtype (Linux)

Sources: the [README](https://github.com/peteonrails/voxtype),
[CONFIGURATION.md](https://github.com/peteonrails/voxtype/blob/main/docs/CONFIGURATION.md),
[quickshell/README.md](https://github.com/peteonrails/voxtype/blob/main/quickshell/README.md)
and [WAYBAR.md](https://github.com/peteonrails/voxtype/blob/main/docs/WAYBAR.md).

- **Placement.** A "Floating waveform OSD". It "Matches your swayosd band by
  default — same vertical position as volume and brightness — so the level
  meter sits where you already look for system feedback". The showcase recipes
  set `top_margin = 0.74` to sit above the lower-band system OSDs.
- **Frontends.** GTK4 (the default), native wgpu, and Quickshell, which has
  shipped since v0.7.5 and targets "Omarchy 4+". The Quickshell card is a
  `PanelWindow` on `WlrLayer.Overlay` with no keyboard focus.
- **State colour.** "a red tint and live waveform during `recording`, blue
  during `streaming`, amber during `transcribing`, and disappears at `idle`."
- **Customisation.**
  - Layouts `compact`, `wide`, `minimal`, `tile` and `orb`.
  - Stackable recipe layers `shadow`, `background`, `waveform`, `bars`, `pulse`,
    `ring`, `meter`, `icon` and `label`, driven by `peak`, `rms`, `vad` or
    `state`.
  - The frame has optional voice-reactive `glow` and `halo`.
  - `palette = "omarchy"` resolves colours from the active Omarchy theme and
    reloads live when the theme changes.
- **Bar.** The Waybar module reads `voxtype status --follow --format json`. The
  suggested CSS turns the icon red and pulsing while recording and yellow while
  transcribing.
- **Streaming insertion.** See the streaming section below. Voxtype has the
  most detailed documentation on this of any product here.

### hyprwhspr (Linux, Hyprland-first)

Sources: the [README](https://github.com/goodroot/hyprwhspr),
[FEEDBACK.md](https://github.com/goodroot/hyprwhspr/blob/main/docs/usage/FEEDBACK.md)
and [window.py](https://github.com/goodroot/hyprwhspr/blob/main/lib/mic_osd/window.py).

- **Placement.** The "mic OSD" is a gtk4-layer-shell overlay, 300 × 60, anchored
  bottom centre with a 130 px margin and no keyboard input. On GNOME and X11
  it falls back to desktop notifications ("recording / transcribing /
  inserted"), which "never steal the focus the paste needs".
- **Styles.**
  - `waveform` (the default): a themed waveform with a transcript preview.
  - `vu_meter`.
  - `pill`: "a compact monochrome status pill: idle dots, live bars while
    recording, a travelling wave while processing, a pulse on error, and a
    checkmark on success."
- **Pill transcript.** Opt-in; it "Shows the last few words while recording".
  The default is 4 words (configurable from 1 to 12), and it hides after 1400 ms
  of idle. It needs a streaming backend. "Final transcription and paste are
  unaffected."
- **Theme and bar.** Colours follow the Omarchy and Noctalia themes. There are
  Waybar and Noctalia bar modules.
- **Streaming.** The README lists "type as you speak (experimental)" for
  self-hosted streaming backends.

### whisrs (Linux, Rust)

Sources: the [README](https://github.com/y0sif/whisrs) and
[configuration.md](https://github.com/y0sif/whisrs/blob/main/docs/configuration.md).

- **Overlay.** Off by default. A 100 × 40 pill (clamped to 90–120 × 36–48) with
  themes `carbon`, `ember`, `cyan` or `custom`, and colours for recording,
  transcribing and glow.
- **Position.** `bottom-center` (default), `bottom-left`, `bottom-right`,
  `top-left`, `top-center` or `top-right`, 16 px from the screen edges.
- **No double signals.** When the overlay is on, the recording and
  transcribing toasts are suppressed "so the same event isn't double-signaled".
  Errors still pop up.
- **Streaming.** whisrs types as it goes. See the streaming section.

### macOS dictation (Apple)

- **Indicator.** "When the cursor is highlighted and pulsing, or you hear the
  tone that signals your Mac is ready for dictation, dictate your text." On
  Apple silicon the pulsing stops while the user types and resumes afterwards.
  A language tag next to the cursor switches language.
- **Text in the field.** "Ambiguous text is underlined in blue." "The new line
  or new paragraph appear when you're done dictating." Dictation stops after 30
  seconds of silence
  ([Apple guide](https://support.apple.com/guide/mac-help/use-dictation-mh40584/mac)).
- **Since Sonoma.** The indicator sits under the text cursor in the accent
  colour and shows the language
  ([MacMost](https://macmost.com/turning-off-the-caps-lock-and-other-text-cursor-indicators-on-your-mac.html)).
  AbilityNet describes a "blue microphone icon" at the cursor that stops
  dictation when clicked
  ([AbilityNet](https://mcmw.abilitynet.org.uk/how-to-dictate-text-in-macos-14-sonoma)).
- **Text appears as spoken.** Text appears in the field while the user
  speaks. Apple's guide implies this without stating it outright. **(inferred
  from the guide's wording and common use)**
- **Speech API.** Apple's speech-to-text API for developers distinguishes
  "volatile results" ("delivered almost as soon as they're spoken but they are
  less accurate guesses") from a finalized result. Its sample shows "the
  volatile results in a lighter opacity, replaced by the finalized results when
  they come in" (`.purple.opacity(0.4)`)
  ([WWDC25 session 277](https://developer.apple.com/videos/play/wwdc2025/277/)).

### Siri with Apple Intelligence

- **iPhone, iPad, CarPlay.** "an elegant glowing light that wraps around the
  edge of the screen when active". **Mac:** "users can place Siri anywhere on
  their desktop"
  ([Apple Newsroom, 2024-10](https://www.apple.com/newsroom/2024/10/apple-intelligence-is-available-today-on-iphone-ipad-and-mac/)).
- **macOS 15.1 release notes.** As quoted by iClarified, they describe the glow
  as one that "animates responsively to the sound of your voice, and lets you
  keep scrolling or typing while you talk to Siri"
  ([iClarified](https://www.iclarified.com/95263/macos-sequoia-151-release-notes/amp)).
  The two Apple sources do not settle whether the Mac glow lights the screen
  edge or the placeable Siri window.

### Windows voice typing

- **Toolbar.** Win+H opens it. It "will start listening automatically. Wait for
  the 'Listening...' alert". A gear opens settings, including the "Voice typing
  launcher", which opens voice typing whenever a text box has focus
  ([Microsoft Support](https://support.microsoft.com/en-us/windows/use-voice-typing-to-talk-instead-of-type-on-your-pc-fec94565-c4bd-329d-e59a-af033fa5689f)).
  The launch post describes "A modern design – optimized for use with touch
  keyboards". A hardware keyboard gets a floating microphone button
  ([Insider build 20206](https://blogs.windows.com/windows-insider/2020/09/02/announcing-windows-10-insider-preview-build-20206/)).
- **States.** The button "will turn blue to show that Voice typing is active"
  ([AbilityNet](https://mcmw.abilitynet.org.uk/how-to-use-voice-typing-in-windows-11)).
  Text is typed into the box as the user speaks
  ([Laptop Mag](https://www.laptopmag.com/how-to/windows-voice-to-text)).
- **Touch keyboard, 2025-12.** Microsoft replaced the old overlay: "No overlay;
  dictation state animations are shown directly on the dictation key"
  ([Insider build 26220.7522](https://blogs.windows.com/windows-insider/2025/12/19/announcing-windows-11-insider-preview-build-26220-7522-dev-beta-channels/)).
  The change goes toward a smaller indicator, not a bigger one.

### Gboard Assistant voice typing and Pixel Recorder

- **Gboard.** On Pixel 6 and later, the "colorful microphone icon" means voice
  typing is on. "If your microphone is still on, the microphone icon continues
  to glow." Double-tapping the mic keeps it on. The user can type while the mic
  is on, and can edit by voice ("delete", "clear")
  ([Gboard help](https://support.google.com/gboard/answer/11197787?hl=en)). The
  search excerpt of the same page says text spoken before a pause "is
  transcribed and entered in the text field, underlined", which is the
  provisional marking.
- **Pixel Recorder.** Transcribes live and draws "a colored waveform where each
  color is associated with a different sound category". Each bar covers 50 ms
  ([Google Research](https://research.google/blog/the-on-device-machine-learning-behind-recorder/)).

### ChatGPT voice

The help centre says voice can appear "inside the main chat page or separate
mode (the blue orb screen)". A setting, Settings → Voice → Separate Mode,
switches between them. The integrated mode puts the conversation in the chat
transcript ([help.openai.com](https://help.openai.com/articles/8400625),
search excerpt only: the page returned 403). It is a conversation interface,
not dictation. It is included here because it is the best-known orb.

### Dragon

- **Results box.** As the user talks, "text displays in the Results box while
  Dragon figures out what you said". One guide calls it a small yellow window
  ([Bangor quick start](https://www.bangor.ac.uk/access-centre/documents/QuickStart_Dragon.pdf)).
  Dragon showed the volatile hypothesis in a separate box before committing to
  the document long before current apps did.
- **Moving and hiding it.** The Results Display icon can be dragged, anchored,
  or set to auto-hide "when you haven't spoken for 10 seconds"
  ([Nuance](https://nuance.com/products/help/dragon156/dragon-for-pc/enx/professionalindividual/Content/Dictation/working_with_the_results_display.htm)).
- **Dictation Box.** For apps without full text control, the Dictation Box is a
  movable, resizable editor whose text is transferred afterwards
  ([Nuance](https://www.nuance.com/products/help/dragon15/dragon-for-pc/enx/dpg-cp/Content/Dictation/using_the_dictation_box.htm)).

### Talon HUD

- **Status bar.** The community HUD has a status bar with a mode indicator. The
  status bar "will always show whether you are in sleep mode or not at a glance
  ... by changing the appearance of the status bar itself". It can also hold a
  microphone toggle and a focus indicator.
- **Speech history.** "Taking inspiration from FPS games", it shows recent
  commands and clears itself "after a few seconds".
- **Positions.** Widgets keep their positions per monitor setup
  ([talon_hud](https://github.com/DashingDevelopers/talon_hud)).

## Patterns

### Placement archetypes

1. **Notch extension (top centre).** VoiceInk notch, Willow Notch View, Handy
   `top`, Talkify. It grows from a fixed point and is where users already look
   for system status on a notched Mac. On a screen with no notch it needs a
   simulated housing.
2. **Bottom-centre pill.** Wispr Flow, VoiceInk mini, Handy `bottom`,
   hyprwhspr, whisrs. Most products use it. Its known cost is covering send
   buttons and docks (PillFloat; Wispr's July change).
3. **Edge-docked or peeking.** Monologue Classic (right edge), Wispr's
   left/right edge docking, Willow's snap to edges. It is out of the way
   until it slides in.
4. **Free-floating window.** Superwhisper classic, Aqua's older box, OpenWhispr,
   the Dragon Dictation Box, Siri on Mac. It is flexible, but users complain
   when it is large (Superwhisper "covers a ton of the screen").
5. **At the text cursor.** macOS dictation, Gboard, Windows launcher. Monologue
   Dot gets close by sitting beside the text field. It shows where the text
   will land. On Wayland the caret position is not available to Talkify
   (see the note under the recommendations).
6. **At the pointer.** Monologue Dot follows the pointer when the user switches
   apps; Superwhisper users ask for it. It is near where the user is looking,
   but the pointer is not always where text goes.
7. **In the status bar.** Voxtype and hyprwhspr Waybar modules, Monologue's menu
   bar indicator, Talon's status bar, Talkify's ghost. It never covers content,
   but it is small and easy to miss.
8. **Screen edge.** Siri with Apple Intelligence. It is impossible to miss and
   says nothing about where text goes.
9. **System OSD band.** Voxtype sits where the volume and brightness OSDs
   appear.
10. **Notifications.** hyprwhspr's fallback on GNOME. It is chosen because it
    cannot steal focus.

### Voice visual archetypes

1. **Level bars.** Wispr, VoiceInk (15), Handy (9), hyprwhspr pill, Talkify
   Compact (5). Most products use them. They read clearly at small sizes. Nearly
   all add per-bar phase so the cluster reads as sound, not a meter.
2. **Scrolling waveform or oscilloscope.** Superwhisper, hyprwhspr `waveform`,
   Voxtype, Pixel Recorder (coloured by sound class), Talkify Chart Line. It
   shows history as well as the current level.
3. **Orb, ring or pulse.** ChatGPT, old Siri, Voxtype `orb` layout, Handy's
   pulsing dot, Apple's pulsing caret. It has no direction, so it suits small
   anchored indicators.
4. **Edge glow.** Siri, Talkify Edge Glow, Voxtype frame `glow`/`halo`. It
   needs a large surface or a frame to light.
5. **Icon state only.** Waybar icons, the Windows mic turning blue, Gboard's
   glowing mic, Windows' new "animations on the dictation key".
6. **Text as the visual.** Aqua's toolbar, Dragon's Results box, Superwhisper
   realtime, Handy Live. The words themselves show that it is listening.

### Words: how much, and how styled

- **None.** Wispr Flow, Willow, Raycast outside its own composer, all the pill
  minimal modes.
- **Last few words.** hyprwhspr pill (default 4, hides after 1.4 s idle).
  Talkify's "Tail Only". OpenWhispr marks the last 6 as active.
- **A short scrolling panel.** VoiceInk (56 pt) and Handy (64 px cap). Both pin
  to the newest line and fade older lines under a gradient at the edge nearest
  the controls.
- **A full editable box.** Aqua's older box and the Dragon Dictation Box.
  Reviewers found it "discordant" next to dictating straight into the app.
- **In the field itself.** macOS, Windows, Gboard. Provisional text is underlined.

Styling of unstable text: Apple draws it at 40% opacity, Aqua's raw tail
"arrives soft" and resolves, OpenWhispr uses a shimmer on the active words,
Gboard and Apple underline provisional text in the field, and Handy does not
mark it.

### State signals

| State | Signals seen |
|---|---|
| Arming (shortcut seen, no audio yet) | Handy's muted dot and "travelling pulse"; Superwhisper 1.45.2 "Show window immediately, display initializing state" |
| Listening | Level bars rising and falling; pulsing dot or caret; Voxtype red tint |
| Silence vs. no audio | Wispr "We couldn't hear you"; Superwhisper "If the waveform stays still" check your device; Talkify's amber static state |
| Latched / hands-free | Wispr shows Stop and Cancel buttons; Handy shows an elapsed timer; Gboard's mic keeps glowing |
| Model loading | Handy's notice after 2 s; Superwhisper "initializing" |
| Processing / finalizing | VoiceInk label plus stepping dots, kept at the same height; Handy spinner, text kept in place; hyprwhspr travelling wave; Voxtype amber; OpenWhispr comet glow |
| Success | hyprwhspr checkmark; Wispr: the pasted text is the signal |
| Error | hyprwhspr pulse; Wispr messages; whisrs still pops error toasts with the overlay on |

### Motion details worth copying

- **Grow from the anchored edge with scale, never by translating past it**
  (Handy). This is the same rule Talkify's Mac HUD already follows.
- **Delay the content slightly after the shape starts to grow** (VoiceInk
  0.09 s; OpenWhispr 260 ms hold, 300 ms expand, waveform 100 ms after). The
  shape change and the content change then read as separate steps.
- **Keep the text where it is during finalizing** (Handy). Collapsing it
  "squishes the text mid-stream".
- **Hold the processing indicator at the visualiser's height** (VoiceInk)
  so nothing jumps.

## Streaming insertion ("paste as you speak")

Most apps show live words in the HUD and insert once at the end. The ones that
insert progressively use one of these commit policies:

1. **Agreement across re-decodes (LocalAgreement-n).** whisper_streaming: "if n
   consecutive updates, each with a newly available audio stream chunk, agree on
   a prefix transcript, it is confirmed". It uses n = 2 and trims the audio
   buffer at confirmed sentences
   ([whisper_streaming](https://github.com/ufal/whisper_streaming)). Voxtype's
   default does the same thing.
   - **Voxtype's version.** It re-transcribes a rolling buffer every
     `interval_secs` (0.8 s) and emits "stable-prefix deltas". It needs
     `min_audio_secs` (1.0) before the first partial, and `partial_min_words`
     (1) new stable words before typing. Each word is withheld "until it's
     agreed across two consecutive re-transcriptions — safe (never types
     something wrong) but can pause for a long stretch if Whisper keeps
     re-wording the same short phrase"
     ([CONFIGURATION.md](https://github.com/peteonrails/voxtype/blob/main/docs/CONFIGURATION.md)).
2. **Type and revise, with a bounded look-back.** Voxtype's experimental
   `revision_mode` "types its current best guess immediately and corrects it
   later (backspace + retype)". After 4 newer words a word is "locked in and can
   never be revised again". The documented risk: "a wrong backspace count could
   in principle remove characters that weren't typed by voxtype at all ... (e.g.
   focus moved mid-correction)."
3. **Commit at pauses, decode each phrase once.** whisrs splits audio "into
   phrases at natural pauses and decode[s] each phrase exactly once. No overlap,
   no dedup — prevents repeated/invented text". Continuous speech is force-split
   after 20 s (hard ceiling 28 s). For realtime servers "whisrs only types
   completed text ... It does not type unstable partial hypotheses as they
   change" ([configuration.md](https://github.com/y0sif/whisrs/blob/main/docs/configuration.md)).
4. **Trust the engine's finality flags.** Soniox "guarantees stable finals;
   non-finals can be revised", and Voxtype's `type_partials = false` types only
   finals. Handy's engine gives an append-only `committed` prefix. Apple gives
   `isFinal`. VoiceInk collects `committed` segments.
5. **Leave it to the platform as composition text.** macOS, Windows and Gboard
   put provisional text into the field and mark it (blue or plain underline).
   They own the text field, so they can do this without risk; a third-party app
   on Wayland cannot. **(inferred)**
6. **Do not stream into the app at all.** Aqua's stated policy ("nothing
   half-said ever shows up in the box"), and VoiceInk, Handy, Wispr and Talkify
   today.

Lessons that apply directly to Hyprland:

- **Typing while the trigger is held breaks key tracking.** "synthetic key
  events emitted by `wtype` and `dotool` clobber the held-key state tracker, so
  the release of a held PTT key never fires `bindrd`". Voxtype therefore
  "auto-promotes `push_to_talk` to `toggle` at startup when streaming is
  enabled" (Voxtype CONFIGURATION.md). whisrs never types while a modifier is
  held. If the modifier is still down when its wait runs out, the text goes to
  the clipboard instead. For Talkify, whose Dictation Trigger is held Right
  Super, progressive insertion only makes sense in a Latched session.
  **(inferred)**
- **Post-processing and streaming do not mix.** whisrs: with streaming "no
  whole transcript ever exists to post-process and the flag is a silent no-op".
- **Each typing call costs time.** Voxtype measured ~700–800 ms per `dotool`
  spawn and recommends the `dotoold` daemon for streaming.
- **Focus can move between commits.** Voxtype's revision mode warns about it.
  Talkify already checks focus before inserting, and a progressive mode would
  need that check before every commit. **(inferred)**

A commit policy that fits Talkify, which already re-decodes the whole
recording for the Live draft **(inferred, not tested)**:

- **Where it applies.** Only in Latched sessions, and only when the insertion
  destination is the window.
- **Commit rule.** Commit a prefix only when two consecutive Live drafts agree
  on it, it ends at a sentence boundary (the Speech Model's own punctuation),
  and at least ~400 ms of silence has followed it.
- **Never revise.** Committed text is append-only. Keep the committed prefix
  and type only the new delta.
- **At finish.** When the final pass runs, check whether its text starts with
  what was committed. If it does, insert only the rest. If it does not, insert
  nothing more and put the full final text on the clipboard, with a HUD message.
  Never backspace text the user may have edited.
- **On a focus change.** Stop committing; the rest waits on the clipboard,
  as today.
- **Clipboard cost.** Paste-based insertion restores the clipboard after each
  commit. Typing the deltas through the virtual keyboard may be cheaper than a
  paste per sentence. This needs measuring.

## Recommendations for Talkify on Omarchy

Facts the variants rely on:

- **Layer-shell surfaces** can be placed anywhere on an output, and Talkify
  already keeps one HUD surface mapped per display.
- **Hyprland reports** the session window's rectangle (`hyprctl activewindow
  -j`: `at`, `size`, `fullscreen`) and the pointer position (`hyprctl
  cursorpos`). Focus, workspace and fullscreen changes arrive as socket2
  events. Window geometry and pointer movement have to be polled during a
  session. **(inferred)**
- **The Omarchy bar** is a Quickshell bar Talkify already draws in (the ghost).
- **The caret position** is not available.
- **One surface can draw everything (inferred).** If the HUD surface covered the
  whole output with an empty input mask, every placement below would just be a
  drawing position inside it, with no remapping. Remapping would bring back
  Hyprland's layer fade.

Every variant keeps the Mac app's rules:

- **Dead microphone.** Amber and static, never just flat.
- **Reveal.** By anchored scale, never by position overshoot.
- **Final pass.** The final pass, not the Live draft, decides what is inserted.

### Variant 0: Notch (the current HUD)

Kept as the default. A black shape grows from the top edge under the bar and
carries Chart Line, Edge Glow or the Live draft. Nothing here argues for
changing it. Every variant below is an alternative to it.

### Variant 1: Window Caption (anchored to the target window, words on)

- **Size and anchoring.** A black caption pill pinned to the bottom centre of
  the window the session started in, inset 16 px from the window's bottom edge.
  Width is `min(0.6 × window width, 560 px)`; height is 36 px for one line and
  58 px for two. The rectangle comes from the window address the daemon already
  records at session start. During the session it re-reads the rectangle on
  socket2 events and polls it a few times a second, so a floating window that
  moves takes the caption with it. **(inferred)**
- **Motion.** It grows upward from its bottom edge with the same spring as the
  Notch.
- **Words.** The Live draft, with the settled part in white and the last few
  words at about 50% opacity. With "Tail Only" the head is truncated; otherwise
  it grows to two lines.
- **Latched sessions.** A thin ring on the left end closes into a solid dot, and
  an elapsed time appears on the right.
- **Dead microphone.** The pill border and the dot turn amber and the text area
  says so.
- **Finalizing.** The text stays put while a soft sweep runs left to right
  across it.
- **Focus change.** If focus leaves the window, the caption stays on the
  original window and changes to "Will go to clipboard", matching the existing
  rule for the insertion destination.
- **Fallback.** A window narrower than 320 px or taller than wide falls back to
  the Notch.
- **Why.** It is the closest thing Wayland allows to dictating "at the
  cursor" (macOS dictation, Monologue's "See where your text will appear"). It
  also shows which window will receive the text, which no other HUD here does.

### Variant 2: Window Halo (glow around the target window, words off)

- **Size and anchoring.** A soft glow, 6 to 18 px wide, drawn just outside the
  session window's border and following its corner radius. The glow is brightest
  along the bottom edge.
- **Motion.** On session start the glow travels around the window from the
  bottom centre in 250 ms. Intensity and width then follow the voice level, as
  Siri's "animates responsively to the sound of your voice". On a fullscreen
  window it becomes the screen-edge glow.
- **Words.** None. It can be paired with Variant 1 for users who want words.
- **Latched sessions.** The gradient rotates slowly around the window, so a
  session that keeps listening without the key held looks different from a
  held one.
- **Dead microphone.** The halo freezes amber and stops reacting.
- **Finalizing.** The glow drains back toward the bottom centre and fades when
  the text lands.
- **Why.** It adapts Talkify's existing Edge Glow shader to a window. It covers
  no content, and it marks the target window without any text.

### Variant 3: Bar Island (inside the Omarchy bar, words optional)

- **Size and anchoring.** The ghost in the bar widens into a pill inside the
  bar's own height (bar height minus 6 px). It is centred in the bar or kept at
  the widget's slot, as the user chooses. It grows to 220 px for the voice
  visual and up to 420 px with words. No layer surface is used.
- **Motion.** The island widens from the ghost, the same morph as Handy's pill
  changing width. On release it shrinks back to the ghost.
- **Words.** Optional. One line with the last 4 to 6 words, like hyprwhspr's
  pill transcript; the head scrolls off.
- **Voice visual.** Five bars, the existing Compact indicator.
- **Latched sessions.** The ghost's eyes stay open and a small lock tick
  appears at the left end.
- **Dead microphone.** The bars freeze amber.
- **Finalizing.** The bars become three stepping dots.
- **Hidden bar.** If the bar is hidden (fullscreen) or not at the top, it falls
  back to the Notch.
- **Why.** It is the least intrusive option that is still visible, and it fits
  Omarchy's look. It is the bar-resident pattern (Talon, Voxtype and hyprwhspr
  Waybar modules) made rich enough to replace the HUD for users who find any
  floating shape distracting.

### Variant 4: Pointer Dot (at the mouse pointer, words off)

- **Size and anchoring.** A 22 px ring placed 18 px below and right of the
  pointer at session start. It flips to the other side near screen edges.
- **Pointer tracking.** It follows the pointer only while the pointer is on the
  session window's monitor, polling `cursorpos` at about 30 Hz during a
  session. Easing over about 80 ms keeps it from jittering.
- **Motion.** The ring's radius and thickness breathe with the level, an orb
  reduced to its outline. It scales in from 0.6.
- **Words.** None.
- **Latched sessions.** A filled centre dot inside the ring.
- **Dead microphone.** The ring is static amber.
- **Finalizing.** A short arc spins around the ring, and it scales out when the
  text lands.
- **Why.** Monologue shipped this (Following Cursor and Dot) and Superwhisper
  users asked for it (24 votes, "The big SuperWhisper window is a bit
  disruptive"). It is the smallest HUD that still shows the voice.
  It is also useful on large or multi-monitor setups, where the top centre may
  be far from where the user is looking.

### Variant 5: Bottom Pill (bottom centre, words on or off)

- **Size and anchoring.** A 184 × 40 px black pill, 40 px above the bottom
  edge of the session's monitor.
- **Words on.** It grows upward into a panel up to 420 × 110 px. The newest
  line sits at the bottom, nearest the pill, and older lines fade under a top
  mask, as in Handy and VoiceInk.
- **Motion.** It scales up from its bottom edge, from 0.92 to 1, over about
  450 ms with an ease-out curve.
- **Latched sessions.** An elapsed timer appears at the right end.
- **Dead microphone.** Amber static bars, and the text area says no audio is
  coming in.
- **Finalizing.** The text stays and a spinner replaces the dot.
- **Why.** It is the placement users already know from Wispr, VoiceInk mini,
  Handy, hyprwhspr and whisrs. It does not compete with the top bar.
  Terminal prompts and chat input boxes are usually at the bottom of their
  windows, so it sits near where text lands in those apps **(inferred)**.

### Variant 6: Draft Sheet (escalates for long Latched sessions, words first)

- **Size and anchoring.** The session starts as the Notch, or whichever variant
  is selected. When a Latched session's Live draft passes about 12 words or 8
  seconds, the HUD turns into a sheet hanging from the top centre: 640 px wide,
  up to five lines, with a 15 px body and 1.4 line height.
- **Motion.** The sheet grows downward from the Notch (the "Grow Down" rule,
  extended).
- **Words.** The committed prefix in full white. The words still changing at
  about 45% opacity, as in Apple's sample and Aqua's "soft" tail.
- **Voice visual.** It shrinks to a thin Chart Line strip along the top of the
  sheet.
- **Latched sessions.** A latched session is what triggers the sheet. A held
  session never escalates.
- **Dead microphone.** The strip goes flat amber and a line says so.
- **Finalizing.** The volatile words settle to white one by one as the final
  pass returns, then the sheet retracts.
- **Progressive insertion.** If it is ever built, this is where it belongs: the
  committed prefix would be the text already inserted, and the user can see the
  commit line move.
- **Why.** Long dictation (email, notes) needs readable text and a check before
  anything lands. Aqua, Superwhisper's classic window and Dragon's Results box
  provide it, and short held sessions do not need it.

### A note on the caret

The text caret position is not available to Talkify, but Wayland does carry it
to one kind of client. Apps that implement `text-input-v3` send a
`set_cursor_rectangle`, and the compositor uses it to place an input method's
popup surface next to the caret
([text-input-v3](https://isaacfreund.com/docs/wayland/text-input-unstable-v3);
Hyprland implements input-method-v2). To use this, Talkify would have to
register as the seat's input method, which conflicts with fcitx5 and similar
tools. XWayland and some apps would also report nothing. It is noted here as
the only path to a caret-anchored HUD on Hyprland, and it is not recommended.
**(inferred, untested)**
