import React from "react";
import { FONT, mix, mixColor } from "./brand";
import { Ghost } from "./Ghost";
import { OmarchyTheme } from "./themes";
import { Waveform } from "./Waveform";

// An Omarchy desktop at 1600×900: a wallpaper lit in the theme's colours,
// the bar, two tiled Hyprland windows with blur behind them (a coding agent
// and neovim), and Talkify's HUD in one of its placements, drawn the way
// the plugin draws them. Every colour comes from `theme`, so the whole
// screen can change themes on the beat.

export const DESKTOP_W = 1600;
export const DESKTOP_H = 900;
const BAR_H = 36;
const GAP = 14;
const TOP = BAR_H + GAP / 2;
const HALF = (DESKTOP_W - GAP * 3) / 2;
export const WINDOWS = {
  left: { x: GAP, y: TOP, w: HALF, h: DESKTOP_H - TOP - GAP },
  right: { x: GAP * 2 + HALF, y: TOP, w: HALF, h: DESKTOP_H - TOP - GAP },
};

export type Placement = "pill" | "caption" | "halo" | "island" | "pointer" | "notch";

/** The marks the daemon lays over a Live draft, drawn as the plugin draws them. */
export type Mark = "filler" | "scratched" | "punctuation" | "vocabulary" | "send";

export type DraftWord = {
  text: string;
  /** 0 unheard → 1 on screen. */
  t: number;
  /** A filler: faint, then folded away by `fold`. */
  filler?: boolean;
  /** Part of the spoken send: drawn in the accent, folded away by `sendFold`. */
  send?: boolean;
  mark?: Mark;
};

export type HudState = {
  placement: Placement;
  /** 0 hidden → 1 shown. */
  reveal: number;
  level: (frame: number) => number;
  words?: DraftWord[];
  /** 0–1: fillers fold out of the draft. */
  fold?: number;
  /** The ⏎ a spoken send presses: `send` shows it, `press` pushes it down. */
  send?: number;
  press?: number;
  /** 0–1: the spoken send's words fold into the ⏎ they pressed. */
  sendFold?: number;
  /** The HUD drawn larger than life, so it reads in a wide shot. */
  scale?: number;
  /** Let the draft wrap onto a second line, as the pill's grow-down style does. */
  wrap?: boolean;
};

export type TerminalState = {
  /** What sits in the agent's input box. */
  typed: string;
  /** Where the newest pasted chunk starts in `typed`, and how fresh it is. */
  freshFrom?: number;
  fresh?: number;
  /** 0–1: the prompt leaves the box for the history. */
  sent?: number;
  /** Agent lines printed, each 0–1. */
  lines?: number[];
  cursor?: boolean;
};

/** #rrggbb or rgb() → rgba(). */
export const tint = (color: string, a: number) => {
  if (color.startsWith("#")) {
    const r = parseInt(color.slice(1, 3), 16);
    const g = parseInt(color.slice(3, 5), 16);
    const b = parseInt(color.slice(5, 7), 16);
    return `rgba(${r}, ${g}, ${b}, ${a})`;
  }
  return color.replace("rgb(", "rgba(").replace(")", `, ${a})`);
};

const toHex = (color: string) => {
  if (color.startsWith("#")) return color.toLowerCase();
  const [r, g, b] = color.match(/\d+/g)!.map(Number);
  return `#${[r, g, b].map((v) => v.toString(16).padStart(2, "0")).join("")}`;
};

const blendColor = (a: string, b: string, t: number) => toHex(mixColor(a.toLowerCase(), b.toLowerCase(), t));

export const blendTheme = (a: OmarchyTheme, b: OmarchyTheme, t: number): OmarchyTheme => {
  if (t <= 0) return a;
  if (t >= 1) return b;
  const out = { ...a } as Record<string, unknown>;
  for (const key of Object.keys(a) as (keyof OmarchyTheme)[]) {
    if (key === "id" || key === "name") continue;
    if (key === "wall") {
      out.wall = a.wall.map((color, index) => blendColor(color, b.wall[index], t));
      continue;
    }
    out[key] = blendColor(a[key], b[key], t);
  }
  return out as unknown as OmarchyTheme;
};

