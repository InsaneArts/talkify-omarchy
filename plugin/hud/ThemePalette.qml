import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "ThemeColors.js" as ThemeColors

// The current Omarchy theme's colours, read from its colors.toml and kept
// current: the file is watched, and because `omarchy theme set` may replace
// it rather than rewrite it (which a watch can miss), it is also re-read
// whenever the shell's own colours change, which is how a theme switch
// reaches the shell. `look` is ThemeColors.derive() of what it read.
Item {
  id: palette

  // The theme to read; the harness points this at a stock theme.
  property string path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
  // Whether the shell's colours changing should trigger a re-read; off for a
  // pinned file that is not the current theme.
  property bool followShell: true

  property var raw: ({})
  readonly property var fallback: ({
    foreground: [Color.foreground.r, Color.foreground.g, Color.foreground.b, 1],
    background: [Color.background.r, Color.background.g, Color.background.b, 1],
    accent: [Color.accent.r, Color.accent.g, Color.accent.b, 1]
  })
  readonly property var look: ThemeColors.derive(raw, fallback)
  // Talkify's own colours, with the shell's foreground for the hairline as
  // before.
  readonly property var talkifyLook: ThemeColors.talkify(fallback.foreground)

  FileView {
    id: file
    path: palette.path
    watchChanges: true
    printErrors: false
    // `text()` is stale in the change signal itself, so a change goes through
    // reload to the loaded signal.
    onFileChanged: reload()
    onLoaded: palette.raw = ThemeColors.parseToml(text())
    onLoadFailed: palette.raw = ({})
  }

  Connections {
    target: palette.followShell ? Color : null
    ignoreUnknownSignals: true
    function onAccentChanged() { reread.restart() }
    function onForegroundChanged() { reread.restart() }
    function onBackgroundChanged() { reread.restart() }
  }

  // The three colours change one after another; read once they settle.
  Timer {
    id: reread
    interval: 60
    onTriggered: file.reload()
  }
}
