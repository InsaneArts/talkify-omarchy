import React from "react";
import { AbsoluteFill, Img, staticFile, useCurrentFrame } from "remotion";
import { C, FONT } from "./brand";
import { loadFonts } from "./fonts";
import { DESKTOP_H, DESKTOP_W, Desktop, DraftWord, HudState, Mark, Pill, Placement, tint } from "./Desktop";
import { Ghost } from "./Ghost";
import { Spark } from "./scenes/Fun";
import { OmarchyTheme } from "./themes";
import { theme } from "./themeline";

// The README's pictures, and GitHub's social preview: the cover, then one
// picture per feature, each in another Omarchy theme. `npm run readme`
// renders them into .github/assets.

loadFonts();

const STILL = 300;
const voice = (frame: number) => 0.45 + 0.5 * Math.abs(Math.sin(frame * 0.19) * Math.sin(frame * 0.061 + 1.3));
const DONE = { typed: "Refactor the parser and make every test pass.", sent: 1, lines: [1, 1, 1] };
const SPARKS = ["#7aa2f7", "#f5c2e7", "#d8a657", "#82fb9c", "#f38d70", "#bb9af7", "#7dcfff", "#dbbc7f", "#a6e3a1", "#fab387"];

const words = (text: string, marks: Record<number, Mark> = {}): DraftWord[] =>
  text.split(" ").map((word, index) => ({ text: word, t: 1, mark: marks[index] }));

const hud = (placement: Placement, extra: Partial<HudState> = {}): HudState => ({
  placement,
  reveal: 1,
  level: voice,
  ...extra,
});

/** An Omarchy desktop at `scale`, its top-left corner at (x, y). */
const At: React.FC<{ x: number; y: number; scale: number; children: React.ReactNode; style?: React.CSSProperties }> = ({
  x,
  y,
  scale,
  children,
  style,
}) => (
  <div
    style={{
      position: "absolute",
      left: x,
      top: y,
      width: DESKTOP_W,
      height: DESKTOP_H,
      transform: `scale(${scale})`,
      transformOrigin: "0 0",
      ...style,
    }}
  >
    {children}
  </div>
);

/** The theme's wallpaper and bar, filling a 1920-wide picture. */
const Backdrop: React.FC<{ t: OmarchyTheme; height: number }> = ({ t, height }) => {
  const scale = Math.max(1920 / DESKTOP_W, height / DESKTOP_H) * 1.02;
  return (
    <At x={(1920 - DESKTOP_W * scale) / 2} y={(height - DESKTOP_H * scale) / 2} scale={scale}>
      <Desktop frame={STILL} theme={t} recording bare={1} hud={hud("pill", { reveal: 0 })} terminal={DONE} />
    </At>
  );
};

/** A real settings page, turned toward the rest of the picture. */
const Panel: React.FC<{ src: string; x: number; y: number; height: number; turn: number }> = ({ src, x, y, height, turn }) => (
  <div style={{ position: "absolute", left: x, top: y, height, aspectRatio: "1189 / 991", perspective: 2400 }}>
    <Img
      src={staticFile(src)}
      style={{
        width: "100%",
        height: "100%",
        borderRadius: 18,
        transform: `rotateY(${turn}deg)`,
        boxShadow: "0 60px 140px rgba(0,0,0,0.55), 0 0 0 1px rgba(255,255,255,0.08)",
      }}
    />
  </div>
);

/** A pill drawn on its own, its bottom edge at `bottom`, centred on `x`. */
const FloatingPill: React.FC<{ t: OmarchyTheme; x: number; bottom: number; hud: HudState }> = ({ t, x, bottom, hud }) => (
  <div style={{ position: "absolute", left: x - 960, top: 0, width: 1920, height: bottom + 40 }}>
    <Pill theme={t} frame={STILL} hud={hud} />
  </div>
);

const Sparkles: React.FC<{ x: number; y: number; t: number; spread?: number }> = ({ x, y, t, spread = 1 }) => (
  <div style={{ position: "absolute", left: x, top: y, transform: `scale(${spread})` }}>
    {SPARKS.map((colour, index) => (
      <Spark
        key={colour}
        angle={(index / SPARKS.length) * Math.PI * 2 - Math.PI / 2 + (index % 2) * 0.25}
        t={t * (index % 2 ? 0.86 : 1)}
        colour={colour}
        size={26 + (index % 3) * 9}
      />
    ))}
  </div>
);

const COVER_THEMES = ["gruvbox", "tokyo-night", "rose-pine", "hackerman", "ristretto"];
const NAMES: Record<string, string> = {
  catppuccin: "Catppuccin",
  gruvbox: "Gruvbox",
  "tokyo-night": "Tokyo Night",
  "rose-pine": "Rosé Pine",
  hackerman: "Hackerman",
  ristretto: "Ristretto",
};

