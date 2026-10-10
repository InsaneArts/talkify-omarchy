import React from "react";
import { AbsoluteFill, useCurrentFrame } from "remotion";
import { C, FONT } from "./brand";
import { loadFonts } from "./fonts";
import {
  DESKTOP_H,
  DESKTOP_W,
  Desktop,
  DraftWord,
  HudState,
  Mark,
  Neovim,
  Pill,
  Placement,
  TerminalState,
  Tok,
  tint,
} from "./Desktop";
import { OmarchyTheme, THEMES } from "./themes";

// The README's (and the landing page's) stills, one per frame: the film's
// desktop and HUD posed for each feature. `npm run shots` renders them all.

loadFonts();

const theme = (id: string) => THEMES.find((t) => t.id === id)!;
const TOKYO = theme("tokyo-night");

/** A voice caught mid-word, so the line has shape in a still. */
const voice = (frame: number) => 0.4 + 0.5 * Math.abs(Math.sin(frame * 0.19) * Math.sin(frame * 0.061 + 1.3));
const STILL = 300;

const words = (text: string, marks: Record<number, Mark> = {}, partial?: number): DraftWord[] =>
  text.split(" ").map((word, index, all) => ({
    text: word,
    t: partial !== undefined && index === all.length - 1 ? partial : 1,
    mark: marks[index],
  }));

const hud = (placement: Placement, extra: Partial<HudState> = {}): HudState => ({
  placement,
  reveal: 1,
  level: voice,
  ...extra,
});

const DONE: TerminalState = { typed: "", lines: [] };

/** The ground every shot stands on: near black, lit from behind in the theme's colours. */
const Stage: React.FC<{ glow?: OmarchyTheme; children: React.ReactNode }> = ({ glow, children }) => (
  <AbsoluteFill style={{ background: C.ink, overflow: "hidden" }}>
    {glow && (
      <div
        style={{
          position: "absolute",
          left: 960 - 900,
          top: 540 - 520,
          width: 1800,
          height: 1040,
          borderRadius: "50%",
          background: `radial-gradient(closest-side, ${tint(glow.wall[0], 0.34)}, ${tint(glow.wall[1], 0.14)} 55%, transparent)`,
          filter: "blur(50px)",
        }}
      />
    )}
    {children}
  </AbsoluteFill>
);

/** A desktop placed on the stage: `scale`, and the desktop point to centre on. */
const Placed: React.FC<{
  scale: number;
  focus?: [number, number];
  at?: [number, number];
  framed?: boolean;
  children: React.ReactNode;
}> = ({ scale, focus = [DESKTOP_W / 2, DESKTOP_H / 2], at = [960, 540], framed = true, children }) => (
  <div
    style={{
      position: "absolute",
      left: at[0] - focus[0] * scale,
      top: at[1] - focus[1] * scale,
      width: DESKTOP_W,
      height: DESKTOP_H,
      transform: `scale(${scale})`,
      transformOrigin: "0 0",
      borderRadius: 18,
      boxShadow: framed ? "0 0 0 1px rgba(255,255,255,0.1), 0 60px 160px rgba(0,0,0,0.7)" : undefined,
    }}
  >
    {children}
  </div>
);

const PROMPT = "Refactor the parser and make every test pass.";

const Hero: React.FC<{ frame: number }> = ({ frame }) => (
  <Stage glow={TOKYO}>
    <Placed scale={0.94}>
      <Desktop
        frame={frame}
        theme={TOKYO}
        recording
        hud={hud("pill", { words: [...words(PROMPT), { text: "send it", t: 1, mark: "send" }] })}
        terminal={{ typed: PROMPT, freshFrom: "Refactor the parser".length, fresh: 0.75 }}
      />
    </Placed>
  </Stage>
);

const Live: React.FC<{ frame: number }> = ({ frame }) => (
  <Stage>
    <Placed scale={1.38} focus={[630, 520]} framed={false}>
      <Desktop
        frame={frame}
        theme={TOKYO}
        recording
        hud={hud("pill", { words: words("Refactor the parser and make every", {}, 0.55) })}
        terminal={{ typed: "Refactor the parser", freshFrom: 0, fresh: 1 }}
      />
    </Placed>
    <AbsoluteFill
      style={{ background: "radial-gradient(130% 120% at 50% 50%, transparent 60%, rgba(5,6,10,0.75) 100%)" }}
    />
  </Stage>
);

