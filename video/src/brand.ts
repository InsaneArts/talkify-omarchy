import { Easing, interpolate } from "remotion";

// The film's rules. Three colours, two typefaces, one tempo. Every scene
// draws from here, so nothing on screen is an accident.

export const FPS = 60;
export const WIDTH = 1920;
export const HEIGHT = 1080;

// 100 BPM: smooth, cool, effortless. Scenes cut on bars, accents land on
// beats.
export const BEAT = 36;
export const BAR = BEAT * 4;
/** The first frame of bar `n` (1-based). */
export const bar = (n: number) => (n - 1) * BAR;

export const C = {
  /** The stage: near-black with a breath of blue. */
  ink: "#05060a",
  inkLift: "#0c0e16",
  /** Apple's off-white, for every word. */
  paper: "#f5f5f7",
  mist: "rgba(245, 245, 247, 0.52)",
  faint: "rgba(245, 245, 247, 0.16)",
  /** The voice: one gradient, violet into cyan, used only for sound. */
  voiceA: "#7aa2f7",
  voiceB: "#bb9af7",
  voiceC: "#7dcfff",
};

export const VOICE_GRADIENT = `linear-gradient(90deg, ${C.voiceB}, ${C.voiceA} 45%, ${C.voiceC})`;

export const FONT = {
  display: "'Inter Display', 'Inter', sans-serif",
  text: "'Inter', sans-serif",
  mono: "'JetBrains Mono', monospace",
};

// Motion: nothing moves linearly. Out-curves land softly, in-out curves
// carry the camera.
export const EASE = {
  out: Easing.bezier(0.16, 1, 0.3, 1),
  inOut: Easing.bezier(0.65, 0, 0.35, 1),
  in: Easing.bezier(0.7, 0, 0.84, 0),
  soft: Easing.bezier(0.33, 0, 0.12, 1),
};

/** 0 → 1 over `duration` frames from `start`, eased. */
export const progress = (
  frame: number,
  start: number,
  duration: number,
  easing: (t: number) => number = EASE.out,
) =>
  interpolate(frame, [start, start + duration], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing,
  });

/** Linear mix of two numbers. */
export const mix = (a: number, b: number, t: number) => a + (b - a) * t;

/** Mixes two #rrggbb colours. */
export const mixColor = (a: string, b: string, t: number) => {
  const parse = (hex: string) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
  const [ar, ag, ab] = parse(a);
  const [br, bg, bb] = parse(b);
  const channel = (x: number, y: number) => Math.round(mix(x, y, t));
  return `rgb(${channel(ar, br)}, ${channel(ag, bg)}, ${channel(ab, bb)})`;
};

/** A colour with alpha, from #rrggbb. */
export const alpha = (hex: string, a: number) => {
  const r = parseInt(hex.slice(1, 3), 16);
  const g = parseInt(hex.slice(3, 5), 16);
  const b = parseInt(hex.slice(5, 7), 16);
  return `rgba(${r}, ${g}, ${b}, ${a})`;
};

/**
 * A voice, as a level 0–1 at a frame: syllables as soft bumps, words
 * grouped with short gaps, never perfectly regular. Deterministic, so every
 * render is the same performance.
 */
export const voiceLevel = (frame: number, start: number, end: number, seed = 1) => {
  if (frame < start || frame > end) return 0;
  const t = (frame - start) / FPS;
  const fadeIn = Math.min(1, (frame - start) / 10);
  const fadeOut = Math.min(1, (end - frame) / 14);
  const syllables =
    0.5 +
    0.5 * Math.sin(t * 2 * Math.PI * 4.1 + seed) * Math.sin(t * 2 * Math.PI * 1.3 + seed * 2);
  const words = 0.55 + 0.45 * Math.sin(t * 2 * Math.PI * 0.62 + seed * 3);
  const breath = Math.sin(t * 2 * Math.PI * 0.21 + seed) > -0.85 ? 1 : 0.15;
  return Math.max(0, Math.min(1, Math.abs(syllables) * words * breath)) * fadeIn * fadeOut;
};
