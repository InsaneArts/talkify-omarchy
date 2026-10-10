import React from "react";

// Talkify's Chart Line: the recent voice drawn as one smooth line, newest
// at the right, its ends dissolving so it never looks clipped. `level(f)`
// is the voice at frame f; the line reads history back from `frame`.

type Props = {
  frame: number;
  level: (frame: number) => number;
  width: number;
  height: number;
  /** Stroke stops, left to right. */
  colors?: string[];
  strokeWidth?: number;
  glow?: number;
  points?: number;
  /** Frames of history between neighbouring points. */
  spacing?: number;
  /** A resting ripple so silence still looks alive. */
  idle?: number;
  opacity?: number;
  /** The voice rises at the centre and travels out to both ends. */
  symmetric?: boolean;
};

const smoothPath = (pts: [number, number][]) => {
  if (pts.length < 2) return "";
  let d = `M ${pts[0][0].toFixed(2)} ${pts[0][1].toFixed(2)}`;
  for (let i = 0; i < pts.length - 1; i++) {
    const p0 = pts[Math.max(0, i - 1)];
    const p1 = pts[i];
    const p2 = pts[i + 1];
    const p3 = pts[Math.min(pts.length - 1, i + 2)];
    const c1x = p1[0] + (p2[0] - p0[0]) / 6;
    const c1y = p1[1] + (p2[1] - p0[1]) / 6;
    const c2x = p2[0] - (p3[0] - p1[0]) / 6;
    const c2y = p2[1] - (p3[1] - p1[1]) / 6;
    d += ` C ${c1x.toFixed(2)} ${c1y.toFixed(2)}, ${c2x.toFixed(2)} ${c2y.toFixed(2)}, ${p2[0].toFixed(2)} ${p2[1].toFixed(2)}`;
  }
  return d;
};

export const Waveform: React.FC<Props> = ({
  frame,
  level,
  width,
  height,
  colors = ["rgba(196,206,230,0)", "#ffffff", "#dfe5f5", "#ffffff", "rgba(196,206,230,0)"],
  strokeWidth = 2.4,
  glow = 10,
  points = 72,
  spacing = 1.5,
  idle = 0.04,
  opacity = 1,
  symmetric = false,
}) => {
  const id = React.useId();
  const mid = height / 2;
  const pts: [number, number][] = [];
  for (let i = 0; i < points; i++) {
    const x = (i / (points - 1)) * width;
    const fromMiddle = Math.abs(i - (points - 1) / 2);
    const age = symmetric ? fromMiddle * spacing * 2 : (points - 1 - i) * spacing;
    // Toward the ends the line calms, so it dissolves rather than stops.
    const taper = symmetric ? Math.cos((fromMiddle / ((points - 1) / 2)) * Math.PI * 0.5) ** 1.4 : 1;
    const v = level(frame - age) * taper;
    // Each bump rises and falls with its own phase, so speech reads as a
    // wave rather than a bar chart.
    const shape = symmetric
      ? Math.sin(fromMiddle * 0.5 - frame * 0.16) * 0.7 + Math.sin(i * 0.21 + frame * 0.04) * 0.3
      : Math.sin(i * 0.55 + frame * 0.11) * 0.65 + Math.sin(i * 0.23 - frame * 0.05) * 0.35;
    const ripple = Math.sin(i * 0.4 + frame * 0.08) * idle;
    const y = mid - (v * shape * (height * 0.46)) - ripple * height;
    pts.push([x, y]);
  }
  const d = smoothPath(pts);
  return (
    <svg width={width} height={height} style={{ overflow: "visible", opacity }}>
      <defs>
        <linearGradient id={`stroke-${id}`} x1="0" x2="1" y1="0" y2="0">
          {colors.map((color, index) => (
            <stop key={index} offset={index / (colors.length - 1)} stopColor={color} />
          ))}
        </linearGradient>
        <filter id={`glow-${id}`} x="-20%" y="-200%" width="140%" height="500%">
          <feGaussianBlur stdDeviation={glow} />
        </filter>
      </defs>
      {glow > 0 && (
        <path
          d={d}
          fill="none"
          stroke={`url(#stroke-${id})`}
          strokeWidth={strokeWidth * 3}
          strokeLinecap="round"
          filter={`url(#glow-${id})`}
          opacity={0.55}
        />
      )}
      <path
        d={d}
        fill="none"
        stroke={`url(#stroke-${id})`}
        strokeWidth={strokeWidth}
        strokeLinecap="round"
      />
    </svg>
  );
};
