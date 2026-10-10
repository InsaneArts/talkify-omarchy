import React from "react";
import { Composition } from "remotion";
import { FPS, HEIGHT, WIDTH } from "./brand";
import { Film } from "./Film";
import { Cover, FEATURES, Features } from "./Readme";
import { DURATION } from "./timeline";
import { Shots, SHOTS } from "./Shots";

export const Root: React.FC = () => (
  <>
    <Composition id="Film" component={Film} durationInFrames={DURATION} fps={FPS} width={WIDTH} height={HEIGHT} />
    <Composition id="Shots" component={Shots} durationInFrames={SHOTS.length} fps={FPS} width={WIDTH} height={HEIGHT} />
    <Composition id="Cover" component={Cover} durationInFrames={1} fps={FPS} width={1920} height={960} />
    <Composition id="Features" component={Features} durationInFrames={FEATURES.length} fps={FPS} width={WIDTH} height={HEIGHT} />
  </>
);
