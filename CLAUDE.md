# Talkify for Omarchy

Talkify's Direct Dictation for Omarchy (Hyprland, Quickshell). Linux and
Omarchy only; no other platform is a goal.

Read [`CONTEXT.md`](CONTEXT.md) first. Its terminology is binding: Direct
Dictation, Dictation Trigger, Chord guard, Latched session, Live draft, Speech
Model, HUD, Insertion destination. Use those words in code, comments and
commits.

The macOS app at `../Talkify` is the spec for behaviour and look. When a rule
here differs from it, the difference is deliberate and says why in a comment.

## Rules

- Two spaces for indentation, in Rust (rustfmt.toml) and QML alike.
- No section-marker comments (`// MARK:`, `// ----`). A file that needs them
  needs splitting.
- Rules that can be pinned without a microphone or a window go in
  `crates/talkify-core`, with tests. When a bug lives in impure code, move the
  rule into a pure type and test that rather than mocking the world.
- The daemon's loop owns all session state. Threads report back as `Msg`s and
  carry the session id; never share session state across threads.
- One third-party model runtime: `parakeet-rs` (ONNX Runtime via `ort`).
  Adding a second speech engine is a decision to raise, not to make.
- Never edit `/usr/share/omarchy`. User config changes (Hyprland binds, the
  Omarchy menu) are documented in the README, not done by `install.sh`.

## Build and test

```sh
cargo test                      # must pass
cargo build --release
./install.sh                    # installs and restarts talkify.service
quickshell -p plugin/dev        # HUD preview with scripted sessions
```

`AGENTS.md` is a symlink to this file.