/** A label in the film's mono, small and wide. */
const Label: React.FC<{ children: React.ReactNode; color?: string; style?: React.CSSProperties }> = ({
  children,
  color = C.mist,
  style,
}) => (
  <div style={{ fontFamily: FONT.mono, fontSize: 22, letterSpacing: "0.2em", color, textAlign: "center", ...style }}>
    {children}
  </div>
);

const Blurred: React.FC<{ theme: OmarchyTheme; frame: number }> = ({ theme, frame }) => (
  <div style={{ position: "absolute", inset: 0, filter: "blur(26px) brightness(0.45)", transform: "scale(1.08)" }}>
    <Placed scale={1.25} framed={false}>
      <Desktop frame={frame} theme={theme} recording={false} hud={hud("pill", { reveal: 0 })} terminal={DONE} />
    </Placed>
  </div>
);

const Tidy: React.FC<{ frame: number }> = ({ frame }) => {
  const t = theme("catppuccin");
  const draft = words("Um, the demo is on Friday, scratch that, Thursday at noon period", {
    0: "filler",
    4: "scratched",
    5: "scratched",
    6: "scratched",
    7: "scratched",
    11: "punctuation",
  });
  return (
    <Stage glow={t}>
      <Blurred theme={t} frame={frame} />
      <div style={{ position: "absolute", left: 0, right: 0, top: 150, height: 470 }}>
        <Pill theme={t} frame={frame} hud={hud("pill", { words: draft, scale: 3, wrap: true })} />
      </div>
      <Label style={{ position: "absolute", left: 0, right: 0, top: 700 }}>LANDS AS</Label>
      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          top: 752,
          textAlign: "center",
          fontFamily: FONT.display,
          fontWeight: 600,
          fontSize: 76,
          letterSpacing: "-0.03em",
          color: C.paper,
        }}
      >
        The demo is Thursday at noon.
      </div>
    </Stage>
  );
};

const WORDS_TXT: Tok[][] = [
  [["# Words to prefer", "com"]],
  [["Hyprland", "p"]],
  [["Quickshell", "p"]],
  [["Parakeet", "p"]],
  [],
  [["# Corrections", "com"]],
  [["omachi ", "p"], ["->", "acc"], [" Omarchy", "str"]],
  [["hyper land ", "p"], ["->", "acc"], [" Hyprland", "str"]],
  [["way bar ", "p"], ["->", "acc"], [" Waybar", "str"]],
  [],
  [["# Snippets", "com"]],
  [["sign off ", "p"], ["=>", "acc"], [" Best, Ghost", "str"]],
  [["my site ", "p"], ["=>", "acc"], [" usetalkify.app", "str"]],
];

const NOTES: Tok[][] = [
  [["# Weekly notes", "acc"]],
  [],
  [["- Shipped the live insertion fix.", "p"]],
  [["- Talk at the meetup on Thursday.", "p"]],
  [["- I moved my dotfiles to ", "p"], ["Omarchy", "hl"], [".", "p"]],
];

const Vocab: React.FC<{ frame: number }> = ({ frame }) => {
  const t = theme("osaka-jade");
  return (
    <Stage glow={t}>
      <Placed scale={0.94}>
        <Desktop
          frame={frame}
          theme={t}
          recording
          left={(th) => <Neovim theme={th} tabs={["words.txt"]} code={WORDS_TXT} lang="text" cursor={7} />}
          right={(th) => <Neovim theme={th} tabs={["notes.md"]} code={NOTES} lang="markdown" cursor={5} />}
          hud={hud("pill", { words: words("I moved my dotfiles to omachi", { 5: "vocabulary" }) })}
          terminal={DONE}
        />
      </Placed>
    </Stage>
  );
};

const CELLS: { placement: Placement; label: string; scale: number; focus: [number, number]; draft?: string }[] = [
  { placement: "pill", label: "Pill", scale: 0.6, focus: [800, 700], draft: "Ship it on Friday" },
  { placement: "caption", label: "Window caption", scale: 0.6, focus: [420, 690], draft: "Ship it on Friday" },
  { placement: "halo", label: "Halo", scale: 0.36, focus: [800, 440] },
  { placement: "island", label: "Bar island", scale: 0.78, focus: [1340, 190] },
  { placement: "pointer", label: "Pointer", scale: 0.62, focus: [1190, 560] },
  { placement: "notch", label: "Notch", scale: 0.6, focus: [800, 200], draft: "Ship it on Friday" },
];
const CELL_W = 576;
const CELL_H = 324;

