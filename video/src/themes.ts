// Stock Omarchy themes, read from /usr/share/omarchy/themes/*/colors.toml.

export type OmarchyTheme = {
  id: string;
  name: string;
  background: string;
  dark_background: string;
  lighter_background: string;
  foreground: string;
  bright_foreground: string;
  muted: string;
  accent: string;
  red: string;
  yellow: string;
  green: string;
  cyan: string;
  blue: string;
  magenta: string;
  /** The wallpaper's three lights, picked to read as the theme at a glance. */
  wall: [string, string, string];
};

export const THEMES: OmarchyTheme[] = [
  {
    id: "tokyo-night",
    name: "Tokyo Night",
    background: "#1a1b26",
    dark_background: "#13141c",
    lighter_background: "#24283b",
    foreground: "#a9b1d6",
    bright_foreground: "#c0caf5",
    muted: "#414868",
    accent: "#7aa2f7",
    red: "#f7768e",
    yellow: "#e0af68",
    green: "#9ece6a",
    cyan: "#449dab",
    blue: "#7aa2f7",
    magenta: "#ad8ee6",
    wall: ["#7aa2f7", "#bb9af7", "#7dcfff"],
  },
  {
    id: "catppuccin",
    name: "Catppuccin",
    background: "#1e1e2e",
    dark_background: "#161622",
    lighter_background: "#313244",
    foreground: "#cdd6f4",
    bright_foreground: "#cdd6f4",
    muted: "#585b70",
    accent: "#89b4fa",
    red: "#f38ba8",
    yellow: "#f9e2af",
    green: "#a6e3a1",
    cyan: "#94e2d5",
    blue: "#89b4fa",
    magenta: "#f5c2e7",
    wall: ["#cba6f7", "#f5c2e7", "#89b4fa"],
  },
  {
    id: "gruvbox",
    name: "Gruvbox",
    background: "#282828",
    dark_background: "#1e1e1e",
    lighter_background: "#3c3836",
    foreground: "#d4be98",
    bright_foreground: "#d4be98",
    muted: "#665c54",
    accent: "#7daea3",
    red: "#ea6962",
    yellow: "#d8a657",
    green: "#a9b665",
    cyan: "#89b482",
    blue: "#7daea3",
    magenta: "#d3869b",
    wall: ["#d8a657", "#ea6962", "#7daea3"],
  },
  {
    id: "kanagawa",
    name: "Kanagawa",
    background: "#1f1f28",
    dark_background: "#17171e",
    lighter_background: "#223249",
    foreground: "#dcd7ba",
    bright_foreground: "#dcd7ba",
    muted: "#54546D",
    accent: "#dcd7ba",
    red: "#c34043",
    yellow: "#c0a36e",
    green: "#76946a",
    cyan: "#6a9589",
    blue: "#7e9cd8",
    magenta: "#957fb8",
    wall: ["#7e9cd8", "#957fb8", "#c0a36e"],
  },
  {
    id: "osaka-jade",
    name: "Osaka Jade",
    background: "#111c18",
    dark_background: "#0c1512",
    lighter_background: "#23372B",
    foreground: "#C1C497",
    bright_foreground: "#F7E8B2",
    muted: "#53685B",
    accent: "#509475",
    red: "#FF5345",
    yellow: "#459451",
    green: "#549e6a",
    cyan: "#2DD5B7",
    blue: "#509475",
    magenta: "#D2689C",
    wall: ["#549e6a", "#2dd5b7", "#d2689c"],
  },
];