const Wallpaper: React.FC<{ theme: OmarchyTheme; frame: number }> = ({ theme, frame }) => {
  const [one, two, three] = theme.wall;
  const drift = Math.sin(frame / 200) * 30;
  return (
    <div
      style={{
        position: "absolute",
        inset: 0,
        background: `radial-gradient(900px 640px at ${12 + drift / 40}% 8%, ${tint(one, 0.62)}, transparent 70%),
          radial-gradient(1000px 760px at 96% ${92 - drift / 40}%, ${tint(two, 0.55)}, transparent 70%),
          radial-gradient(700px 520px at 64% 40%, ${tint(three, 0.32)}, transparent 72%),
          linear-gradient(160deg, ${theme.dark_background}, ${theme.background})`,
      }}
    />
  );
};

const Frosted: React.FC<{
  rect: { x: number; y: number; w: number; h: number };
  theme: OmarchyTheme;
  active: boolean;
  children?: React.ReactNode;
}> = ({ rect, theme, active, children }) => (
  <div
    style={{
      position: "absolute",
      left: rect.x,
      top: rect.y,
      width: rect.w,
      height: rect.h,
      borderRadius: 10,
      padding: 2,
      background: active ? `linear-gradient(135deg, ${theme.accent}, ${theme.magenta})` : tint(theme.muted, 0.7),
      boxShadow: "0 30px 70px rgba(0,0,0,0.35)",
    }}
  >
    <div
      style={{
        width: "100%",
        height: "100%",
        borderRadius: 8,
        background: tint(theme.background, 0.84),
        backdropFilter: "blur(28px) saturate(1.4)",
        overflow: "hidden",
        position: "relative",
      }}
    >
      {children}
    </div>
  </div>
);

const MONO = 23;
const LINE = 38;

const AGENT_LINES: { mark: string; text: string; tone: "accent" | "green" }[] = [
  { mark: "●", text: "Reading crates/core/src/parser.rs", tone: "accent" },
  { mark: "●", text: "Running cargo test", tone: "accent" },
  { mark: "✓", text: "214 tests passed", tone: "green" },
];

const Terminal: React.FC<{ theme: OmarchyTheme; state: TerminalState; frame: number }> = ({
  theme,
  state,
  frame,
}) => {
  const sent = state.sent ?? 0;
  const lines = state.lines ?? [];
  const mono: React.CSSProperties = {
    fontFamily: FONT.mono,
    fontSize: MONO,
    lineHeight: `${LINE}px`,
    whiteSpace: "pre",
  };
  const cursorOn = (state.cursor ?? true) && Math.floor(frame / 32) % 2 === 0;
  const freshFrom = state.freshFrom ?? state.typed.length;
  const fresh = state.fresh ?? 0;
  const inBox = sent > 0 ? "" : state.typed;
  return (
    <div style={{ padding: "26px 32px", color: theme.foreground }}>
      <div style={{ ...mono, fontSize: 19, color: theme.muted }}>
        <span style={{ color: theme.blue }}>~/projects/talkify</span>
        <span>  main</span>
      </div>
      <div style={{ opacity: 0.5, marginTop: 18 }}>
        <div style={{ ...mono, color: theme.foreground }}>
          <span style={{ color: theme.magenta }}>› </span>Why does the last word go missing?
        </div>
        <div style={{ ...mono, color: theme.foreground }}>
          <span style={{ color: theme.accent }}>● </span>Cuts now land only in silence.
        </div>
      </div>
      {sent > 0 && (
        <div style={{ height: LINE * 2.3 * Math.min(1, sent * 1.4), overflow: "hidden" }}>
          <div
            style={{
              ...mono,
              marginTop: 16,
              whiteSpace: "normal",
              color: theme.bright_foreground,
              opacity: sent,
              transform: `translateY(${(1 - sent) * 44}px)`,
            }}
          >
            <span style={{ color: theme.magenta }}>› </span>
            {state.typed}
          </div>
        </div>
      )}
      {lines.map((t, index) =>
        t > 0 ? (
          <div key={index} style={{ height: LINE * Math.min(1, t * 1.6), overflow: "hidden" }}>
            <div style={{ ...mono, opacity: t, transform: `translateY(${(1 - t) * 12}px)` }}>
              <span style={{ color: AGENT_LINES[index].tone === "green" ? theme.green : theme.accent }}>
                {AGENT_LINES[index].mark}{" "}
              </span>
              <span style={{ color: AGENT_LINES[index].tone === "green" ? theme.bright_foreground : theme.foreground }}>
                {AGENT_LINES[index].text}
              </span>
            </div>
          </div>
        ) : null,
      )}
      <div
        style={{
          marginTop: 20,
          border: `1.5px solid ${tint(theme.accent, 0.6)}`,
          borderRadius: 12,
          padding: "14px 18px",
          minHeight: LINE * 2,
          ...mono,
          whiteSpace: "normal",
          color: theme.bright_foreground,
          background: tint(theme.dark_background, 0.4),
        }}
      >
        <span style={{ color: theme.magenta }}>› </span>
        {inBox ? (
          <>
            {inBox.slice(0, freshFrom)}
            <span
              style={{
                borderRadius: 5,
                background: tint(theme.accent, 0.32 * fresh),
                boxShadow: `0 0 ${20 * fresh}px ${tint(theme.accent, 0.4 * fresh)}`,
              }}
            >
              {inBox.slice(freshFrom)}
            </span>
          </>
        ) : (
          <span style={{ color: theme.muted }}>{sent > 0 ? "" : "Ask anything"}</span>
        )}
        <span
          style={{
            display: "inline-block",
            width: 12,
            height: 27,
            marginLeft: 3,
            transform: "translateY(6px)",
            background: cursorOn ? theme.accent : "transparent",
          }}
        />
      </div>
    </div>
  );
};

