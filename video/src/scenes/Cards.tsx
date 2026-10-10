import React from "react";
import { AbsoluteFill } from "remotion";
import { C, EASE, FONT, mix, progress } from "../brand";
import { arrive, leave } from "../fx";

// 17–22 s. Four facts, one per beat of the lift, each arriving its own way.

export const CARD = 72;
export const CARDS_AT = 1006;

const headline: React.CSSProperties = {
  fontFamily: FONT.display,
  fontWeight: 600,
  fontSize: 120,
  letterSpacing: "-0.04em",
  lineHeight: 1.04,
  color: C.paper,
  textAlign: "center",
  whiteSpace: "nowrap",
};

const label: React.CSSProperties = {
  fontFamily: FONT.mono,
  fontSize: 22,
  letterSpacing: "0.22em",
  color: C.mist,
  textAlign: "center",
};

/** Words that arrive one after another and leave together. */
const Staggered: React.FC<{ frame: number; start: number; end: number; text: string; gap?: number }> = ({
  frame,
  start,
  end,
  text,
  gap = 4,
}) => {
  const out = leave(frame, end, 14, 26, 12);
  return (
    <span style={{ display: "inline-block", opacity: out.opacity, transform: `translateY(${out.y}px)`, filter: `blur(${out.blur}px)` }}>
      {text.split(" ").map((word, index) => {
        const a = arrive(frame, start + index * gap, 30, 48, 16);
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
    </span>
  );
};

const Centered: React.FC<{ children: React.ReactNode; style?: React.CSSProperties }> = ({ children, style }) => (
  <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", flexDirection: "column", ...style }}>
    {children}
  </AbsoluteFill>
);

/** One character on an odometer drum: it rolls up into place. */
const Roll: React.FC<{ frame: number; start: number; char: string }> = ({ frame, start, char }) => {
  const t = progress(frame, start, 34, EASE.out);
  return (
    <span style={{ display: "inline-block", overflow: "hidden", verticalAlign: "top", height: "1.04em" }}>
      <span style={{ display: "inline-block", transform: `translateY(${mix(105, 0, t)}%)`, filter: `blur(${mix(10, 0, t)}px)` }}>
        {char}
      </span>
    </span>
  );
};

export const Cards: React.FC<{ frame: number }> = ({ frame }) => {
  const at = (n: number) => CARDS_AT + n * CARD;

  // Card two zooms in from close up; card three wipes in left to right.
  const zoom = progress(frame, at(1), 34, EASE.out);
  const zoomOut = leave(frame, at(2) - 14, 14, 26, 12);
  const wipeOne = progress(frame, at(2), 26, EASE.out);
  const wipeTwo = progress(frame, at(2) + 12, 26, EASE.out);
  const wipeOut = leave(frame, at(3) - 14, 14, 26, 12);
  const numberOut = progress(frame, at(4) - 24, 22, EASE.in);
  const sub = arrive(frame, at(3) + 16, 30, 24, 10);

  return (
    <AbsoluteFill>
      {frame < at(1) && (
        <Centered>
          <div style={headline}>
            <Staggered frame={frame} start={at(0)} end={at(1) - 14} text="Right where you type." />
          </div>
        </Centered>
      )}

      {frame >= at(1) - 2 && frame < at(2) && (
        <Centered
          style={{
            opacity: progress(frame, at(1), 18) * zoomOut.opacity,
            transform: `translateY(${zoomOut.y}px) scale(${mix(1.22, 1, zoom)})`,
            filter: `blur(${mix(18, 0, zoom) + zoomOut.blur}px)`,
          }}
        >
          <div style={{ ...label, marginBottom: 34 }}>PARAKEET · 25 LANGUAGES · ON-DEVICE</div>
          <div style={headline}>Runs on your machine.</div>
        </Centered>
      )}

      {frame >= at(2) - 2 && frame < at(3) && (
        <Centered style={{ opacity: wipeOut.opacity, transform: `translateY(${wipeOut.y}px)`, filter: `blur(${wipeOut.blur}px)` }}>
          <div style={{ ...headline, display: "flex", gap: "0.3em" }}>
            <span style={{ clipPath: `inset(-20% ${(1 - wipeOne) * 100}% -20% 0)`, transform: `translateX(${mix(-30, 0, wipeOne)}px)` }}>
              No cloud.
            </span>
            <span
              style={{
                clipPath: `inset(-20% ${(1 - wipeTwo) * 100}% -20% 0)`,
                transform: `translateX(${mix(-30, 0, wipeTwo)}px)`,
                color: C.mist,
              }}
            >
              No account.
            </span>
          </div>
        </Centered>
      )}

      {frame >= at(3) - 2 && (
        <Centered
          style={{
            opacity: 1 - numberOut,
            transform: `scale(${mix(1, 0.72, numberOut)})`,
            filter: `blur(${numberOut * 20}px)`,
          }}
        >
          <div
            style={{
              ...headline,
              fontSize: 300,
              fontWeight: 700,
              letterSpacing: "-0.055em",
              lineHeight: 1.04,
              display: "flex",
              alignItems: "baseline",
            }}
          >
            <Roll frame={frame} start={at(3)} char="0" />
            <Roll frame={frame} start={at(3) + 3} char="." />
            <Roll frame={frame} start={at(3) + 6} char="3" />
            <span style={{ fontSize: 150, marginLeft: "0.18em", letterSpacing: "-0.02em", color: C.mist }}>
              <Roll frame={frame} start={at(3) + 10} char="s" />
            </span>
          </div>
          <div
            style={{
              fontFamily: FONT.display,
              fontWeight: 500,
              fontSize: 44,
              letterSpacing: "-0.015em",
              color: C.mist,
              marginTop: 18,
              opacity: sub.opacity,
              transform: `translateY(${sub.y}px)`,
              filter: `blur(${sub.blur}px)`,
            }}
          >
            to transcribe 11 seconds of speech.
          </div>
          <div
            style={{
              position: "absolute",
              bottom: 56,
              fontFamily: FONT.text,
              fontSize: 18,
              letterSpacing: "0.01em",
              color: C.faint,
              opacity: sub.opacity,
            }}
          >
            Parakeet TDT 0.6B v3 on the CPU. Times vary by machine.
          </div>
        </Centered>
      )}
    </AbsoluteFill>
  );
};
