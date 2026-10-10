import React from "react";
import { Composition } from "remotion";
import { FPS, HEIGHT, WIDTH } from "./brand";
import { Film } from "./Film";
import { Shots, SHOTS } from "./Shots";

export const Root: React.FC = () => (
  <>
    <Composition id="Film" component={Film} durationInFrames={FPS * 30} fps={FPS} width={WIDTH} height={HEIGHT} />
    <Composition id="Shots" component={Shots} durationInFrames={SHOTS.length} fps={FPS} width={WIDTH} height={HEIGHT} />
  </>
);