export type Tok = [string, "kw" | "fn" | "ty" | "str" | "com" | "mac" | "num" | "p" | "acc" | "hl"];
const CODE: Tok[][] = [
  [["use ", "kw"], ["crate", "kw"], ["::token::{", "p"], ["Kind", "ty"], [", ", "p"], ["Token", "ty"], ["};", "p"]],
  [],
  [["/// Splits a transcript into words.", "com"]],
  [["pub fn ", "kw"], ["parse", "fn"], ["(input: &", "p"], ["str", "ty"], [") -> ", "p"], ["Vec", "ty"], ["<", "p"], ["Token", "ty"], ["> {", "p"]],
  [["  let mut ", "kw"], ["tokens = ", "p"], ["Vec", "ty"], ["::", "p"], ["new", "fn"], ["();", "p"]],
  [["  for ", "kw"], ["word ", "p"], ["in ", "kw"], ["input.", "p"], ["split_whitespace", "fn"], ["() {", "p"]],
  [["    let ", "kw"], ["kind = ", "p"], ["Kind", "ty"], ["::", "p"], ["of", "fn"], ["(word);", "p"]],
  [["    tokens.", "p"], ["push", "fn"], ["(", "p"], ["Token", "ty"], ["::", "p"], ["new", "fn"], ["(word, kind));", "p"]],
  [["  }", "p"]],
  [["  tokens", "p"]],
  [["}", "p"]],
  [],
  [["#[test]", "mac"]],
  [["fn ", "kw"], ["parses_a_sentence", "fn"], ["() {", "p"]],
  [["  let ", "kw"], ["tokens = ", "p"], ["parse", "fn"], ["(", "p"], ['"send it"', "str"], [");", "p"]],
  [["  assert_eq!", "mac"], ["(tokens.", "p"], ["len", "fn"], ["(), ", "p"], ["2", "num"], [");", "p"]],
  [["}", "p"]],
];

