import React from "react";
import { AbsoluteFill, interpolate, spring } from "remotion";
import { C, EASE, FONT, FPS, VOICE_GRADIENT, mix, progress } from "../brand";
import { passing, pulse, speech } from "../fx";
import { Ghost } from "../Ghost";
import { Waveform } from "../Waveform";

// 4–9 s. The right Super key rises and is pressed on the downbeat. Hold.
// Speak. Let go. Then the camera dives through it into the desktop.

export const PRESS = 288;
export const RELEASE = 444;
const SPEAK: [number, number][] = [
  [380, 398],
  [404, 416],
  [420, 436],
];
const voice = speech(SPEAK, 2.3);

/**
 * Where the ghost legend sits on screen once the key has risen (frame
 * LEGEND.at), worked out through the key's perspective: the intro's ghost
 * flies here and becomes it.
 */
export const LEGEND = { from: 250, at: 284, x: 1063.5, y: 387.8, scale: 0.252, squash: 0.92 };

const KEY_W = 380;
const KEY_H = 330;
const TOP_W = 318;
const TOP_H = 262;
const SKIRT = 40;

export const Keycap: React.FC<{ frame: number }> = ({ frame }) => {
  const rise = progress(frame, 238, 46, EASE.out);
  const down =
    frame < RELEASE
      ? progress(frame, PRESS - 3, 5, EASE.in)
      : 1 - spring({ frame: frame - RELEASE, fps: FPS, config: { damping: 9, stiffness: 260, mass: 0.6 } });
  const lit = Math.max(0, Math.min(1, down)) * (1 - progress(frame, RELEASE + 10, 40, EASE.inOut));
  const level = voice(frame);
  const flash = pulse(frame, PRESS, 3, 30);

  // Through the key and out the other side.
  const dive = progress(frame, 494, 50, EASE.in);
  const sceneScale = mix(1, 5.5, dive);

  const lineIn = progress(frame, 372, 20, EASE.out);
  const lineOut = progress(frame, 440, 20, EASE.inOut);
  const lineWidth = 1760 * lineIn * (1 - lineOut);

  const legend = interpolate(lit, [0, 1], [0, 1]);

  return (
    <AbsoluteFill
      style={{
        opacity: 1 - progress(frame, 520, 22, EASE.in),
        filter: `blur(${dive * 26}px)`,
        transform: `scale(${sceneScale})`,
        transformOrigin: "960px 470px",
      }}
    >
      {lineWidth > 2 && (
        <div style={{ position: "absolute", left: (1920 - lineWidth) / 2, top: 470 - 150, width: lineWidth, height: 300 }}>
          <div style={{ position: "absolute", inset: 0 }}>
            <Waveform
              frame={frame}
              level={voice}
              width={lineWidth}
              height={300}
              colors={["rgba(187,154,247,0)", C.voiceB, C.voiceA, C.voiceC, "rgba(125,207,255,0)"]}
              strokeWidth={6}
              glow={14}
              points={110}
              spacing={0.45}
              idle={0.01}
              symmetric
            />
          </div>
          <div style={{ position: "absolute", inset: 0 }}>
            <Waveform
              frame={frame}
              level={voice}
              width={lineWidth}
              height={300}
              colors={["rgba(255,255,255,0)", "#ffffff", "#ffffff", "#ffffff", "rgba(255,255,255,0)"]}
              strokeWidth={2}
              glow={0}
              points={110}
              spacing={0.45}
              idle={0.01}
              symmetric
            />
          </div>
        </div>
      )}

      <div
        style={{
          position: "absolute",
          left: 960 - KEY_W / 2,
          top: 470 - KEY_H / 2 + mix(720, 0, rise),
          width: KEY_W,
          height: KEY_H,
          perspective: 1400,
        }}
      >
        <div
          style={{
            position: "absolute",
            inset: 0,
            transform: `rotateX(${mix(46, 26, rise)}deg)`,
            transformOrigin: "50% 60%",
          }}
        >
          {/* The light under the key: the voice, spilling out round it. */}
          <div
            style={{
              position: "absolute",
              left: -150,
              top: -70,
              width: KEY_W + 300,
              height: KEY_H + 200,
              borderRadius: "50%",
              background: `conic-gradient(from 200deg, ${C.voiceB}, ${C.voiceA}, ${C.voiceC}, ${C.voiceB})`,
              filter: `blur(${60 - level * 14}px)`,
              opacity: 0.1 * rise + lit * (0.38 + level * 0.45) + flash * 0.3,
              transform: `scale(${0.82 + lit * 0.08 + level * 0.12})`,
            }}
          />
          <div
            style={{
              position: "absolute",
              left: 24,
              top: SKIRT + 24,
              width: KEY_W - 48,
              height: KEY_H - 20,
              borderRadius: 40,
              background: "rgba(0,0,0,0.9)",
              filter: `blur(${mix(30, 16, down)}px)`,
              transform: `translateY(${mix(26, 10, down)}px)`,
            }}
          />
          {/* The skirt. */}
          <div
            style={{
              position: "absolute",
              left: 0,
              top: 0,
              width: KEY_W,
              height: KEY_H,
              borderRadius: 46,
              background: "linear-gradient(180deg, #23252c 0%, #121318 55%, #0a0b0e 100%)",
              boxShadow: `inset 0 -2px 0 rgba(255,255,255,0.05), 0 0 0 1px rgba(255,255,255,${0.05 + lit * 0.18}), 0 ${2 + lit * 2}px ${lit * 26}px rgba(122,162,247,${lit * 0.6})`,
            }}
          />
          {/* The top: dished, lit from above, sinking when pressed. */}
          <div
            style={{
              position: "absolute",
              left: (KEY_W - TOP_W) / 2,
              top: 14 + down * (SKIRT - 18),
              width: TOP_W,
              height: TOP_H,
              borderRadius: 34,
              background: `radial-gradient(120% 90% at 50% 18%, rgba(255,255,255,0.09), rgba(255,255,255,0) 60%),
                linear-gradient(180deg, #3a3c45 0%, #26272e 48%, #1c1d23 100%)`,
              boxShadow: "inset 0 1.5px 0 rgba(255,255,255,0.22), inset 0 -10px 24px rgba(0,0,0,0.35), 0 2px 0 rgba(0,0,0,0.6)",
            }}
          >
            <div
              style={{
                position: "absolute",
                right: 32,
                top: 30,
                filter: `drop-shadow(0 0 ${legend * 10}px rgba(122,162,247,${legend}))`,
                opacity: progress(frame, LEGEND.at - 8, 10, EASE.out),
              }}
            >
              <Ghost size={44} color={legend > 0.01 ? `rgba(${Math.round(mix(214, 190, legend))}, ${Math.round(mix(217, 210, legend))}, ${Math.round(mix(224, 255, legend))}, 1)` : "#d6d9e0"} />
            </div>
            <div
              style={{
                position: "absolute",
                left: 32,
                bottom: 28,
                fontFamily: FONT.text,
                fontWeight: 500,
                fontSize: 34,
                letterSpacing: "0.01em",
                color: "#d6d9e0",
                textShadow: `0 0 ${legend * 14}px rgba(122,162,247,${legend * 0.9})`,
              }}
            >
              super
            </div>
          </div>
        </div>
      </div>

      <Caption frame={frame} />
    </AbsoluteFill>
  );
};

const word: React.CSSProperties = {
  position: "absolute",
  left: 0,
  right: 0,
  top: 776,
  textAlign: "center",
  fontFamily: FONT.display,
  fontWeight: 600,
  fontSize: 112,
  letterSpacing: "-0.035em",
  lineHeight: 1,
  color: C.paper,
};

const Caption: React.FC<{ frame: number }> = ({ frame }) => (
  <>
    <div style={{ ...word, ...passing(frame, PRESS + 8, 362) }}>Hold.</div>
    <div style={{ ...word, ...passing(frame, 370, 436) }}>
      <span
        style={{
          backgroundImage: VOICE_GRADIENT,
          WebkitBackgroundClip: "text",
          backgroundClip: "text",
          color: "transparent",
          padding: "0 0.06em",
        }}
      >
        Speak.
      </span>
    </div>
    <div style={{ ...word, ...passing(frame, RELEASE + 2, 488, { out: 12 }) }}>Let go.</div>
  </>
);
