#!/usr/bin/env bash
# Plays every HUD reaction in every placement and counts the frames rendered
# in each quiet window after the HUD has retracted. Every window must count
# zero: once the shape has gone, nothing on the HUD surfaces animates.
#
#   plugin/dev/quiet.sh            # all placements
#   HUD_QUIET_LOG=/tmp/q.log plugin/dev/quiet.sh
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log="${HUD_QUIET_LOG:-$(mktemp)}"
HUD_TOUR=quiet QSG_RENDER_TIMING=1 timeout 900 quickshell -p "$here" --log-times --no-color \
  --log-rules "qt.scenegraph.time.renderloop.debug=true" >"$log" 2>&1 || true
awk '
  /quiet: start/ { quiet = 1; name = $0; sub(/.*quiet: start /, "", name); frames = 0; next }
  /quiet: end/ { if (quiet) { printf "%-22s %d frames\n", name, frames; if (frames > 0) bad++ }; quiet = 0; next }
  quiet && /frame rendered/ { frames++ }
  END { if (bad) { print bad " quiet windows rendered frames"; exit 1 } else print "all quiet" }
' "$log"
