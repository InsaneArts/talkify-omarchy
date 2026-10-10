#!/usr/bin/env bash
# Compiles every HUD shader source to the .qsb Qt Quick loads at runtime,
# next to its source (housing.frag -> housing.frag.qsb). `--qt6` bakes every
# target the RHI may pick (SPIR-V, GLSL, HLSL, MSL), so the HUD draws on
# whichever backend the shell ends up with.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
qsb="${QSB:-/usr/lib/qt6/bin/qsb}"

if [[ ! -x "$qsb" ]]; then
  echo "build.sh: qsb not found at $qsb (install qt6-shadertools or set QSB)" >&2
  exit 1
fi

shopt -s nullglob
sources=("$here"/*.frag "$here"/*.vert)
if (( ${#sources[@]} == 0 )); then
  echo "build.sh: no shader sources in $here" >&2
  exit 1
fi

for source in "${sources[@]}"; do
  if ! "$qsb" --qt6 -o "$source.qsb" "$source"; then
    echo "build.sh: $(basename "$source") failed to compile" >&2
    exit 1
  fi
  echo "built $(basename "$source").qsb"
done
