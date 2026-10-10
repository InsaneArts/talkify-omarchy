#!/usr/bin/env bash
# Builds Talkify and installs it for the current user: the daemon, its
# sounds, the Omarchy shell plugin, and the systemd user service. Safe to run
# again; it replaces what it installed before.
#
# From a clone it builds that clone. Piped from curl it has no source next to
# it, so it fetches the source into ~/.local/share/talkify/source (or updates
# it there) and runs the install.sh it finds in it:
#
#   curl -fsSL https://raw.githubusercontent.com/InsaneArts/talkify-omarchy/main/install.sh | bash
set -euo pipefail

# TALKIFY_SOURCE fetches from somewhere else, such as a fork.
source_url="${TALKIFY_SOURCE:-https://github.com/InsaneArts/talkify-omarchy.git}"
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"

if [[ ! -f "$here/Cargo.toml" || ! -f "$here/plugin/manifest.json" ]]; then
  source_dir="${XDG_DATA_HOME:-$HOME/.local/share}/talkify/source"
  command -v git >/dev/null || { echo "install.sh: git is needed to fetch Talkify" >&2; exit 1; }
  if [[ -d "$source_dir/.git" ]]; then
    echo "Updating the source in $source_dir"
    git -C "$source_dir" pull --ff-only --quiet
  else
    echo "Fetching the source into $source_dir"
    git clone --depth 1 --quiet "$source_url" "$source_dir"
  fi
  # Build artefacts belong in the cache, not beside the source in the data
  # folder, which they would grow by a couple of gigabytes.
  export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/talkify/target}"
  exec bash "$source_dir/install.sh" "$@"
fi

repo="$here"
data="${XDG_DATA_HOME:-$HOME/.local/share}/talkify"
units="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
target="${CARGO_TARGET_DIR:-$repo/target}"

# Rust builds the daemon and qsb compiles the HUD's shaders; Omarchy installs
# either when it is missing.
needs=()
command -v cargo >/dev/null || needs+=(rust)
[[ -x "${QSB:-/usr/lib/qt6/bin/qsb}" ]] || needs+=(qt6-shadertools)
if (( ${#needs[@]} > 0 )); then
  if command -v omarchy-pkg-add >/dev/null; then
    echo "Installing ${needs[*]}"
    omarchy-pkg-add "${needs[@]}"
  else
    echo "install.sh: needs ${needs[*]}; install them and run it again" >&2
    exit 1
  fi
fi

echo "Building the daemon"
cargo build --release --locked --manifest-path "$repo/Cargo.toml" -p talkify

echo "Installing ~/.local/bin/talkify"
install -Dm755 "$target/release/talkify" "$HOME/.local/bin/talkify"
install -d "$data/sounds"
install -m644 "$repo"/sounds/*.wav "$data/sounds/"

echo "Compiling the HUD shaders"
"$repo/plugin/shaders/build.sh" >/dev/null

install -Dm644 "$repo/systemd/talkify.service" "$units/talkify.service"

"$repo/packaging/talkify-setup" "$repo/plugin"
