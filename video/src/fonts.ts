import { continueRender, delayRender, staticFile } from "remotion";

// Fonts ship with the film, so a render looks the same on any machine.
const faces: [string, string, string][] = [
  ["Inter Display", "fonts/InterDisplay-Medium.woff2", "500"],
  ["Inter Display", "fonts/InterDisplay-SemiBold.woff2", "600"],
  ["Inter Display", "fonts/InterDisplay-Bold.woff2", "700"],
  ["Inter", "fonts/Inter-Regular.woff2", "400"],
  ["Inter", "fonts/Inter-Medium.woff2", "500"],
  ["JetBrains Mono", "fonts/JetBrainsMono-Regular.ttf", "400"],
];

let loaded = false;

export const loadFonts = () => {
  if (loaded) return;
  loaded = true;
  const handle = delayRender("fonts");
  Promise.all(
    faces.map(([family, file, weight]) => {
      const face = new FontFace(family, `url(${staticFile(file)})`, { weight });
      document.fonts.add(face);
      return face.load();
    }),
  )
    .then(() => continueRender(handle))
    .catch((error) => {
      console.error(error);
      continueRender(handle);
    });
};
