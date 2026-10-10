#!/usr/bin/env bash
# Renders the README's pictures into ../.github/assets: the hero, a frame of
# the film, and one picture per feature, as JPEGs; and GitHub's social
# preview, the hero at 1280×640 as a PNG, to upload in the repository's
# settings.
set -euo pipefail
cd "$(dirname "$0")/.."
out=../.github/assets
stills=out/readme
# The pill in Tokyo Night, saying it follows the Omarchy theme.
hero_frame=1340
mkdir -p "$out" "$stills"
npx remotion bundle src/index.ts --out-dir out/bundle >/dev/null
npx remotion still out/bundle Film "$stills/hero.png" --frame="$hero_frame" --props='{"grain":false}' >/dev/null
names=(appearance vocabulary insights app-rules)
for i in "${!names[@]}"; do
  npx remotion still out/bundle Features "$stills/feature-${names[$i]}.png" --frame="$i" >/dev/null
done
# Smooth gradients make large PNGs; a JPEG at this quality, without chroma
# subsampling, looks the same at a tenth of the size.
for still in "$stills"/*.png; do
  magick "$still" -quality 90 -sampling-factor 4:4:4 "$out/$(basename "${still%.png}").jpg"
done
magick "$stills/hero.png" -gravity center -crop 1920x960+0+0 +repage -resize 1280x640 "$out/social-preview.png"
ls -1 "$out"/hero.jpg "$out"/feature-*.jpg "$out"/social-preview.png
