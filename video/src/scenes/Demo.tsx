import React from "react";
import { AbsoluteFill, spring } from "remotion";
import { EASE, FPS, mix, progress } from "../brand";
import { speech } from "../fx";
import { DESKTOP_H, DESKTOP_W, Desktop, DraftWord } from "../Desktop";
import { THEMES } from "../themes";

// 8–17 s. The desktop. The pill rises, the words land in the agent's box
// while they are still being spoken, "send it" presses Enter, the agent
// gets to work.

export const T = {
  enter: 496,
  pill: 628,
  chunkOne: 740,
  chunkTwo: 826,
  sendHeard: 852,
  enter_: 866,
  exit: 968,
};

const WORDS: { text: string; at: [number, number]; filler?: boolean; send?: boolean }[] = [
  { text: "Um,", at: [640, 656], filler: true },
  { text: "refactor", at: [672, 696] },
  { text: "the", at: [696, 704] },
  { text: "parser", at: [704, 728] },
  { text: "and", at: [750, 760] },
  { text: "make", at: [760, 772] },
  { text: "every", at: [772, 786] },
  { text: "test", at: [786, 798] },
  { text: "pass.", at: [798, 816] },
  { text: "send", at: [834, 846], send: true },
  { text: "it", at: [846, 856], send: true },
];
export const demoVoice = speech(WORDS.map((word) => word.at), 0.9);

const CHUNK_ONE = "Refactor the parser";
const CHUNK_TWO = " and make every test pass.";

export const Demo: React.FC<{ frame: number }> = ({ frame }) => {
  const enter = progress(frame, T.enter, 96, EASE.out);
  const push = progress(frame, 600, 360, EASE.inOut);
  const exit = progress(frame, T.exit, 40, EASE.in);
  const scale = mix(0.5, 0.88, enter) * mix(1, 1.1, push) * mix(1, 1.9, exit);

  const shown = spring({ frame: frame - T.pill, fps: FPS, config: { damping: 16, stiffness: 140, mass: 0.8 } });
  const hidden = progress(frame, T.enter_ + 6, 26, EASE.in);
  const words: DraftWord[] = WORDS.map((word) => ({
    text: word.filler ? word.text : word.text === "refactor" ? "Refactor" : word.text,
    t: progress(frame, word.at[0] + 4, 16, EASE.out),
    filler: word.filler,
    send: word.send,
  }));

  const typed = frame >= T.chunkTwo ? CHUNK_ONE + CHUNK_TWO : frame >= T.chunkOne ? CHUNK_ONE : "";
  const landed = frame >= T.chunkTwo ? T.chunkTwo : T.chunkOne;
  const press = Math.min(progress(frame, T.enter_ - 2, 4, EASE.in), 1 - progress(frame, T.enter_ + 4, 8));

  return (
    <AbsoluteFill
      style={{
        alignItems: "center",
        justifyContent: "center",
        opacity: Math.min(1, enter * 1.6) * (1 - exit),
      }}
    >
      <div
        style={{
          width: DESKTOP_W,
          height: DESKTOP_H,
          flexShrink: 0,
          transform: `translateY(${mix(140, 0, enter)}px) perspective(2400px) rotateX(${mix(22, 0, enter)}deg) scale(${scale})`,
          transformOrigin: "42% 70%",
          filter: `blur(${mix(18, 0, enter) + exit * 28}px)`,
          borderRadius: 18,
          boxShadow: "0 0 0 1px rgba(255,255,255,0.08), 0 80px 200px rgba(0,0,0,0.8)",
        }}
      >
        <Desktop
          frame={frame}
          theme={THEMES[0]}
          recording={frame >= T.pill && frame < T.enter_ + 4}
          hud={{
            placement: "pill",
            reveal: frame < T.pill ? 0 : Math.min(shown, 1 - hidden),
            level: demoVoice,
            words,
            fold: progress(frame, 686, 22, EASE.inOut),
            send: progress(frame, T.sendHeard, 12, EASE.out),
            press,
            sendFold: progress(frame, T.enter_ - 2, 14, EASE.inOut),
            scale: 1.5,
          }}
          terminal={{
            typed,
            freshFrom: landed === T.chunkTwo ? CHUNK_ONE.length : 0,
            fresh: typed ? 1 - progress(frame, landed, 48, EASE.inOut) : 0,
            sent: progress(frame, T.enter_ + 2, 22, EASE.out),
            lines: [
              progress(frame, 886, 16, EASE.out),
              progress(frame, 906, 16, EASE.out),
              progress(frame, 930, 16, EASE.out),
            ],
          }}
        />
      </div>
    </AbsoluteFill>
  );
};
