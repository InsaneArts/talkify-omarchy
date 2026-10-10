# Changelog

## 0.1.0

The first release: Talkify's Direct Dictation for Omarchy.

Install it in one line (`curl -fsSL https://raw.githubusercontent.com/InsaneArts/talkify-omarchy/main/install.sh | bash`),
from the AUR (`omarchy pkg aur add talkify-omarchy`, then `talkify-setup`), or
from source (`./install.sh`).

- Hold Right Super to talk and let go to insert, or tap for a hands-free
  session. Escape cancels. Shortcuts that start with Right Super keep
  working, and the microphone opens with the key so the first word is kept.
  A mouse button can be the trigger
- On-device speech with NVIDIA Parakeet TDT 0.6B v3 on the CPU: 25 European
  languages, detected as you speak, about 0.3 s for an 11-second sentence
- Text lands in the window the session started in, with the clipboard put
  back and kept out of the clipboard history; it waits on the clipboard if
  focus moved. Media pauses while you talk
- Live insertion: a hands-free session can paste a phrase at a time as you
  pause
- The Tidy pass: fillers and stutters go, spoken punctuation becomes marks,
  "scratch that" removes the phrase before it
- Vocabulary and Teach: words to prefer, corrections and snippets in
  `~/.config/talkify/words.txt`, matched by sound as well as spelling
- App rules per window class; terminals drop the closing period and press
  Enter on "send it"
- The HUD in six places (pill, window caption, halo, bar island, pointer,
  notch), with four voice visuals, six waveform styles and four reveals, in
  the current Omarchy theme's colours
- Recent dictations: paste again, paste the original, Retry
- Insights: words, pace, voice time, streaks and a 16-week heatmap; only
  daily totals are kept
- The ghost in the bar, with the settings behind it
