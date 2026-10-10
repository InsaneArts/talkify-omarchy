#!/usr/bin/env bash
# Renders the post clips into out/x: 3–5 second slices of the film, with the
# sound eased in and out so they start and loop without a click.
#
#   npm run clips                         every clip
#   npm run clips -- 2-words-land-as-you-speak   only that one
set -euo pipefail
cd "$(dirname "$0")/.."
out=out/x
mkdir -p "$out"
npx remotion bundle src/index.ts --out-dir out/bundle >/dev/null
for id in $(npx remotion compositions out/bundle --quiet 2>/dev/null | tr ' ' '\n' | grep '^Clip-'); do
  name="${id#Clip-}"
  if (( $# > 0 )) && [[ " $* " != *" $name "* ]]; then
    continue
  fi
  npx remotion render out/bundle "$id" "$out/.raw-$name.mp4" --codec h264 --crf 16 --pixel-format yuv420p \
    --audio-codec aac --audio-bitrate 256k >/dev/null
  length=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$out/.raw-$name.mp4")
  ffmpeg -loglevel error -y -i "$out/.raw-$name.mp4" -c:v copy \
    -af "afade=t=in:d=0.12,afade=t=out:st=$(awk -v l="$length" 'BEGIN { print l - 0.25 }'):d=0.25" \
    -c:a aac -b:a 256k -movflags +faststart "$out/$name.mp4"
  rm "$out/.raw-$name.mp4"
  echo "$out/$name.mp4"
done
