import { FPS } from "./brand";

// Where each part of the film starts, in frames. The first four parts are
// placed by their own scenes; from here on every part starts on a bar.

export const AT = {
  /** The pill in the middle while the theme changes on the beat. */
  theme: 1296,
  /** Every placement, a beat each. */
  places: 1728,
  /** Insights, Vocabulary, App rules. */
  settings: 2016,
  /** Using a computer should be fun. */
  fun: 2304,
  /** Talkify. Now for Omarchy. */
  end: 2520,
};

export const DURATION = Math.round(FPS * 45.6);
