import React from "react";
import { AbsoluteFill, Audio, Sequence, getStaticFiles, staticFile, useCurrentFrame } from "remotion";
import { C } from "./brand";
import { loadFonts } from "./fonts";
import { Cards, CARDS_AT } from "./scenes/Cards";
import { Demo, T } from "./scenes/Demo";
import { End, END_AT } from "./scenes/End";
import { Intro } from "./scenes/Intro";
import { Keycap, PRESS, RELEASE } from "./scenes/Keycap";
import { COLLAPSE, Themes, THEMES_AT } from "./scenes/Themes";

// Talkify, now for Omarchy: thirty seconds at 100 BPM. Scenes overlap so
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

export const Film: React.FC = () => {
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
      {frame >= CARDS_AT - 4 && frame < THEMES_AT + 20 && <Cards frame={frame} />}
      {frame >= THEMES_AT - 10 && frame < COLLAPSE + 40 && <Themes frame={frame} />}
      {frame >= END_AT - 4 && <End frame={frame} />}
      <Grain />

      <Cue at={0} name="music.wav" />
      <Cue at={PRESS - 2} name="key.wav" volume={0.9} />
      <Cue at={RELEASE} name="key.wav" volume={0.45} />
      <Cue at={490} name="whoosh.wav" volume={0.55} />
      <Cue at={T.pill} name="Synth8Begin.wav" volume={0.55} />
      <Cue at={T.chunkOne} name="Synth8Paste.wav" volume={1} />
      <Cue at={T.chunkTwo} name="Synth8Paste.wav" volume={1} />
      <Cue at={T.enter_ + 6} name="Synth8End.wav" volume={0.32} />
      <Cue at={T.exit} name="whoosh.wav" volume={0.42} />
      <Cue at={COLLAPSE} name="whoosh.wav" volume={0.5} />
      <Cue at={END_AT} name="glow.wav" volume={0.8} />
    </AbsoluteFill>
  );
};
