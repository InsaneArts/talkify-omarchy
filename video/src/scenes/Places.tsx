import React from "react";
import { AbsoluteFill, spring } from "remotion";
import { C, EASE, FONT, FPS, mix, progress } from "../brand";
import { DESKTOP_H, DESKTOP_W, Desktop, Placement } from "../Desktop";
import { arrive } from "../fx";
import { themeAt } from "../themeline";
import { AT } from "../timeline";
import { FRAMED, THEME_STEPS, nameOf, pillWords } from "./ThemePill";

// 28.8–33.6 s. The pill settles into the desktop, and then the HUD jumps
// through every placement on the beat, each in another theme, the camera
// leaning toward wherever it is. The words keep naming the theme.

const BEAT = 36;
export const STEPS: { placement: Placement; label: string; id: string; at: number }[] = [
  { placement: "pill", label: "Pill", id: "tokyo-night", at: AT.places },
  { placement: "caption", label: "Window", id: "catppuccin", at: AT.places + BEAT },
  { placement: "halo", label: "Halo", id: "hackerman", at: AT.places + BEAT * 2 },
  { placement: "island", label: "Island", id: "gruvbox", at: AT.places + BEAT * 3 },
  { placement: "pointer", label: "Pointer", id: "rose-pine", at: AT.places + BEAT * 4 },
  { placement: "notch", label: "Notch", id: "ristretto", at: AT.places + BEAT * 5 },
];
export const LEAVE = AT.places + BEAT * 6;
/** The first frame drawn here: the pill has just settled (ThemePill). */
export const HANDOFF = AT.places + 24;

const LEAN = 0.2;
const CAMERA: Record<Placement, { x: number; y: number; zoom: number }> = {
  pill: { x: 0, y: 0, zoom: 1 },
  caption: { x: -394, y: 260, zoom: 1.06 },
  halo: { x: -394, y: 25, zoom: 1.03 },
  island: { x: 640, y: -150, zoom: 1.12 },
  pointer: { x: 390, y: 60, zoom: 1.08 },
  notch: { x: 0, y: -140, zoom: 1.06 },
};

const voice = (frame: number) => 0.35 + 0.6 * Math.abs(Math.sin(frame * 0.17) * Math.sin(frame * 0.053 + 0.6));
const WITH_WORDS: Placement[] = ["pill", "caption", "notch"];

export const Places: React.FC<{ frame: number }> = ({ frame }) => {
  const now = themeAt(frame, STEPS);
  const step = STEPS[now.index];
  const previous = STEPS[Math.max(0, now.index - 1)];

  const lean = now.index === 0 ? 1 : progress(frame, step.at, 22, EASE.inOut);
  const cam = {
    x: mix(CAMERA[previous.placement].x, CAMERA[step.placement].x, lean),
    y: mix(CAMERA[previous.placement].y, CAMERA[step.placement].y, lean),
    zoom: mix(CAMERA[previous.placement].zoom, CAMERA[step.placement].zoom, lean),
  };
  const leave = progress(frame, LEAVE, 50, EASE.in);
  const scale = FRAMED.scale * cam.zoom * mix(1, 1.12, leave);

  const shown = spring({ frame: frame - step.at, fps: FPS, config: { damping: 15, stiffness: 160, mass: 0.7 } });
  const isLast = now.index === STEPS.length - 1;
  const hide = isLast ? 0 : progress(frame, step.at + BEAT - 8, 8, EASE.in);
  const reveal = now.index === 0 ? 1 - hide : shown * (1 - hide);
  // The pill's words were already on screen when it settled; later ones arrive.
  const wordsAt = now.index === 0 ? THEME_STEPS[THEME_STEPS.length - 1].at : step.at + 4;

  const labels = arrive(frame, AT.places + 10, 26, 24, 10);

  return (
    <AbsoluteFill>
      <div
        style={{
          position: "absolute",
          left: FRAMED.x - (DESKTOP_W * scale) / 2 - cam.x * scale * LEAN,
          top: FRAMED.y - (DESKTOP_H * scale) / 2 - cam.y * scale * LEAN,
          width: DESKTOP_W,
          height: DESKTOP_H,
          transform: `scale(${scale})`,
          transformOrigin: "0 0",
          borderRadius: 18,
          boxShadow: "0 0 0 1px rgba(255,255,255,0.1), 0 60px 160px rgba(0,0,0,0.7)",
          filter: `blur(${leave * 14}px) brightness(${1 - leave * 0.45})`,
        }}
      >
        <Desktop
          frame={frame}
          theme={now.theme}
          recording
          pointer={{ x: 1130, y: 470 }}
          hud={{
            placement: step.placement,
            reveal,
            level: voice,
            scale: step.placement === "halo" ? 2.2 : 1.5,
            words: WITH_WORDS.includes(step.placement) ? pillWords(nameOf(step.id), frame, wordsAt) : undefined,
          }}
          terminal={{ typed: "Refactor the parser and make every test pass.", sent: 1, lines: [1, 1, 1] }}
        />
      </div>

      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          top: 872,
          display: "flex",
          justifyContent: "center",
          gap: 46,
          fontFamily: FONT.display,
          fontWeight: 600,
          fontSize: 58,
          letterSpacing: "-0.03em",
          opacity: labels.opacity * (1 - progress(frame, LEAVE, 14, EASE.in)),
          transform: `translateY(${labels.y}px)`,
          filter: `blur(${labels.blur + leave * 10}px)`,
        }}
      >
        {STEPS.map((s, index) => {
          const lit = index === now.index ? progress(frame, s.at, 8, EASE.out) : index === now.index - 1 ? 1 - progress(frame, STEPS[now.index].at, 8) : 0;
          return (
            <span
              key={s.label}
              style={{
                color: C.paper,
                opacity: mix(0.22, 1, lit),
                transform: `translateY(${-lit * 6}px)`,
                display: "inline-block",
              }}
            >
              {s.label}
            </span>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};
