#!/usr/bin/env bash
# Renders the README's pictures into ../.github/assets: the cover and one
# picture per feature as JPEGs, and GitHub's social preview, the cover at
# 1280×640 as a PNG, to upload in the repository's settings.
set -euo pipefail
cd "$(dirname "$0")/.."
out=../.github/assets
stills=out/readme
mkdir -p "$out" "$stills"
npx remotion bundle src/index.ts --out-dir out/bundle >/dev/null
npx remotion still out/bundle Cover "$stills/cover.png" >/dev/null
npx remotion still out/bundle Cover "$out/social-preview.png" --scale=0.6667 >/dev/null
names=(appearance vocabulary insights app-rules)
for i in "${!names[@]}"; do
  npx remotion still out/bundle Features "$stills/feature-${names[$i]}.png" --frame="$i" >/dev/null
done
# Smooth gradients make large PNGs; a JPEG at this quality, without chroma
# subsampling, looks the same at a tenth of the size.
for still in "$stills"/*.png; do
  magick "$still" -quality 90 -sampling-factor 4:4:4 "$out/$(basename "${still%.png}").jpg"
done
ls -1 "$out"/cover.jpg "$out"/feature-*.jpg "$out"/social-preview.png