export const Neovim: React.FC<{
  theme: OmarchyTheme;
  tabs?: string[];
  code?: Tok[][];
  lang?: string;
  cursor?: number;
}> = ({ theme, tabs = ["parser.rs", "live.rs", "tidy.rs"], code = CODE, lang = "rust", cursor = 4 }) => {
  const color = (kind: Tok[1]) =>
    ({
      kw: theme.magenta,
      fn: theme.blue,
      ty: theme.yellow,
      str: theme.green,
      com: theme.muted,
      mac: theme.cyan,
      num: theme.red,
      p: theme.foreground,
      acc: theme.accent,
      hl: theme.bright_foreground,
    })[kind];
  return (
    <div style={{ position: "absolute", inset: 0, fontFamily: FONT.mono, fontSize: 19, lineHeight: "31px" }}>
      <div
        style={{
          display: "flex",
          gap: 0,
          fontSize: 16,
          lineHeight: "34px",
          background: tint(theme.dark_background, 0.5),
          color: theme.foreground,
        }}
      >
        {tabs.map((tab, index) => (
          <span
            key={tab}
            style={
              index === 0
                ? { padding: "0 18px", background: tint(theme.accent, 0.18), color: theme.bright_foreground }
                : { padding: "0 18px", opacity: 0.55 }
            }
          >
            {tab}
          </span>
        ))}
      </div>
      <div style={{ padding: "16px 0" }}>
        {code.map((line, index) => (
          <div key={index} style={{ display: "flex", whiteSpace: "pre" }}>
            <span style={{ width: 58, textAlign: "right", paddingRight: 20, color: index === cursor - 1 ? theme.accent : tint(theme.muted, 0.9) }}>
              {index + 1}
            </span>
            <span>
              {line.map(([text, kind], tokenIndex) => (
                <span
                  key={tokenIndex}
                  style={{
                    color: color(kind),
                    borderRadius: 4,
                    background: kind === "hl" ? tint(theme.accent, 0.35) : undefined,
                    boxShadow: kind === "hl" ? `0 0 18px ${tint(theme.accent, 0.4)}` : undefined,
                  }}
                >
                  {text}
                </span>
              ))}
            </span>
          </div>
        ))}
      </div>
      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          bottom: 0,
          display: "flex",
          fontSize: 16,
          lineHeight: "34px",
          background: tint(theme.dark_background, 0.6),
          color: theme.foreground,
        }}
      >
        <span style={{ padding: "0 16px", background: theme.accent, color: theme.dark_background, fontWeight: 700 }}>
          NORMAL
        </span>
        <span style={{ padding: "0 16px", opacity: 0.8 }}> main</span>
        <span style={{ flex: 1 }} />
        <span style={{ padding: "0 16px", opacity: 0.7 }}>{lang}</span>
        <span style={{ padding: "0 16px", background: tint(theme.accent, 0.25) }}>4:12</span>
      </div>
    </div>
  );
};

const VOICE_STOPS = (theme: OmarchyTheme) => [
  tint(theme.bright_foreground, 0),
  theme.bright_foreground,
  theme.accent,
  theme.magenta,
  tint(theme.magenta, 0),
];

/** The ⏎ a spoken send presses, at the pill's far end. */
const SendKey: React.FC<{ theme: OmarchyTheme; send: number; press: number; size: number }> = ({
  theme,
  send,
  press,
  size,
}) => (
  <div
    style={{
      width: size * 1.25,
      height: size,
      borderRadius: size * 0.26,
      display: "grid",
      placeItems: "center",
      fontFamily: FONT.text,
      fontWeight: 600,
      fontSize: size * 0.62,
      color: "#05060a",
      background: theme.accent,
      opacity: send,
      transform: `translateY(${press * 3}px) scale(${mix(0.4, 1, send) * (1 - press * 0.06)})`,
      boxShadow: `0 ${4 - press * 4}px 0 ${tint(theme.accent, 0.45)}, 0 0 ${press * 30}px ${tint(theme.accent, 0.8 * press)}`,
    }}
  >
    ⏎
  </div>
);

