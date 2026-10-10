import React from "react";
import { AbsoluteFill } from "remotion";
import { C, EASE, FONT, mix, progress } from "../brand";
import { arrive, pulse } from "../fx";
import { Ghost } from "../Ghost";
import { AT } from "../timeline";

// 42–45.6 s. The ghost that hopped for joy takes its place, and the name
// arrives under it. Talkify. Now for Omarchy.

export const END_AT = AT.end;

export const End: React.FC<{ frame: number }> = ({ frame }) => {
  // The ghost arrives already in place, carried here by the scene before.
  const born = 1;
  const clear = 1;
  const bloom = pulse(frame, END_AT - 6, 16, 80) * 0.8 + progress(frame, END_AT + 20, 60) * 0.28;
  const name = arrive(frame, END_AT + 26, 40, 40, 16);
  const tracking = mix(0.06, -0.045, progress(frame, END_AT + 26, 60, EASE.out));
  const line = arrive(frame, END_AT + 66, 40, 26, 12);
  const blink = pulse(frame, END_AT + 150, 5, 8);
  const look = Math.sin(Math.max(0, frame - END_AT - 90) / 40) * 0.25 * progress(frame, END_AT + 90, 40);
  const float = Math.sin((frame - END_AT) / 46) * 5 * progress(frame, END_AT + 40, 60);
  const fade = progress(frame, END_AT + 204, 12, EASE.in);

  return (
    <AbsoluteFill style={{ opacity: 1 - fade }}>
      <div
        style={{
          position: "absolute",
          left: 960,
          top: 372 + float,
          transform: `translate(-50%, -50%) scale(${mix(0.2, 1, born)})`,
          opacity: clear,
          filter: `blur(${mix(18, 0, clear)}px)`,
        }}
      >
        <div
          style={{
            position: "absolute",
            left: "50%",
            top: "50%",
            width: 640,
            height: 640,
            transform: "translate(-50%, -50%)",
            borderRadius: "50%",
            background: `radial-gradient(circle, rgba(122,162,247,${0.5 * bloom}) 0%, rgba(187,154,247,${0.26 * bloom}) 34%, rgba(5,6,10,0) 66%)`,
            filter: "blur(24px)",
          }}
        />
        <Ghost size={150} color={C.paper} blink={blink} look={look} />
      </div>

      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          top: 520,
          textAlign: "center",
          fontFamily: FONT.display,
          fontWeight: 700,
          fontSize: 168,
          lineHeight: 1,
          letterSpacing: `${tracking}em`,
          color: C.paper,
          opacity: name.opacity,
          transform: `translateY(${name.y}px)`,
          filter: `blur(${name.blur}px)`,
        }}
      >
        Talkify
      </div>

      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          top: 718,
          textAlign: "center",
          fontFamily: FONT.display,
          fontWeight: 500,
          fontSize: 58,
          letterSpacing: "-0.025em",
          color: C.mist,
          opacity: line.opacity,
          transform: `translateY(${line.y}px)`,
          filter: `blur(${line.blur}px)`,
        }}
      >
        Now for <span style={{ color: C.paper }}>Omarchy.</span>
      </div>
    </AbsoluteFill>
  );
};
