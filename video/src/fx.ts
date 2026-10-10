import React from "react";
import { EASE, mix, progress } from "./brand";

// The film's two gestures: things arrive by rising out of a blur, and
// leave by drifting up into one. Every word on screen moves this way.

export const arrive = (frame: number, start: number, duration = 28, rise = 36, blur = 14) => {
  const t = progress(frame, start, duration, EASE.out);
  return { t, y: mix(rise, 0, t), blur: mix(blur, 0, t), opacity: t };
};

export const leave = (frame: number, start: number, duration = 16, lift = 22, blur = 10) => {
  const t = progress(frame, start, duration, EASE.in);
  return { t, y: mix(0, -lift, t), blur: mix(0, blur, t), opacity: 1 - t };
};

/** A word or line that arrives at `start` and leaves at `end`. */
export const passing = (
  frame: number,
  start: number,
  end: number,
  options: { duration?: number; rise?: number; blur?: number; out?: number } = {},
): React.CSSProperties => {
  const a = arrive(frame, start, options.duration ?? 28, options.rise ?? 36, options.blur ?? 14);
  const l = leave(frame, end, options.out ?? 16);
  return {
    opacity: a.opacity * l.opacity,
    transform: `translateY(${a.y + l.y}px)`,
    filter: `blur(${a.blur + l.blur}px)`,
  };
};

/** A blip that rises over `rise` frames and falls over `fall`. */
export const pulse = (frame: number, start: number, rise: number, fall: number) => {
  if (frame < start) return 0;
  if (frame < start + rise) return progress(frame, start, rise, EASE.out);
  return 1 - progress(frame, start + rise, fall, EASE.inOut);
};

/** A speaker's level from a word list: syllables inside words, quiet between. */
export const speech = (words: [number, number][], seed = 1) => (frame: number) => {
  let level = 0;
  for (const [start, end] of words) {
    if (frame < start - 4 || frame > end + 8) continue;
    const attack = Math.min(1, (frame - start + 4) / 6);
    const release = Math.min(1, (end + 8 - frame) / 10);
    const t = (frame - start) / 60;
    const syllable = 0.62 + 0.38 * Math.sin(t * 2 * Math.PI * 5.3 + seed + start * 0.37);
    const body = 0.8 + 0.2 * Math.sin(t * 2 * Math.PI * 1.7 + start);
    level = Math.max(level, Math.max(0, attack) * Math.max(0, release) * syllable * body);
  }
  return Math.min(1, level);
};
