#!/usr/bin/env bash
# Renders the README's stills into ../.github/assets as film-<name>.png.
# Pass --scale=2 for landing-page sizes.
set -euo pipefail
cd "$(dirname "$0")/.."
out=../.github/assets
mkdir -p "$out"
names=(hero live tidy vocabulary placements themes)
npx remotion bundle src/index.ts --out-dir out/bundle >/dev/null
for i in "${!names[@]}"; do
  npx remotion still out/bundle Shots "$out/film-${names[$i]}.png" --frame="$i" "$@" >/dev/null
  echo "$out/film-${names[$i]}.png"
done
