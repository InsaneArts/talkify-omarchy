import React from "react";
import { AbsoluteFill, spring } from "remotion";
import { C, EASE, FONT, FPS, VOICE_GRADIENT, mix, progress } from "../brand";
import { arrive, pulse } from "../fx";
import { Ghost } from "../Ghost";
import { AT } from "../timeline";

// 38.4–42 s. Why Talkify looks the way it does. Omarchy is fun to use, and
// dictation should be too: two lines, and the ghost hopping with sparkles,
// the way it does in the bar for a milestone. Then it takes its place for
// the end card.

const LINE_ONE = "Using a computer should be fun.";
const LINE_TWO = ["So", "should", "talking", "to", "one."];
const HOP = AT.fun + 120;
/** Where the end card draws its ghost, and how big (End.tsx). */
export const END_GHOST = { x: 960, y: 372, size: 150 };

const SPARK_COLOURS = [
  "#7aa2f7", "#f5c2e7", "#d8a657", "#82fb9c", "#f38d70", "#bb9af7",
  "#7dcfff", "#dbbc7f", "#a6e3a1", "#fab387", "#89b4fa", "#f7768e",
];

const Spark: React.FC<{ angle: number; t: number; colour: string; size: number }> = ({ angle, t, colour, size }) => {
  const distance = mix(40, 210, t);
  const s = size * (t < 0.3 ? t / 0.3 : 1 - (t - 0.3) / 0.7);
  return (
    <svg
      width={s * 2}
      height={s * 2}
      viewBox="-1 -1 2 2"
      style={{
        position: "absolute",
        left: Math.cos(angle) * distance - s,
        top: Math.sin(angle) * distance - s,
        transform: `rotate(${t * 140}deg)`,
        filter: `drop-shadow(0 0 ${s * 0.6}px ${colour})`,
      }}
    >
      <path d="M0 -1 Q0.12 -0.12 1 0 Q0.12 0.12 0 1 Q-0.12 0.12 -1 0 Q-0.12 -0.12 0 -1 Z" fill={colour} />
    </svg>
  );
};

export const Fun: React.FC<{ frame: number }> = ({ frame }) => {
  const away = progress(frame, AT.end - 40, 40, EASE.inOut);
  const gone = progress(frame, AT.end - 36, 26, EASE.in);

  const born = spring({ frame: frame - (AT.fun + 84), fps: FPS, config: { damping: 11, stiffness: 160, mass: 0.7 } });
  const hopT = progress(frame, HOP, 26);
  const height = Math.sin(Math.PI * hopT) * 70;
  const squash = pulse(frame, HOP + 25, 3, 12) * 0.12 - pulse(frame, HOP - 2, 3, 6) * 0.08;
  const blink = pulse(frame, HOP + 52, 4, 7);
  const look = Math.sin((frame - AT.fun) / 18) * 0.5 * (1 - away);
  const sparks = progress(frame, HOP + 6, 46, EASE.out);

  const ghostX = END_GHOST.x;
  const ghostY = mix(250, END_GHOST.y, away) - height * (1 - away);
  const ghostSize = mix(112, END_GHOST.size, away);

  return (
    <AbsoluteFill>
      <AbsoluteFill style={{ opacity: progress(frame, AT.fun - 16, 40) * (1 - away) }}>
        {["#7aa2f7", "#f5c2e7", "#d8a657", "#82fb9c"].map((colour, index) => (
          <div
            key={colour}
            style={{
              position: "absolute",
              left: 960 + Math.cos(frame / 70 + index * 1.6) * 520 - 380,
              top: 540 + Math.sin(frame / 90 + index * 2.1) * 260 - 380,
              width: 760,
              height: 760,
              borderRadius: "50%",
              background: `radial-gradient(closest-side, ${colour}, transparent)`,
              opacity: 0.22,
              filter: "blur(60px)",
            }}
          />
        ))}
      </AbsoluteFill>

      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          top: 420,
          textAlign: "center",
          fontFamily: FONT.display,
          fontWeight: 600,
          fontSize: 96,
          letterSpacing: "-0.04em",
          lineHeight: 1.1,
          color: C.paper,
          opacity: 1 - gone,
          filter: `blur(${gone * 14}px)`,
          transform: `translateY(${-gone * 30}px)`,
        }}
      >
        <div>
          {LINE_ONE.split(" ").map((word, index) => {
            const a = arrive(frame, AT.fun + index * 4, 30, 44, 14);
            return (
              <span
                key={index}
                style={{
                  display: "inline-block",
                  marginRight: "0.24em",
                  opacity: a.opacity,
                  transform: `translateY(${a.y}px)`,
                  filter: `blur(${a.blur}px)`,
                }}
              >
                {word}
              </span>
            );
          })}
        </div>
        <div style={{ marginTop: 18 }}>
          {LINE_TWO.map((word, index) => {
            const a = arrive(frame, AT.fun + 72 + index * 4, 30, 44, 14);
            const voiced = word === "talking";
            return (
              <span
                key={index}
                style={{
                  display: "inline-block",
                  marginRight: "0.24em",
                  opacity: a.opacity,
                  transform: `translateY(${a.y}px)`,
                  filter: `blur(${a.blur}px)`,
                  ...(voiced
                    ? { backgroundImage: VOICE_GRADIENT, WebkitBackgroundClip: "text", backgroundClip: "text", color: "transparent" }
                    : {}),
                }}
              >
                {word}
              </span>
            );
          })}
        </div>
      </div>

      {frame >= AT.fun + 84 && (
        <div style={{ position: "absolute", left: ghostX, top: ghostY }}>
          {sparks > 0 &&
            sparks < 1 &&
            SPARK_COLOURS.map((colour, index) => (
              <Spark
                key={index}
                angle={(index / SPARK_COLOURS.length) * Math.PI * 2 - Math.PI / 2 + (index % 2) * 0.2}
                t={Math.min(1, sparks * (index % 2 ? 1.15 : 1))}
                colour={colour}
                size={30 + (index % 3) * 10}
              />
            ))}
          <div
            style={{
              position: "absolute",
              left: 0,
              top: 0,
              transform: `translate(-50%, -50%) scale(${born}) scaleY(${1 - squash}) scaleX(${1 + squash * 0.8})`,
              transformOrigin: "50% 100%",
            }}
          >
            <Ghost size={ghostSize} color={C.paper} blink={blink} look={look} />
          </div>
        </div>
      )}
    </AbsoluteFill>
  );
};
