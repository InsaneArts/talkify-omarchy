import React from "react";
import { AbsoluteFill, spring } from "remotion";
import { C, EASE, FONT, FPS, mix, progress, voiceLevel } from "../brand";
import { arrive, leave } from "../fx";
import { blendTheme, DESKTOP_H, DESKTOP_W, Desktop, Placement, tint } from "../Desktop";
import { THEMES } from "../themes";

// 21–26 s. The desktop comes back and changes theme on every beat; the HUD
// follows the colours and moves to a new place each time.

export const THEMES_AT = 1296;
const STEP = 72;
const ORDER: { theme: number; placement: Placement }[] = [
  { theme: 0, placement: "pill" },
  { theme: 1, placement: "halo" },
  { theme: 2, placement: "island" },
  { theme: 4, placement: "pointer" },
];
export const COLLAPSE = THEMES_AT + STEP * ORDER.length - 20;
// Where each placement's HUD sits, from the desktop's centre, and how far
// the camera leans in on it.
const LEAN = 0.2;
const CAMERA: Record<Placement, { x: number; y: number; zoom: number }> = {
  pill: { x: 0, y: 300, zoom: 1 },
  halo: { x: -394, y: 25, zoom: 1.06 },
  island: { x: 640, y: -160, zoom: 1.1 },
  pointer: { x: 390, y: 60, zoom: 1.08 },
  caption: { x: -394, y: 300, zoom: 1.06 },
  notch: { x: 0, y: -160, zoom: 1.08 },
};

const voice = (frame: number) => 0.25 + 0.75 * voiceLevel(frame, THEMES_AT - 30, COLLAPSE + 40, 3.1);

