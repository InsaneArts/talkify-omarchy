import React from "react";
import { AbsoluteFill, spring } from "remotion";
import { C, EASE, FPS, mix, progress, voiceLevel } from "../brand";
import { pulse } from "../fx";
import { Ghost } from "../Ghost";
import { Waveform } from "../Waveform";
import { LEGEND } from "./Keycap";

// 0–5 s. A line in the dark. A voice moves it. The voice gathers into the
// ghost, which blinks, looks down at the key rising toward it, and dives
// into place as the legend on its top.

const VOICE: [number, number] = [52, 182];
const level = (frame: number) => voiceLevel(frame, VOICE[0], VOICE[1], 1.7) * 0.95;

export const Intro: React.FC<{ frame: number }> = ({ frame }) => {
  const draw = progress(frame, 12, 64, EASE.out);
  const gather = progress(frame, 150, 48, EASE.inOut);
  const lineFade = 1 - progress(frame, 184, 18, EASE.in);
  const lineWidth = mix(1320, 40, gather);
  const lineLevel = (f: number) => level(f) * (1 - gather * 0.85);

  const born = spring({ frame: frame - 178, fps: FPS, config: { damping: 15, mass: 0.9, stiffness: 120 } });
  const clear = progress(frame, 178, 44, EASE.out);
  const bloom = pulse(frame, 178, 18, 70) * 0.75 + progress(frame, 190, 40) * 0.2;
  const blink = pulse(frame, 232, 5, 8);
  const lookDown = progress(frame, 244, 14, EASE.inOut);
  const dive = progress(frame, LEGEND.from, LEGEND.at - LEGEND.from, EASE.inOut);
  const settle = progress(frame, LEGEND.at - 6, 8, EASE.in);

  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
      {lineFade > 0 && (
        <div
          style={{
            position: "absolute",
            top: 540 - 130,
            left: (1920 - lineWidth) / 2,
            width: lineWidth,
            height: 260,
            opacity: lineFade,
            clipPath: `inset(-200px ${(1 - draw) * 50}% -200px ${(1 - draw) * 50}%)`,
          }}
        >
          <div style={{ position: "absolute", inset: 0 }}>
            <Waveform
              frame={frame}
              level={lineLevel}
              width={lineWidth}
              height={260}
              colors={["rgba(187,154,247,0)", C.voiceB, C.voiceA, C.voiceC, "rgba(125,207,255,0)"]}
              strokeWidth={7}
              glow={16}
              points={110}
              spacing={1.3}
              idle={0.012}
              opacity={0.9}
              symmetric
            />
          </div>
          <div style={{ position: "absolute", inset: 0 }}>
            <Waveform
              frame={frame}
              level={lineLevel}
              width={lineWidth}
              height={260}
              colors={["rgba(245,245,247,0)", "#ffffff", "#ffffff", "#ffffff", "rgba(245,245,247,0)"]}
              strokeWidth={2.2}
              glow={0}
              points={110}
              spacing={1.3}
              idle={0.012}
              symmetric
            />
          </div>
        </div>
      )}

      {frame >= 176 && frame < LEGEND.at + 4 && (
        <div
          style={{
            position: "absolute",
            left: mix(960, LEGEND.x, dive),
            top: mix(540, LEGEND.y, dive),
            transform: `translate(-50%, -50%) scale(${mix(0.35, 1, born) * mix(1, LEGEND.scale, dive)}) scaleY(${mix(1, LEGEND.squash, dive)})`,
            opacity: clear * (1 - settle),
            filter: `blur(${mix(22, 0, clear)}px)`,
          }}
        >
          <div
            style={{
              position: "absolute",
              left: "50%",
              top: "50%",
              width: 520,
              height: 520,
              transform: "translate(-50%, -50%)",
              borderRadius: "50%",
              opacity: 1 - dive,
              background: `radial-gradient(circle, rgba(122,162,247,${0.55 * bloom}) 0%, rgba(187,154,247,${0.3 * bloom}) 32%, rgba(5,6,10,0) 66%)`,
              filter: "blur(20px)",
            }}
          />
          <Ghost size={168} color={C.paper} blink={blink} lookY={lookDown} />
        </div>
      )}
    </AbsoluteFill>
  );
};