/** A Live draft with its marks, one word at a time. */
const Draft: React.FC<{ theme: OmarchyTheme; hud: HudState; size: number; wrap?: boolean }> = ({
  theme,
  hud,
  size,
  wrap,
}) => {
  const fold = hud.fold ?? 0;
  return (
    <div
      style={{
        fontFamily: FONT.text,
        fontWeight: 500,
        fontSize: size,
        lineHeight: `${size * 1.4}px`,
        color: "#f5f5f7",
        whiteSpace: wrap ? "normal" : "nowrap",
        overflow: "hidden",
        display: "flex",
        flexWrap: wrap ? "wrap" : "nowrap",
        justifyContent: "flex-start",
        alignItems: "baseline",
      }}
    >
      {(hud.words ?? []).map((word, index) => {
        const mark = word.mark ?? (word.filler ? "filler" : undefined);
        const folds = mark === "filler" || mark === "scratched";
        const gone = folds ? fold : word.send ? hud.sendFold ?? 0 : 0;
        const t = word.t * (1 - gone);
        const faint = mark === "filler" ? 0.36 : mark === "scratched" ? 0.5 : 1;
        if (mark === "send") {
          return (
            <span
              key={index}
              style={{
                display: "inline-grid",
                placeItems: "center",
                height: size * 1.15,
                padding: `0 ${size * 0.38}px`,
                marginRight: "0.26em",
                borderRadius: size * 0.28,
                background: theme.accent,
                color: "#05060a",
                fontWeight: 600,
                fontSize: size * 0.8,
                opacity: t,
                alignSelf: "center",
              }}
            >
              ⏎
            </span>
          );
        }
        return (
          <span
            key={index}
            style={{
              display: "inline-block",
              overflow: "hidden",
              maxWidth: wrap ? undefined : `${t * (word.text.length * 0.62 + 0.3)}em`,
              opacity: faint * word.t * (1 - gone) ** 2,
              filter: `blur(${(1 - word.t) * 6 + gone * 6}px)`,
              textDecoration: mark === "scratched" ? "line-through" : "none",
              textDecorationThickness: Math.max(2, size * 0.07),
              color: mark === "vocabulary" || word.send ? theme.accent : undefined,
              boxShadow: mark === "punctuation" ? `inset 0 -${Math.max(2, size * 0.09)}px 0 ${theme.accent}` : undefined,
              marginRight: "0.26em",
              paddingBottom: mark === "punctuation" ? size * 0.04 : 0,
            }}
          >
            {word.text}
          </span>
        );
      })}
    </div>
  );
};

/** The ghost and the voice: the row every placement carries. */
const VoiceRow: React.FC<{ theme: OmarchyTheme; hud: HudState; frame: number; s: number; width: number; points: number }> = ({
  theme,
  hud,
  frame,
  s,
  width,
  points,
}) => {
  const level = hud.level(frame);
  const blink = Math.max(0, 1 - Math.abs(((frame + 40) % 170) - 4) / 4);
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 10 * s, height: 40 * s }}>
      <div style={{ transform: `translateY(${-level * 3 * s}px)` }}>
        <Ghost size={17 * s} color={theme.bright_foreground} blink={blink} />
      </div>
      <div style={{ height: 28 * s }}>
        <Waveform
          frame={frame}
          level={hud.level}
          width={width}
          height={28 * s}
          strokeWidth={1.6 * s}
          glow={3}
          points={points}
          colors={VOICE_STOPS(theme)}
        />
      </div>
    </div>
  );
};

const capsule = (theme: OmarchyTheme, level: number, radius: number): React.CSSProperties => ({
  borderRadius: radius,
  background: "#000",
  boxShadow: `0 0 0 1px ${tint(theme.foreground, 0.12)}, 0 24px 60px rgba(0,0,0,0.55), 0 0 ${50 * level}px ${tint(theme.accent, 0.35)}`,
});

