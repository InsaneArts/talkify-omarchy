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
# either when it is missing. On x86_64 machines whose CPU lacks AVX (such as
# Intel Pentium Gold or Celeron), the prebuilt static ONNX Runtime downloaded
# by ort-sys will crash with SIGILL. Use baseline onnxruntime-cpu instead.
has_avx() {
  [[ "$(uname -m)" != "x86_64" ]] || grep -qw avx /proc/cpuinfo 2>/dev/null
}

needs=()
command -v cargo >/dev/null || needs+=(rust)
[[ -x "${QSB:-/usr/lib/qt6/bin/qsb}" ]] || needs+=(qt6-shadertools)
if ! has_avx; then
  if [[ ! -f /usr/lib/libonnxruntime.so && ! -f "$data/lib/libonnxruntime.so" ]]; then
    needs+=(onnxruntime-cpu)
  fi
fi

if (( ${#needs[@]} > 0 )); then
  if command -v omarchy-pkg-add >/dev/null; then
    echo "Installing ${needs[*]}"
    omarchy-pkg-add "${needs[@]}"
  else
    echo "install.sh: needs ${needs[*]}; install them and run it again" >&2
    exit 1
  fi
fi

if ! has_avx; then
  if [[ -f /usr/lib/libonnxruntime.so ]]; then
    export ORT_LIB_LOCATION=/usr/lib
    export ORT_PREFER_DYNAMIC_LINK=1
    export RUSTFLAGS="${RUSTFLAGS:-} -C link-arg=-Wl,-rpath,/usr/lib"
  elif [[ -f "$data/lib/libonnxruntime.so" ]]; then
    export ORT_LIB_LOCATION="$data/lib"
    export ORT_PREFER_DYNAMIC_LINK=1
    export RUSTFLAGS="${RUSTFLAGS:-} -C link-arg=-Wl,-rpath,$data/lib"
  else
    mkdir -p "$data/lib"
    if command -v pacman >/dev/null; then
      echo "Fetching baseline ONNX Runtime for CPU without AVX..."
      for pkg_url in $(pacman -Sp onnxruntime-cpu 2>/dev/null || true); do
        curl -fsSL "$pkg_url" | tar -I zstd -xf - -C "$data/lib" --strip-components=2 --wildcards 'usr/lib/libonnxruntime.so*' 'usr/lib/libcpuinfo.so*' 2>/dev/null || true
      done
      if [[ -f "$data/lib/libonnxruntime.so.1" ]]; then
        [[ -f "$data/lib/libonnxruntime.so" ]] || ln -sf libonnxruntime.so.1 "$data/lib/libonnxruntime.so"
        export ORT_LIB_LOCATION="$data/lib"
        export ORT_PREFER_DYNAMIC_LINK=1
        export RUSTFLAGS="${RUSTFLAGS:-} -C link-arg=-Wl,-rpath,$data/lib"
      fi
    fi
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