export const Themes: React.FC<{ frame: number }> = ({ frame }) => {
  const enter = progress(frame, THEMES_AT - 8, 66, EASE.out);
  const collapse = progress(frame, COLLAPSE, 36, EASE.in);

  const step = Math.max(0, Math.min(ORDER.length - 1, Math.floor((frame - THEMES_AT + 10) / STEP)));
  const blendAt = THEMES_AT + step * STEP - 10;
  const from = THEMES[ORDER[Math.max(0, step - 1)].theme];
  const to = THEMES[ORDER[step].theme];
  const theme = step === 0 ? to : blendTheme(from, to, progress(frame, blendAt, 20, EASE.inOut));

  const shownAt = THEMES_AT + step * STEP - 2;
  const shown = spring({ frame: frame - shownAt, fps: FPS, config: { damping: 15, stiffness: 150, mass: 0.7 } });
  const isLast = step === ORDER.length - 1;
  const hide = isLast ? 0 : progress(frame, shownAt + STEP - 14, 12, EASE.in);
  const reveal = step === 0 ? Math.min(1, progress(frame, THEMES_AT + 6, 24, EASE.out)) * (1 - hide) : shown * (1 - hide);

  const pointerT = progress(frame, THEMES_AT + 3 * STEP - 30, 70, EASE.inOut);
  const pointer = { x: mix(1300, 1120, pointerT), y: mix(660, 420, pointerT) };

  // The camera leans toward wherever the HUD is this time.
  const camAt = (index: number) => CAMERA[ORDER[index].placement];
  const lean = step === 0 ? 1 : progress(frame, THEMES_AT + step * STEP - 18, 36, EASE.inOut);
  const camFrom = camAt(Math.max(0, step - 1));
  const camTo = camAt(step);
  const cam = {
    x: mix(camFrom.x, camTo.x, lean),
    y: mix(camFrom.y, camTo.y, lean),
    zoom: mix(camFrom.zoom, camTo.zoom, lean),
  };
  const scale = mix(0.56, 0.72, enter) * cam.zoom * mix(1, 0.08, collapse);
  const lift = mix(-30, -120, enter) + collapse * 160;

  const caption = arrive(frame, THEMES_AT + 14, 34, 30, 12);
  const captionOut = leave(frame, COLLAPSE - 12, 16);

  return (
    <AbsoluteFill>
      <div
        style={{
          position: "absolute",
          left: 960 - 800,
          top: 530 - 460 + lift,
          width: 1600,
          height: 920,
          borderRadius: "50%",
          background: `radial-gradient(closest-side, ${tint(theme.wall[0], 0.3)}, ${tint(theme.wall[1], 0.12)} 55%, transparent)`,
          filter: "blur(40px)",
          opacity: enter * (1 - collapse),
        }}
      />
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "flex-start" }}>
        <div
          style={{
            marginTop: 80,
            width: DESKTOP_W,
            height: DESKTOP_H,
            flexShrink: 0,
            transformOrigin: "50% 50%",
            transform: `translate(${-cam.x * scale * LEAN * (1 - collapse)}px, ${lift - cam.y * scale * LEAN * (1 - collapse)}px) perspective(2400px) rotateX(${mix(-16, 0, enter)}deg) scale(${scale})`,
            opacity: Math.min(1, enter * 1.5) * (1 - progress(frame, COLLAPSE + 14, 22)),
            filter: `blur(${mix(16, 0, enter) + collapse * 16}px)`,
            borderRadius: 18,
            boxShadow: "0 0 0 1px rgba(255,255,255,0.1), 0 60px 160px rgba(0,0,0,0.7)",
          }}
        >
          <Desktop
            frame={frame}
            theme={theme}
            recording
            pointer={pointer}
            hud={{ placement: ORDER[step].placement, reveal, level: voice, scale: 1.9 }}
            terminal={{
              typed: "Refactor the parser and make every test pass.",
              sent: 1,
              lines: [1, 1, 1],
              cursor: true,
            }}
          />
        </div>
      </AbsoluteFill>

      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          top: 834,
          textAlign: "center",
          opacity: caption.opacity * captionOut.opacity,
          transform: `translateY(${caption.y + captionOut.y}px)`,
          filter: `blur(${caption.blur + captionOut.blur}px)`,
        }}
      >
        <div
          style={{
            fontFamily: FONT.display,
            fontWeight: 600,
            fontSize: 78,
            letterSpacing: "-0.035em",
            lineHeight: 1,
            color: C.paper,
          }}
        >
          Made for Omarchy.
        </div>
        <ThemeChip frame={frame} step={step} accent={theme.accent} />
      </div>
    </AbsoluteFill>
  );
};

/** `omarchy-theme-set <name>`, the name rolling over on each change. */
const ThemeChip: React.FC<{ frame: number; step: number; accent: string }> = ({ frame, step, accent }) => {
  const changeAt = THEMES_AT + step * STEP - 10;
  const roll = step === 0 ? 1 : progress(frame, changeAt, 20, EASE.inOut);
  const current = THEMES[ORDER[step].theme].id;
  const previous = THEMES[ORDER[Math.max(0, step - 1)].theme].id;
  return (
    <div
      style={{
        marginTop: 30,
        display: "inline-flex",
        alignItems: "center",
        gap: 14,
        padding: "12px 22px",
        borderRadius: 14,
        background: "rgba(255,255,255,0.05)",
        boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.08)",
        fontFamily: FONT.mono,
        fontSize: 26,
        color: C.mist,
      }}
    >
      <span style={{ color: "rgba(245,245,247,0.32)" }}>$</span>
      <span>omarchy-theme-set</span>
      <span style={{ position: "relative", display: "inline-block", width: "11ch", height: 34, overflow: "hidden", textAlign: "left" }}>
        {roll < 1 && (
          <span style={{ position: "absolute", left: 0, top: 0, transform: `translateY(${-roll * 100}%)`, opacity: 1 - roll, color: accent }}>
            {previous}
          </span>
        )}
        <span style={{ position: "absolute", left: 0, top: 0, transform: `translateY(${(1 - roll) * 100}%)`, opacity: roll, color: accent }}>
          {current}
        </span>
      </span>
    </div>
  );
};
