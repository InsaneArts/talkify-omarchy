import { EASE, progress } from "./brand";
import { blendTheme } from "./Desktop";
import { OmarchyTheme, THEMES } from "./themes";

export const theme = (id: string): OmarchyTheme => {
  const found = THEMES.find((t) => t.id === id);
  if (!found) throw new Error(`no theme ${id}`);
  return found;
};

/** Whether a theme is a light one, by its background's luminance. */
export const isLight = (t: OmarchyTheme) => {
  const [r, g, b] = [1, 3, 5].map((i) => parseInt(t.background.slice(i, i + 2), 16) / 255);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.5;
};

export type Step = { id: string; at: number };

/** The step in force at `frame`, its predecessor, and the theme between them. */
export const themeAt = (frame: number, steps: Step[], blend = 8) => {
  let index = 0;
  for (let i = 0; i < steps.length; i++) if (frame >= steps[i].at) index = i;
  const current = theme(steps[index].id);
  const previous = index > 0 ? theme(steps[index - 1].id) : undefined;
  const t = previous ? progress(frame, steps[index].at, blend, EASE.inOut) : 1;
  return {
    index,
    step: steps[index],
    previousStep: index > 0 ? steps[index - 1] : undefined,
    theme: previous ? blendTheme(previous, current, t) : current,
    light: isLight(t > 0.5 || !previous ? current : previous),
  };
};
