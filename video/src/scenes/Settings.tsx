import React from "react";
import { AbsoluteFill, Img, spring, staticFile } from "remotion";
import { C, EASE, FONT, FPS, mix, progress } from "../brand";
import { DESKTOP_H, DESKTOP_W, Desktop } from "../Desktop";
import { arrive, leave as leaveFx } from "../fx";
import { themeAt } from "../themeline";
import { AT } from "../timeline";
import { LEAVE as PLACES_LEAVE } from "./Places";

// 32.4–38.4 s. A click on the ghost in the bar opens the settings, and three
// pages go by on the beat, each in another theme: Insights, Vocabulary, App
// rules. Then all three fan out together. Real screenshots of the plugin.

const BEAT = 36;
const PAGES = [
  {
    src: "settings/insights.png",
    id: "ristretto",
    title: "Insights",
    sub: "Watch your words add up, in your theme's colours.",
    at: AT.settings,
  },
  {
    src: "settings/vocabulary.png",
    id: "gruvbox",
    title: "Vocabulary",
    sub: "Teach it the names and words you use.",
    at: AT.settings + BEAT * 2,
  },
  {
    src: "settings/apps.png",
    id: "rose-pine",
    title: "App rules",
    sub: "In a terminal, “send it” presses Enter.",
    at: AT.settings + BEAT * 4,
  },
];
const FAN = AT.settings + BEAT * 6;
const OUT = AT.fun - 18;
/** Where the bar's ghost is on screen as the desktop leaves (Places). */
const GHOST = { x: 1560, y: 112 };

const PANEL_H = 760;
const PANEL_W = (1189 / 991) * PANEL_H;
const voice = () => 0.4;

export const Settings: React.FC<{ frame: number }> = ({ frame }) => {
  const now = themeAt(frame, PAGES, 10);
  const open = spring({ frame: frame - (PLACES_LEAVE + 6), fps: FPS, config: { damping: 16, stiffness: 120, mass: 0.9 } });
  const backdrop = progress(frame, PLACES_LEAVE + 6, 30, EASE.out);
  const fan = spring({ frame: frame - FAN, fps: FPS, config: { damping: 17, stiffness: 110, mass: 0.9 } });
  const out = progress(frame, OUT, 22, EASE.in);
  const dark = progress(frame, FAN, 24, EASE.inOut);

  return (
    <AbsoluteFill style={{ opacity: 1 - out }}>
      <AbsoluteFill style={{ opacity: backdrop * (1 - dark) }}>
        <div
          style={{
            position: "absolute",
            left: 960 - (DESKTOP_W * 1.23) / 2,
            top: 540 - (DESKTOP_H * 1.23) / 2,
            width: DESKTOP_W,
            height: DESKTOP_H,
            transform: "scale(1.23)",
            transformOrigin: "0 0",
            filter: "brightness(0.8)",
          }}
        >
          <Desktop
            frame={frame}
            theme={now.theme}
            recording={false}
            bare={1}
            hud={{ placement: "pill", reveal: 0, level: voice }}
            terminal={{ typed: "", sent: 1, lines: [1, 1, 1] }}
          />
        </div>
        <AbsoluteFill style={{ background: "linear-gradient(90deg, rgba(5,6,10,0) 40%, rgba(5,6,10,0.78) 70%)" }} />
      </AbsoluteFill>

      {PAGES.map((page, index) => {
        const shownAt = index === 0 ? PLACES_LEAVE + 6 : page.at;
        const arriving =
          index === 0 ? open : spring({ frame: frame - page.at, fps: FPS, config: { damping: 16, stiffness: 150, mass: 0.8 } });
        const next = PAGES[index + 1];
        const going = next ? progress(frame, next.at - 4, 16, EASE.in) : 0;
        if (frame < shownAt - 1) return null;

        // On its own: the left half of the screen, turned toward the words.
        const soloX = 700 + (index === 0 ? 0 : mix(220, 0, arriving)) - going * 260;
        const soloRotate = 12 + going * 20;
        const soloScale = index === 0 ? mix(0.12, 1, open) : 1;
        const soloOpacity = (index === 0 ? Math.min(1, open * 2) : Math.min(1, arriving * 1.6)) * (1 - going);
        const fromGhost = index === 0 ? 1 - open : 0;

        // In the fan: side by side, the middle one nearest.
        const fanX = 960 + (index - 1) * 560;
        const fanRotate = (1 - index) * 26;
        const fanScale = index === 1 ? 0.7 : 0.6;
        const x = mix(soloX, fanX, fan);
        const rotate = mix(soloRotate, fanRotate, fan);
        const scale = mix(soloScale, fanScale, fan);
        const opacity = fan > 0.01 ? Math.max(soloOpacity, fan) : soloOpacity;

        return (
          <div
            key={page.src}
            style={{
              position: "absolute",
              left: mix(x, GHOST.x, fromGhost) - PANEL_W / 2,
              top: mix(540 + mix(0, -40, fan), GHOST.y, fromGhost) - PANEL_H / 2,
              width: PANEL_W,
              height: PANEL_H,
              perspective: 2200,
              opacity,
              zIndex: index === 1 && fan > 0.5 ? 3 : index,
              filter: `blur(${going * 14 * (1 - fan) + out * 16}px)`,
            }}
          >
            <Img
              src={staticFile(page.src)}
              style={{
                width: "100%",
                height: "100%",
                transform: `rotateY(${rotate}deg) scale(${scale})`,
                transformOrigin: "50% 50%",
                borderRadius: 18,
                boxShadow: "0 50px 140px rgba(0,0,0,0.65), 0 0 0 1px rgba(255,255,255,0.08)",
              }}
            />
          </div>
        );
      })}

      {PAGES.map((page, index) => {
        const next = PAGES[index + 1];
        const start = index === 0 ? PLACES_LEAVE + 22 : page.at + 4;
        const end = next ? next.at - 6 : FAN - 4;
        const a = arrive(frame, start, 26, 30, 12);
        const l = leaveFx(frame, end, 12, 24, 10);
        if (frame < start - 1 || frame > end + 14) return null;
        return (
          <div
            key={page.title}
            style={{
              position: "absolute",
              left: 1240,
              top: 400,
              width: 600,
              opacity: a.opacity * l.opacity,
              transform: `translateY(${a.y + l.y}px)`,
              filter: `blur(${a.blur + l.blur}px)`,
            }}
          >
            <div
              style={{
                fontFamily: FONT.display,
                fontWeight: 600,
                fontSize: 108,
                letterSpacing: "-0.04em",
                lineHeight: 1,
                color: C.paper,
              }}
            >
              {page.title}
            </div>
            <div
              style={{
                marginTop: 26,
                fontFamily: FONT.display,
                fontWeight: 500,
                fontSize: 40,
                letterSpacing: "-0.015em",
                lineHeight: 1.25,
                color: C.mist,
              }}
            >
              {page.sub}
            </div>
          </div>
        );
      })}

      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          top: 900,
          textAlign: "center",
          fontFamily: FONT.display,
          fontWeight: 600,
          fontSize: 64,
          letterSpacing: "-0.03em",
          color: C.paper,
          ...(() => {
            const a = arrive(frame, FAN + 10, 28, 26, 12);
            return { opacity: a.opacity, transform: `translateY(${a.y}px)`, filter: `blur(${a.blur}px)` };
          })(),
        }}
      >
        Every setting, in your colours.
      </div>
    </AbsoluteFill>
  );
};
