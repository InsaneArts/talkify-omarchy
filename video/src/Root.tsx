import React from "react";
import { Composition } from "remotion";
import { FPS, HEIGHT, WIDTH } from "./brand";
import { Clip, CLIPS } from "./Clips";
import { Film } from "./Film";
import { FEATURES, Features } from "./Readme";
import { DURATION } from "./timeline";
import { Shots, SHOTS } from "./Shots";

export const Root: React.FC = () => (
  <>
    <Composition id="Film" component={Film} durationInFrames={DURATION} fps={FPS} width={WIDTH} height={HEIGHT} />
    <Composition id="Shots" component={Shots} durationInFrames={SHOTS.length} fps={FPS} width={WIDTH} height={HEIGHT} />
    {CLIPS.map(({ name, frames, ...props }) => (
      <Composition
        key={name}
        id={`Clip-${name}`}
        component={Clip}
        durationInFrames={frames}
        fps={FPS}
        width={WIDTH}
        height={HEIGHT}
        defaultProps={props}
      />
    ))}
    <Composition id="Features" component={Features} durationInFrames={FEATURES.length} fps={FPS} width={WIDTH} height={HEIGHT} />
  </>
);
