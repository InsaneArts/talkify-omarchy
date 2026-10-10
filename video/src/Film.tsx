import React from "react";
import { AbsoluteFill, Audio, Sequence, getStaticFiles, staticFile, useCurrentFrame } from "remotion";
import { C } from "./brand";
import { loadFonts } from "./fonts";
import { Cards, CARDS_AT } from "./scenes/Cards";
import { Demo, T } from "./scenes/Demo";
import { End, END_AT } from "./scenes/End";
import { Intro } from "./scenes/Intro";
import { Keycap, PRESS, RELEASE } from "./scenes/Keycap";
import { Fun } from "./scenes/Fun";
import { HANDOFF, LEAVE, Places, STEPS } from "./scenes/Places";
import { Settings } from "./scenes/Settings";
import { ThemePill } from "./scenes/ThemePill";
import { AT } from "./timeline";

// Talkify, now for Omarchy: 45.6 seconds at 100 BPM. Scenes overlap so
// every cut is a movement, never a jump.

loadFonts();

const has = (name: string) => getStaticFiles().some((file) => file.name === `sounds/${name}`);

const Cue: React.FC<{ at: number; name: string; volume?: number }> = ({ at, name, volume = 1 }) =>
  has(name) ? (
    <Sequence from={at} layout="none">
      <Audio src={staticFile(`sounds/${name}`)} volume={volume} />
    </Sequence>
  ) : null;

/** A still, fine noise over the ground so dark gradients never band. */
const Grain: React.FC = () => (
  <svg width="1920" height="1080" style={{ position: "absolute", inset: 0, opacity: 0.05, mixBlendMode: "overlay" }}>
    <filter id="grain">
      <feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves={2} seed={7} stitchTiles="stitch" />
      <feColorMatrix type="saturate" values="0" />
    </filter>
    <rect width="100%" height="100%" filter="url(#grain)" />
  </svg>
);

/** `grain` off for stills, where there is no motion to hide it in. */
export const Film: React.FC<{ grain?: boolean }> = ({ grain = true }) => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill
      style={{
        background: `radial-gradient(1400px 900px at 50% 46%, ${C.inkLift}, ${C.ink} 70%)`,
        WebkitFontSmoothing: "antialiased",
        overflow: "hidden",
      }}
    >
      {frame >= 210 && frame < 545 && <Keycap frame={frame} />}
      {frame < 300 && <Intro frame={frame} />}
      {frame >= T.enter && frame < T.exit + 42 && <Demo frame={frame} />}
      {frame >= CARDS_AT - 4 && frame < AT.theme + 4 && <Cards frame={frame} />}
      {frame >= AT.theme - 12 && frame < HANDOFF && <ThemePill frame={frame} />}
      {frame >= HANDOFF && frame < LEAVE + 56 && <Places frame={frame} />}
      {frame >= LEAVE && frame < AT.fun + 6 && <Settings frame={frame} />}
      {frame >= AT.fun - 18 && frame < AT.end && <Fun frame={frame} />}
      {frame >= END_AT && <End frame={frame} />}
      {grain && <Grain />}

      <Cue at={0} name="music.wav" />
      <Cue at={PRESS - 2} name="key.wav" volume={0.9} />
      <Cue at={RELEASE} name="key.wav" volume={0.45} />
      <Cue at={490} name="whoosh.wav" volume={0.55} />
      <Cue at={T.pill} name="Synth8Begin.wav" volume={0.55} />
      <Cue at={T.chunkOne} name="Synth8Paste.wav" volume={1} />
      <Cue at={T.chunkTwo} name="Synth8Paste.wav" volume={1} />
      <Cue at={T.enter_ + 6} name="Synth8End.wav" volume={0.32} />
      <Cue at={T.exit} name="whoosh.wav" volume={0.42} />
      <Cue at={AT.places - 16} name="whoosh.wav" volume={0.3} />
      {STEPS.slice(1).map((step) => (
        <Cue key={step.at} at={step.at} name="tick.wav" volume={0.7} />
      ))}
      <Cue at={LEAVE + 4} name="whoosh.wav" volume={0.45} />
      <Cue at={AT.settings + 72} name="tick.wav" volume={0.7} />
      <Cue at={AT.settings + 144} name="tick.wav" volume={0.7} />
      <Cue at={AT.fun + 126} name="sparkle.wav" volume={0.8} />
      <Cue at={END_AT - 6} name="glow.wav" volume={0.8} />
    </AbsoluteFill>
  );
};
