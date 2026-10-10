# Talkify, now for Omarchy: the film

A 45-second product film, 1920×1080 at 60 fps, built with Remotion. Every
frame is code, so it re-renders identically.

```sh
npm install
npm run studio   # scrub it in the browser
npm run render   # out/talkify-omarchy.mp4
npm run shots    # stills of each feature, into ../.github/assets
npm run readme   # the README's cover and pictures, and GitHub's social preview
```

The film runs at 100 BPM: a bar is 144 frames and scenes cut on bars
(`src/brand.ts`). Scenes live in `src/scenes/`, overlapping so every cut is a
movement; `src/Film.tsx` places them and the sound cues.

The soundtrack and the key, whoosh, glow, tick and sparkle effects are
synthesised by `audio/compose.py` (numpy, scipy, soundfile) into
`public/sounds/`, with a bell on every theme change; the Synth8 sounds are
the app's own. The settings pages in `public/settings/` are real screenshots
of the plugin, taken with `plugin/settings-dev` in a different theme each. Fonts are Inter Display, Inter and
JetBrains Mono, all under the SIL Open Font License.

The Omarchy wordmark in `public/omarchy-logo.svg` is Omarchy's own, from
[basecamp/omarchy](https://github.com/basecamp/omarchy) (MIT).

Claims on screen are the ones the app backs: on-device Parakeet, 25
languages, no cloud or account, and 0.3 s for 11 s of speech measured on the
CPU (with the footnote saying times vary).
