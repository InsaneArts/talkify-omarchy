import React from "react";
import { C, EASE, FONT, progress } from "./brand";

/** `$ omarchy-theme-set <name>`, the name rolling over at `changedAt`. */
export const ThemeChip: React.FC<{
  frame: number;
  current: string;
  previous?: string;
  changedAt: number;
  accent: string;
  light?: boolean;
}> = ({ frame, current, previous, changedAt, accent, light = false }) => {
  const roll = previous === undefined ? 1 : progress(frame, changedAt, 10, EASE.out);
  const ink = light ? "rgba(20,20,24,0.62)" : C.mist;
  return (
    <div
      style={{
        display: "inline-flex",
        alignItems: "center",
        gap: 14,
        padding: "12px 22px",
        borderRadius: 14,
        background: light ? "rgba(255,255,255,0.55)" : "rgba(0,0,0,0.35)",
        boxShadow: `inset 0 0 0 1px ${light ? "rgba(0,0,0,0.08)" : "rgba(255,255,255,0.1)"}`,
        backdropFilter: "blur(12px)",
        fontFamily: FONT.mono,
        fontSize: 26,
        color: ink,
      }}
    >
      <span style={{ opacity: 0.55 }}>$</span>
      <span>omarchy-theme-set</span>
      <span style={{ position: "relative", display: "inline-block", width: "13ch", height: 34, overflow: "hidden" }}>
        {roll < 1 && previous !== undefined && (
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
