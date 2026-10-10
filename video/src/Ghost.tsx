import React from "react";

// Talkify's mark, the same outline the Omarchy bar draws: a domed head, a
// four-point hem, two pill eyes. `blink` 0–1 closes the eyes.
const BODY =
  "M 0 96 L 0 42 A 42 42 0 0 1 84 42 L 84 96 Q 73.5 86 63 96 Q 52.5 86 42 96 Q 31.5 86 21 96 Q 10.5 86 0 96 Z";

export const Ghost: React.FC<{
  size: number;
  color?: string;
  fill?: string;
  blink?: number;
  /** Eyes look toward x (-1…1). */
  look?: number;
  /** Eyes look down (1) or up (-1). */
  lookY?: number;
  style?: React.CSSProperties;
}> = ({ size, color = "#f5f5f7", fill, blink = 0, look = 0, lookY = 0, style }) => {
  const eyeHeight = 14 * (1 - 0.88 * blink);
  const eyeY = 41 + lookY * 5 - eyeHeight / 2;
  const shift = look * 4;
  const id = React.useId();
  return (
    <svg
      width={size * 0.875}
      height={size}
      viewBox="0 0 84 96"
      style={{ overflow: "visible", ...style }}
    >
      <defs>
        <mask id={`eyes-${id}`}>
          <path d={BODY} fill="white" />
          <rect x={26 + shift} y={eyeY} width={8} height={eyeHeight} rx={4} fill="black" />
          <rect x={50 + shift} y={eyeY} width={8} height={eyeHeight} rx={4} fill="black" />
        </mask>
      </defs>
      <path d={BODY} fill={fill ?? color} mask={`url(#eyes-${id})`} />
    </svg>
  );
};
