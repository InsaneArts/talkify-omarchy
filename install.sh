#!/usr/bin/env bash
# Builds Talkify and installs it for the current user: the daemon, its
# sounds, the Omarchy shell plugin, and the systemd user service. Safe to run
# again after a pull; it replaces what it installed before.
set -euo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
plugin_id="tornikegomareli.talkify"
data="${XDG_DATA_HOME:-$HOME/.local/share}/talkify"
plugins="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins"
units="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

echo "Building the daemon"
cargo build --release --manifest-path "$repo/Cargo.toml" -p talkify

echo "Installing ~/.local/bin/talkify"
install -Dm755 "$repo/target/release/talkify" "$HOME/.local/bin/talkify"
install -d "$data/sounds"
install -m644 "$repo"/sounds/*.wav "$data/sounds/"

if [[ -x "$repo/plugin/shaders/build.sh" ]]; then
  echo "Compiling the HUD shaders"
  "$repo/plugin/shaders/build.sh"
fi

# A copy, not a link: the shell's plugin watcher does not follow a symlink,
# so a linked plugin never hot-reloads. The dev preview stays behind; its
# links into the Omarchy shell source are for `quickshell -p plugin/dev`.
echo "Copying the shell plugin into $plugins"
install -d "$plugins"
[[ -L "$plugins/$plugin_id" ]] && rm "$plugins/$plugin_id"
plugin_changes=$(rsync -a --delete --itemize-changes --exclude dev/ "$repo/plugin/" "$plugins/$plugin_id/")

echo "Starting talkify.service"
install -Dm644 "$repo/systemd/talkify.service" "$units/talkify.service"
systemctl --user daemon-reload
systemctl --user enable talkify.service >/dev/null 2>&1
systemctl --user restart talkify.service

if command -v omarchy-shell >/dev/null; then
  # The shell hot-reloads the HUD, but keeps the bar widget, the settings
  # page and the service it already loaded until it restarts.
  if [[ -n "$plugin_changes" ]] && omarchy-shell shell ping >/dev/null 2>&1; then
    echo "Restarting the Omarchy shell to load the new plugin"
    omarchy restart shell >/dev/null 2>&1 || true
  fi
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  if ! grep -q "\"$plugin_id\"" "${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/shell.json" 2>/dev/null; then
    omarchy plugin enable "$plugin_id" >/dev/null 2>&1 || true
  fi
fi

cat <<'NEXT'

Talkify is installed. The first start downloads the Speech Model (670 MB);
the ghost in the bar fills up while it does.

To hold the trigger to talk, Talkify reads the keyboard, which needs the
input group (then log out and back in):

  sudo usermod -aG input "$USER"

Until then, and as a fallback, bind a tap of the trigger in
~/.config/hypr/bindings.lua:

  o.bind("SUPER + Super_R", "Dictation (Talkify)", "talkify tap", { release = true })
NEXT
