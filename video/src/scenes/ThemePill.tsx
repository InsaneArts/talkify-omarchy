import React from "react";
import { AbsoluteFill, spring } from "remotion";
import { C, EASE, FONT, FPS, mix, progress } from "../brand";
import { DESKTOP_H, DESKTOP_W, Desktop, Pill, DraftWord } from "../Desktop";
import { arrive, pulse } from "../fx";
import { ThemeChip } from "../ThemeChip";
import { Step, themeAt } from "../themeline";
import { AT } from "../timeline";

// 21.6–28.8 s. The pill in the middle of the screen, and the whole desktop
// behind it changing theme on the beat, faster and faster: Talkify follows
// the Omarchy theme the moment it changes. At the end the camera pulls back
// and the pill settles into its place at the bottom of the desktop.

const BEAT = 36;
const SEQUENCE: [string, number][] = [
  ["tokyo-night", 2],
  ["catppuccin", 2],
  ["gruvbox", 1],
  ["everforest", 1],
  ["rose-pine", 1],
  ["nord", 1],
  ["retro-82", 1],
  ["hackerman", 0.5],
  ["ristretto", 0.5],
  ["matte-black", 0.5],
  ["flexoki-light", 0.5],
  ["tokyo-night", 1],
];
export const THEME_STEPS: Step[] = SEQUENCE.reduce<Step[]>((steps, [id], index) => {
  const at = index === 0 ? AT.theme : steps[index - 1].at + SEQUENCE[index - 1][1] * BEAT;
  return [...steps, { id, at }];
}, []);

/** Where the desktop sits once the camera has pulled back; Places starts here. */
export const FRAMED = { scale: 0.78, x: 960, y: 440 };
const SETTLE = AT.places - 16;

const voice = (frame: number) => 0.35 + 0.55 * Math.abs(Math.sin(frame * 0.17) * Math.sin(frame * 0.053 + 0.6));

export const pillWords = (name: string, frame: number, at: number): DraftWord[] => {
  const tail = name.split(" ");
  const words: DraftWord[] = ["Looks", "good", "in"].map((text) => ({ text, t: 1 }));
  tail.forEach((text, index) =>
    words.push({
      text: index === tail.length - 1 ? text + "." : text,
      t: progress(frame, at + index * 3, 10, EASE.out),
      mark: "vocabulary",
    }),
  );
  return words;
};

export const ThemePill: React.FC<{ frame: number }> = ({ frame }) => {
  const now = themeAt(frame, THEME_STEPS);
  const enter = progress(frame, AT.theme - 10, 40, EASE.out);
  const settle = progress(frame, SETTLE, 40, EASE.inOut);
  const rise = spring({ frame: frame - AT.theme, fps: FPS, config: { damping: 14, stiffness: 120, mass: 0.8 } });
  const bump = pulse(frame, now.step.at, 3, 14);

  const scale = mix(1.23, FRAMED.scale, settle);
  const pillScale = mix(2.7, 1.5 * FRAMED.scale, settle);
  // The pill's bottom edge: mid-screen, then where the framed desktop draws it.
  const pillBottom = mix(660, FRAMED.y + (DESKTOP_H / 2 - 40) * FRAMED.scale, settle);
  const caption = arrive(frame, AT.theme + 24, 30, 30, 12);
  const out = 1 - settle;
  const captionOut = progress(frame, SETTLE - 14, 16, EASE.in);

  return (
    <AbsoluteFill style={{ opacity: enter }}>
      <div
        style={{
          position: "absolute",
          left: FRAMED.x - (DESKTOP_W * scale) / 2,
          top: mix(540, FRAMED.y, settle) - (DESKTOP_H * scale) / 2,
          width: DESKTOP_W,
          height: DESKTOP_H,
          transform: `scale(${scale})`,
          transformOrigin: "0 0",
          filter: `brightness(${mix(0.94, 1, settle)})`,
          borderRadius: 18,
          boxShadow: `0 0 0 1px rgba(255,255,255,${0.1 * settle}), 0 60px 160px rgba(0,0,0,${0.7 * settle})`,
        }}
      >
        <Desktop
          frame={frame}
          theme={now.theme}
          recording
          bare={1 - settle}
          hud={{ placement: "pill", reveal: 0, level: voice }}
          terminal={{ typed: "Refactor the parser and make every test pass.", sent: 1, lines: [1, 1, 1] }}
        />
      </div>

      <AbsoluteFill
        style={{
          background: "linear-gradient(180deg, rgba(5,6,10,0) 45%, rgba(5,6,10,0.82) 100%)",
          opacity: out,
        }}
      />

      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          top: 0,
          height: pillBottom + 40,
          transform: `translateY(${(1 - rise) * 260}px) scale(${1 + bump * 0.035})`,
          transformOrigin: `50% ${pillBottom}px`,
        }}
      >
        <Pill
          theme={now.theme}
          frame={frame}
          hud={{
            placement: "pill",
            reveal: Math.min(1, rise * 1.2),
            level: voice,
            scale: pillScale,
            words: pillWords(nameOf(now.step.id), frame, now.step.at),
          }}
        />
      </div>

      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          top: 790,
          textAlign: "center",
          opacity: caption.opacity * (1 - captionOut),
          transform: `translateY(${caption.y - captionOut * 24}px)`,
          filter: `blur(${caption.blur + captionOut * 10}px)`,
        }}
      >
        <div
          style={{
            fontFamily: FONT.display,
            fontWeight: 600,
            fontSize: 76,
            letterSpacing: "-0.035em",
            lineHeight: 1,
            color: C.paper,
            textShadow: "0 4px 30px rgba(0,0,0,0.5)",
          }}
        >
          It follows your Omarchy theme.
        </div>
        <div style={{ marginTop: 30 }}>
          <ThemeChip
            frame={frame}
            current={now.step.id}
            previous={now.previousStep?.id}
            changedAt={now.step.at}
            accent={now.theme.accent}
          />
        </div>
      </div>
    </AbsoluteFill>
  );
};

const NAMES: Record<string, string> = {
  "tokyo-night": "Tokyo Night",
  catppuccin: "Catppuccin",
  gruvbox: "Gruvbox",
  everforest: "Everforest",
  "rose-pine": "Rosé Pine",
  nord: "Nord",
  "retro-82": "Retro 82",
  hackerman: "Hackerman",
  ristretto: "Ristretto",
  "matte-black": "Matte Black",
  "flexoki-light": "Flexoki Light",
  "osaka-jade": "Osaka Jade",
  kanagawa: "Kanagawa",
};
export const nameOf = (id: string) => NAMES[id] ?? id;