/** The cover: the name, and the HUD looking good in six themes. */
export const Cover: React.FC = () => {
  const tile = 0.3;
  return (
    <AbsoluteFill style={{ background: C.ink, overflow: "hidden" }}>
      {["#7aa2f7", "#f5c2e7", "#d8a657", "#82fb9c"].map((colour, index) => (
        <div
          key={colour}
          style={{
            position: "absolute",
            left: [180, 1240, 420, 1460][index],
            top: [-200, -160, 420, 380][index],
            width: 760,
            height: 760,
            borderRadius: "50%",
            background: `radial-gradient(closest-side, ${tint(colour, 0.32)}, transparent)`,
            filter: "blur(40px)",
          }}
        />
      ))}

      {COVER_THEMES.map((id, index) => {
        const offset = index - (COVER_THEMES.length - 1) / 2;
        const angle = offset * 5;
        const cx = 960 + offset * 370;
        const cy = 742 + Math.abs(offset) * Math.abs(offset) * 14;
        const t = theme(id);
        return (
          <div
            key={id}
            style={{
              position: "absolute",
              left: cx - (DESKTOP_W * tile) / 2,
              top: cy - (DESKTOP_H * tile) / 2,
              width: DESKTOP_W * tile,
              height: DESKTOP_H * tile,
              transform: `rotate(${angle}deg)`,
              borderRadius: 12,
              overflow: "hidden",
              boxShadow: `0 40px 90px rgba(0,0,0,0.6), 0 0 0 1px rgba(255,255,255,0.12), 0 0 60px ${tint(t.accent, 0.25)}`,
              zIndex: 10 - Math.abs(offset) * 2,
            }}
          >
            <At x={0} y={0} scale={tile}>
              <Desktop
                frame={STILL + index * 17}
                theme={t}
                recording
                bare={1}
                hud={hud("pill", { words: words(`Looks good in ${NAMES[id]}.`, { 3: "vocabulary", 4: "vocabulary" }), scale: 2.4 })}
                terminal={DONE}
              />
            </At>
          </div>
        );
      })}

      <div style={{ position: "absolute", left: 0, right: 0, top: 58, display: "flex", flexDirection: "column", alignItems: "center" }}>
        <div style={{ position: "relative", height: 138 }}>
          <Sparkles x={60} y={56} t={0.44} spread={0.8} />
          <div style={{ transform: "rotate(-6deg) translateY(-6px)" }}>
            <Ghost size={124} color={C.paper} look={0.3} />
          </div>
        </div>
        <div
          style={{
            marginTop: 8,
            fontFamily: FONT.display,
            fontWeight: 700,
            fontSize: 150,
            letterSpacing: "-0.045em",
            lineHeight: 1,
            color: C.paper,
          }}
        >
          Talkify
        </div>
        <div style={{ marginTop: 26, display: "flex", alignItems: "center", gap: 18 }}>
          <span style={{ fontFamily: FONT.display, fontWeight: 500, fontSize: 40, color: C.mist, letterSpacing: "-0.01em" }}>for</span>
          <Img src={staticFile("omarchy-logo.svg")} style={{ height: 40, filter: "invert(1)" }} />
        </div>
        <div
          style={{
            marginTop: 22,
            fontFamily: FONT.display,
            fontWeight: 500,
            fontSize: 36,
            color: C.mist,
            letterSpacing: "-0.015em",
          }}
        >
          Fast, beautiful and private voice dictation.
        </div>
      </div>
    </AbsoluteFill>
  );
};

const PLACES: { placement: Placement; label: string; id: string; scale: number; focus: [number, number]; draft?: string }[] = [
  { placement: "pill", label: "Pill", id: "tokyo-night", scale: 0.6, focus: [800, 700], draft: "Looks good in Tokyo Night." },
  { placement: "caption", label: "Window", id: "catppuccin", scale: 0.6, focus: [420, 690], draft: "Looks good in Catppuccin." },
  { placement: "halo", label: "Halo", id: "hackerman", scale: 0.36, focus: [800, 440] },
  { placement: "island", label: "Island", id: "gruvbox", scale: 0.78, focus: [1340, 190] },
  { placement: "pointer", label: "Pointer", id: "rose-pine", scale: 0.62, focus: [1190, 560] },
  { placement: "notch", label: "Notch", id: "ristretto", scale: 0.6, focus: [800, 200], draft: "Looks good in Ristretto." },
];