/** The bottom pill: the draft hangs above a row of ghost, voice and ⏎. */
export const Pill: React.FC<{ theme: OmarchyTheme; hud: HudState; frame: number }> = ({ theme, hud, frame }) => {
  const s = hud.scale ?? 1.5;
  const words = hud.words ?? [];
  const heard = words.some((word) => word.t > 0);
  const send = hud.send ?? 0;
  const press = hud.press ?? 0;
  const reveal = hud.reveal;
  const pad = 14 * s;
  const row = 40 * s;
  const width = heard ? 420 * s : 184 * s + (send > 0 ? 40 * s * send : 0);
  return (
    <div
      style={{
        position: "absolute",
        left: "50%",
        bottom: 40,
        width,
        transform: `translateX(-50%) translateY(${(1 - reveal) * (row + 60)}px)`,
        opacity: Math.min(1, reveal * 2),
        ...capsule(theme, hud.level(frame), row / 2),
        padding: `${heard ? pad * 0.9 : 0}px ${pad}px 0`,
      }}
    >
      {heard && <Draft theme={theme} hud={hud} size={15 * s} wrap={hud.wrap} />}
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
        <VoiceRow
          theme={theme}
          hud={hud}
          frame={frame}
          s={s}
          width={width - pad * 2 - 27 * s - (send > 0 ? 40 * s : 0)}
          points={heard ? 60 : 30}
        />
        {send > 0 && <SendKey theme={theme} send={send} press={press} size={24 * s} />}
      </div>
    </div>
  );
};

/** The window caption: the pill pinned to the window the text is going to, above its bottom band. */
const Caption: React.FC<{ theme: OmarchyTheme; hud: HudState; frame: number; rect: { x: number; y: number; w: number; h: number } }> = ({
  theme,
  hud,
  frame,
  rect,
}) => {
  const s = hud.scale ?? 1.5;
  const heard = (hud.words ?? []).some((word) => word.t > 0);
  const width = heard ? Math.min(rect.w - 60, 400 * s) : 184 * s;
  const pad = 14 * s;
  return (
    <div
      style={{
        position: "absolute",
        left: rect.x + rect.w / 2,
        top: rect.y + rect.h - 72,
        width,
        transform: `translate(-50%, -100%) translateY(${(1 - hud.reveal) * 20}px)`,
        opacity: hud.reveal,
        ...capsule(theme, hud.level(frame), 20 * s),
        padding: `${heard ? pad * 0.9 : 0}px ${pad}px 0`,
      }}
    >
      {heard && <Draft theme={theme} hud={hud} size={14 * s} wrap={hud.wrap} />}
      <VoiceRow theme={theme} hud={hud} frame={frame} s={s} width={width - pad * 2 - 27 * s} points={heard ? 54 : 30} />
    </div>
  );
};

/** The notch: a black shape hanging from the top edge, with fillets into it. */
const Notch: React.FC<{ theme: OmarchyTheme; hud: HudState; frame: number }> = ({ theme, hud, frame }) => {
  const s = hud.scale ?? 1.5;
  const heard = (hud.words ?? []).some((word) => word.t > 0);
  const width = mix(185, heard ? 400 * s : 230 * s, hud.reveal);
  const fillet = 12;
  const pad = 16 * s;
  return (
    <div style={{ position: "absolute", top: 0, left: "50%", transform: "translateX(-50%)", width: width + fillet * 2 }}>
      <svg width={width + fillet * 2} height={fillet} style={{ position: "absolute", top: 0, left: 0 }}>
        <path d={`M0 0 Q${fillet} 0 ${fillet} ${fillet} L${fillet} 0 Z`} fill="#000" />
        <path d={`M${width + fillet * 2} 0 Q${width + fillet} 0 ${width + fillet} ${fillet} L${width + fillet} 0 Z`} fill="#000" />
      </svg>
      <div
        style={{
          marginLeft: fillet,
          width,
          background: "#000",
          borderRadius: `0 0 ${18 * s}px ${18 * s}px`,
          padding: `${4 * s}px ${pad}px ${heard ? 10 * s : 2 * s}px`,
          boxShadow: `0 18px 40px rgba(0,0,0,0.45), 0 0 ${40 * hud.level(frame)}px ${tint(theme.accent, 0.3)}`,
          opacity: Math.min(1, 0.4 + hud.reveal),
          overflow: "hidden",
        }}
      >
        <div style={{ opacity: hud.reveal }}>
          <VoiceRow theme={theme} hud={hud} frame={frame} s={s} width={width - pad * 2 - 27 * s} points={40} />
          {heard && <Draft theme={theme} hud={hud} size={14 * s} wrap={hud.wrap} />}
        </div>
      </div>
    </div>
  );
};