const Placements: React.FC<{ frame: number }> = ({ frame }) => (
  <Stage glow={TOKYO}>
    {CELLS.map((cell, index) => {
      const column = index % 3;
      const row = Math.floor(index / 3);
      const left = (1920 - CELL_W * 3 - 40 * 2) / 2 + column * (CELL_W + 40);
      const top = 118 + row * (CELL_H + 110);
      return (
        <div key={cell.placement}>
          <div
            style={{
              position: "absolute",
              left,
              top,
              width: CELL_W,
              height: CELL_H,
              borderRadius: 16,
              overflow: "hidden",
              boxShadow: "0 0 0 1px rgba(255,255,255,0.1), 0 30px 80px rgba(0,0,0,0.6)",
              background: TOKYO.dark_background,
            }}
          >
            <Placed scale={cell.scale} focus={cell.focus} at={[CELL_W / 2, CELL_H / 2]} framed={false}>
              <Desktop
                frame={frame + index * 13}
                theme={TOKYO}
                recording
                pointer={{ x: 1130, y: 470 }}
                hud={hud(cell.placement, {
                  words: cell.draft ? words(cell.draft) : undefined,
                  scale: cell.placement === "halo" ? 3.4 : 1.7,
                  level: cell.placement === "halo" ? () => 0.85 : voice,
                })}
                terminal={{ typed: PROMPT, sent: 1, lines: [1, 1, 1] }}
              />
            </Placed>
          </div>
          <Label style={{ position: "absolute", left, width: CELL_W, top: top + CELL_H + 26 }} color={C.paper}>
            {cell.label.toUpperCase()}
          </Label>
        </div>
      );
    })}
  </Stage>
);

const SLICES = ["tokyo-night", "catppuccin", "gruvbox", "osaka-jade"];

const Themes: React.FC<{ frame: number }> = ({ frame }) => {
  const scale = 0.98;
  const width = (DESKTOP_W * scale) / SLICES.length;
  const gap = 3;
  const total = width * SLICES.length + gap * (SLICES.length - 1);
  const left = (1920 - total) / 2;
  const top = 64;
  return (
    <Stage glow={theme("catppuccin")}>
      {SLICES.map((id, index) => {
        const t = theme(id);
        return (
          <div key={id}>
            <div
              style={{
                position: "absolute",
                left: left + index * (width + gap),
                top,
                width,
                height: DESKTOP_H * scale,
                overflow: "hidden",
                borderRadius: index === 0 ? "18px 0 0 18px" : index === SLICES.length - 1 ? "0 18px 18px 0" : 0,
                boxShadow: "0 50px 140px rgba(0,0,0,0.6)",
              }}
            >
              <Placed scale={scale} focus={[(index * width) / scale, 0]} at={[0, 0]} framed={false}>
                <Desktop
                  frame={frame}
                  theme={t}
                  recording
                  hud={hud("pill", { words: words("Your theme, all the way down") })}
                  terminal={{ typed: PROMPT, sent: 1, lines: [1, 1, 1] }}
                />
              </Placed>
            </div>
            <Label
              color={t.accent}
              style={{ position: "absolute", left: left + index * (width + gap), width, top: top + DESKTOP_H * scale + 34 }}
            >
              {id}
            </Label>
          </div>
        );
      })}
    </Stage>
  );
};

export const SHOTS: { name: string; Shot: React.FC<{ frame: number }> }[] = [
  { name: "hero", Shot: Hero },
  { name: "live", Shot: Live },
  { name: "tidy", Shot: Tidy },
  { name: "vocabulary", Shot: Vocab },
  { name: "placements", Shot: Placements },
  { name: "themes", Shot: Themes },
];

export const Shots: React.FC = () => {
  const index = useCurrentFrame();
  const { Shot } = SHOTS[Math.min(index, SHOTS.length - 1)];
  return <Shot frame={STILL} />;
};