/** Appearance: every placement, each in another theme. */
const Appearance: React.FC = () => {
  const w = 576;
  const h = 324;
  return (
    <AbsoluteFill style={{ background: C.ink }}>
      {PLACES.map((cell, index) => {
        const column = index % 3;
        const row = Math.floor(index / 3);
        const left = (1920 - w * 3 - 44 * 2) / 2 + column * (w + 44);
        const top = 110 + row * (h + 116);
        const t = theme(cell.id);
        return (
          <div key={cell.label}>
            <div
              style={{
                position: "absolute",
                left,
                top,
                width: w,
                height: h,
                borderRadius: 18,
                overflow: "hidden",
                boxShadow: `0 0 0 1px rgba(255,255,255,0.1), 0 30px 80px rgba(0,0,0,0.6), 0 0 70px ${tint(t.accent, 0.22)}`,
              }}
            >
              <At x={w / 2 - cell.focus[0] * cell.scale} y={h / 2 - cell.focus[1] * cell.scale} scale={cell.scale}>
                <Desktop
                  frame={STILL + index * 13}
                  theme={t}
                  recording
                  pointer={{ x: 1130, y: 470 }}
                  hud={hud(cell.placement, {
                    words: cell.draft ? words(cell.draft, { 3: "vocabulary", 4: "vocabulary" }) : undefined,
                    scale: cell.placement === "halo" ? 3.4 : 1.7,
                    level: cell.placement === "halo" ? () => 0.85 : voice,
                  })}
                  terminal={DONE}
                />
              </At>
            </div>
            <div
              style={{
                position: "absolute",
                left,
                width: w,
                top: top + h + 26,
                textAlign: "center",
                fontFamily: FONT.display,
                fontWeight: 600,
                fontSize: 40,
                letterSpacing: "-0.02em",
                color: C.paper,
              }}
            >
              {cell.label}
              <span style={{ marginLeft: 14, fontFamily: FONT.mono, fontWeight: 400, fontSize: 20, color: t.accent }}>{cell.id}</span>
            </div>
          </div>
        );
      })}
    </AbsoluteFill>
  );
};

/** Vocabulary: what it heard, and what it writes, beside the page that teaches it. */
const Vocabulary: React.FC = () => {
  const t = theme("gruvbox");
  return (
    <AbsoluteFill style={{ background: C.ink, overflow: "hidden" }}>
      <Backdrop t={t} height={1080} />
      <AbsoluteFill style={{ background: "linear-gradient(90deg, rgba(5,6,10,0.15), rgba(5,6,10,0.55))" }} />
      <Panel src="settings/vocabulary.png" x={110} y={150} height={780} turn={14} />
      <FloatingPill
        t={t}
        x={1460}
        bottom={600}
        hud={hud("pill", {
          words: words("I moved my dotfiles to omachi Omarchy", { 5: "scratched", 6: "vocabulary" }),
          scale: 1.9,
          wrap: true,
        })}
      />
    </AbsoluteFill>
  );
};

/** Insights: the page in Ristretto, and the ghost celebrating a milestone. */
const Insights: React.FC = () => {
  const t = theme("ristretto");
  return (
    <AbsoluteFill style={{ background: C.ink, overflow: "hidden" }}>
      <Backdrop t={t} height={1080} />
      <AbsoluteFill style={{ background: "linear-gradient(90deg, rgba(5,6,10,0.15), rgba(5,6,10,0.5))" }} />
      <Panel src="settings/insights.png" x={110} y={150} height={780} turn={14} />
      <div style={{ position: "absolute", left: 1420, top: 420 }}>
        <Sparkles x={0} y={0} t={0.62} spread={1.5} />
        <div style={{ position: "absolute", left: 0, top: 0, transform: "translate(-50%, -50%) rotate(-8deg)" }}>
          <Ghost size={210} color={C.paper} look={-0.4} />
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          left: 1420,
          top: 640,
          transform: "translateX(-50%)",
          padding: "16px 30px",
          borderRadius: 18,
          fontFamily: FONT.mono,
          fontSize: 40,
          color: t.bright_foreground,
          background: tint(t.dark_background, 0.85),
          boxShadow: `inset 0 0 0 2px ${t.accent}, 0 20px 50px rgba(0,0,0,0.45), 0 0 50px ${tint(t.accent, 0.4)}`,
          whiteSpace: "nowrap",
        }}
      >
        10,000 words
      </div>
    </AbsoluteFill>
  );
};

/** App rules: "send it" in a terminal presses Enter. */
const AppRules: React.FC = () => {
  const t = theme("rose-pine");
  return (
    <AbsoluteFill style={{ background: C.ink, overflow: "hidden" }}>
      <Backdrop t={t} height={1080} />
      <AbsoluteFill style={{ background: "linear-gradient(90deg, rgba(5,6,10,0.05), rgba(5,6,10,0.4))" }} />
      <Panel src="settings/apps.png" x={110} y={150} height={780} turn={14} />
      <FloatingPill
        t={t}
        x={1460}
        bottom={620}
        hud={hud("pill", {
          words: [...words("Run the tests and fix what fails"), { text: "send it", t: 1, mark: "send" }],
          scale: 1.9,
          wrap: true,
          send: 1,
          press: 0.7,
        })}
      />
    </AbsoluteFill>
  );
};

export const FEATURES: { name: string; Picture: React.FC }[] = [
  { name: "appearance", Picture: Appearance },
  { name: "vocabulary", Picture: Vocabulary },
  { name: "insights", Picture: Insights },
  { name: "app-rules", Picture: AppRules },
];

export const Features: React.FC = () => {
  const { Picture } = FEATURES[Math.min(useCurrentFrame(), FEATURES.length - 1)];
  return <Picture />;
};