/** A frame of `width` round an element's edge: everything but its content box. */
const outside = (width: number): React.CSSProperties => ({
  padding: width,
  boxSizing: "border-box",
  WebkitMask: "linear-gradient(#000 0 0) content-box, linear-gradient(#000 0 0)",
  WebkitMaskComposite: "xor",
  mask: "linear-gradient(#000 0 0) content-box exclude, linear-gradient(#000 0 0)",
});

/**
 * The halo: Edge Glow just outside the target window's border. Like the
 * plugin's, it is drawn over everything else and never over the window it
 * marks, so its light falls on the neighbours.
 */
const Halo: React.FC<{
  theme: OmarchyTheme;
  rect: { x: number; y: number; w: number; h: number };
  reveal: number;
  level: number;
  frame: number;
  /** Drawn larger than life, for a small view of the desktop. */
  s?: number;
}> = ({ theme, rect, reveal, level, frame, s = 1 }) => {
  const spin = frame * 0.6;
  const ring = `conic-gradient(from ${spin}deg, ${theme.wall[0]}, ${theme.wall[1]}, ${theme.wall[2]}, ${theme.wall[0]})`;
  const room = 160 * s;
  const band = (thickness: number, blur: number, opacity: number) => (
    <div
      style={{
        position: "absolute",
        left: room - thickness,
        top: room - thickness,
        width: rect.w + thickness * 2,
        height: rect.h + thickness * 2,
        borderRadius: 10 + thickness,
        background: ring,
        filter: blur > 0 ? `blur(${blur}px)` : undefined,
        opacity,
        ...outside(thickness),
      }}
    />
  );
  return (
    <div
      style={{
        position: "absolute",
        left: rect.x - room,
        top: rect.y - room,
        width: rect.w + room * 2,
        height: rect.h + room * 2,
        ...outside(room),
        // Blooms from the bottom centre, as the plugin's does.
        clipPath: `inset(${(1 - reveal) * 100}% ${(1 - reveal) * 50}% 0 ${(1 - reveal) * 50}%)`,
      }}
    >
      {band((14 + level * 22) * s, (34 + level * 26) * s, 0.9)}
      {band((5 + level * 6) * s, (6 + level * 4) * s, 0.9)}
      {band(2.5 * s, 0, 1)}
    </div>
  );
};

/** The island: the bar's ghost widens into a black pill inside the bar. */
const Island: React.FC<{ theme: OmarchyTheme; reveal: number; level: (frame: number) => number; frame: number }> = ({
  theme,
  reveal,
  level,
  frame,
}) => {
  const right = DESKTOP_W - 14;
  const slot = 30;
  const width = mix(slot, 420, reveal);
  const now = level(frame);
  return (
    <div
      style={{
        position: "absolute",
        top: 3,
        left: right - width,
        width,
        height: BAR_H - 6,
        borderRadius: (BAR_H - 6) / 2,
        background: "#000",
        boxShadow: `0 0 0 1px ${tint(theme.accent, 0.3 + now * 0.5)}, 0 0 ${12 + now * 30}px ${tint(theme.accent, 0.55 * reveal)}`,
        display: "flex",
        alignItems: "center",
        gap: 14,
        padding: "0 12px",
        overflow: "hidden",
        boxSizing: "border-box",
      }}
    >
      <Ghost size={19} color={theme.accent} />
      <div style={{ opacity: reveal }}>
        <Waveform frame={frame} level={level} width={Math.max(10, width - 70)} height={26} strokeWidth={1.8} glow={2} points={46} colors={VOICE_STOPS(theme)} />
      </div>
    </div>
  );
};

