import React from "react";
import { AbsoluteFill, Sequence } from "remotion";
import { C } from "./brand";
import { Film } from "./Film";

// 3–5 second slices of the film for posts, one idea each, with the camera
// closer where a phone would make the detail too small. `npm run clips`
// renders them into out/x.

export type ClipProps = {
  /** The film's frame the clip starts on. */
  start: number;
  zoom?: number;
  /** The film's point the clip centres on when zoomed. */
  focus?: [number, number];
};

export const CLIPS: ({ name: string; frames: number } & ClipProps)[] = [
  { name: "1-hold-speak-let-go", start: 280, frames: 265 },
  { name: "2-words-land-as-you-speak", start: 650, frames: 300, zoom: 1.55, focus: [750, 640] },
  { name: "3-follows-your-theme", start: 1380, frames: 300 },
  { name: "4-six-places", start: 1752, frames: 240 },
  { name: "5-settings", start: 2010, frames: 290 },
  { name: "6-dictation-should-be-fun", start: 2300, frames: 300 },
];

export const Clip: React.FC<ClipProps> = ({ start, zoom = 1, focus = [960, 540] }) => (
  <AbsoluteFill style={{ background: C.ink, overflow: "hidden" }}>
    <AbsoluteFill
      style={{
        transform: `translate(${960 - focus[0] * zoom}px, ${540 - focus[1] * zoom}px) scale(${zoom})`,
        transformOrigin: "0 0",
      }}
    >
      <Sequence from={-start}>
        <Film />
      </Sequence>
    </AbsoluteFill>
  </AbsoluteFill>
);