export const Desktop: React.FC<{
  frame: number;
  theme: OmarchyTheme;
  hud: HudState;
  terminal: TerminalState;
  recording: boolean;
  /** Where the pointer sits, for the pointer placement. */
  pointer?: { x: number; y: number };
  /** What the windows show, when not the agent and neovim. */
  left?: (theme: OmarchyTheme) => React.ReactNode;
  right?: (theme: OmarchyTheme) => React.ReactNode;
}> = ({ frame, theme, hud, terminal, recording, pointer = { x: 1130, y: 470 }, left, right }) => {
  const island = hud.placement === "island" ? hud.reveal : 0;
  const level = hud.level(frame);
  return (
    <div
      style={{
        position: "relative",
        width: DESKTOP_W,
        height: DESKTOP_H,
        borderRadius: 18,
        overflow: "hidden",
        background: theme.dark_background,
      }}
    >
      <Wallpaper theme={theme} frame={frame} />

      <div
        style={{
          position: "absolute",
          inset: "0 0 auto 0",
          height: BAR_H,
          display: "flex",
          alignItems: "center",
          padding: "0 20px",
          fontFamily: FONT.mono,
          fontSize: 16,
          color: theme.foreground,
          background: tint(theme.background, 0.88),
        }}
      >
        <div style={{ display: "flex", gap: 16, flex: 1 }}>
          {["1", "2", "3", "4", "5"].map((n) => (
            <span key={n} style={{ color: n === "1" ? theme.accent : tint(theme.foreground, 0.4) }}>
              {n}
            </span>
          ))}
        </div>
        <div>Thursday 14:20</div>
        <div style={{ display: "flex", alignItems: "center", gap: 18, flex: 1, justifyContent: "flex-end" }}>
          {[0, 1, 2].map((index) => (
            <div key={index} style={{ width: 14, height: 14, borderRadius: 4, border: `2px solid ${tint(theme.foreground, 0.5)}` }} />
          ))}
          <div style={{ opacity: island > 0.02 ? 0 : 1 }}>
            <Ghost
              size={19}
              color={recording ? theme.accent : theme.foreground}
              style={{ opacity: recording ? 0.55 + 0.45 * Math.abs(Math.sin(frame / 15)) : 0.9 }}
            />
          </div>
        </div>
      </div>

      {island > 0.02 && <Island theme={theme} reveal={island} level={hud.level} frame={frame} />}

      <Frosted rect={WINDOWS.left} theme={theme} active>
        {left ? left(theme) : <Terminal theme={theme} state={terminal} frame={frame} />}
      </Frosted>
      <Frosted rect={WINDOWS.right} theme={theme} active={false}>
        {right ? right(theme) : <Neovim theme={theme} />}
      </Frosted>

      {hud.placement === "halo" && hud.reveal > 0 && (
        <Halo theme={theme} rect={WINDOWS.left} reveal={hud.reveal} level={level} frame={frame} s={(hud.scale ?? 1.5) / 1.5} />
      )}
      {hud.placement === "pill" && hud.reveal > 0 && <Pill theme={theme} hud={hud} frame={frame} />}
      {hud.placement === "caption" && hud.reveal > 0 && <Caption theme={theme} hud={hud} frame={frame} rect={WINDOWS.left} />}
      {hud.placement === "notch" && <Notch theme={theme} hud={hud} frame={frame} />}

      {hud.placement === "pointer" && hud.reveal > 0 && (
        <div style={{ position: "absolute", left: pointer.x, top: pointer.y }}>
          <svg width={30} height={38} style={{ position: "absolute", left: -2, top: -2, overflow: "visible" }}>
            <path
              d="M2 2 L2 29 L9 22.5 L14 34 L19 32 L14 21 L23 21 Z"
              fill={theme.bright_foreground}
              stroke="#000"
              strokeWidth={1.8}
              strokeLinejoin="round"
            />
          </svg>
          <div
            style={{
              position: "absolute",
              left: 26,
              top: 32,
              width: 68,
              height: 68,
              borderRadius: 34,
              background: "#000",
              display: "grid",
              placeItems: "center",
              opacity: Math.min(1, hud.reveal * 2),
              boxShadow: `0 0 0 ${3 + level * 5}px ${tint(theme.accent, 0.95)}, 0 0 ${24 + level * 40}px ${tint(theme.magenta, 0.7)}`,
              transform: `scale(${mix(0.3, 1, hud.reveal) * (1 + level * 0.12)})`,
              transformOrigin: "0 0",
            }}
          >
            <Ghost size={30} color={theme.bright_foreground} />
          </div>
        </div>
      )}
    </div>
  );
};
