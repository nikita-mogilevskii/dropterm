<div align="center">

<img src="docs/assets/icon.png" width="128" alt="DropTerm icon">

# DropTerm

**A real terminal, one keystroke away — in your macOS menu bar.**

![macOS 26+](https://img.shields.io/badge/macOS-26%2B-blue)
![Swift 6](https://img.shields.io/badge/Swift-6-orange)
![License: MIT](https://img.shields.io/badge/License-MIT-green)
[![Release](https://img.shields.io/github/v/release/nikita-mogilevskii/dropterm)](https://github.com/nikita-mogilevskii/dropterm/releases/latest)

</div>

---

Click one key, get your shell. Click away, the session keeps running. Switch back anytime — the prompt's waiting.

```
Ctrl+I     Terminal appears   click away     runs in background     Ctrl+I     back again
```

## Features

- **Persistent sessions** — tmux-backed when installed (survive even app restarts), plain login shell otherwise
- **Multiple terminals** — up to 4 tiles in one panel, evenly split (1 full, 2/3 equal columns, 4 as a 2x2 grid); each tile is its own independent session
- **Ctrl+I global toggle** — hide/show from anywhere, even fullscreen apps
- **Exit = tile closes (or resets)** — `exit`/Ctrl+D inside the shell ends that tile; on the last remaining tile it respawns a fresh shell with a subtle crossfade instead
- **Spotlight-style fixed panel** — fixed 700pt width, horizontally centered, half the screen's height
- **No Dock icon** — pure menu bar, zero visual clutter
- **Settings panel**
  - Font: choose from system fonts or load custom `.ttf`/`.otf` files
  - Custom shell command — run zsh, bash, fish, nu, or other interpreters
  - Background style: Color (with opacity), Image (aspect-fill), or Liquid Glass (macOS 26 real blur)
  - Dim inactive terminals toggle (default on)
  - Ctrl+± to scale the font on the fly
- **Ctrl+W to close/quit** — closes the focused tile, or quits the app when it's the last one, without losing other session state
- **Fast keybinds**
  - Ctrl+D → add a new terminal tile (up to 4)
  - Ctrl+W → close focused tile (quits app on the last tile)
  - Cmd+Left / Cmd+Right → switch focused tile
  - Ctrl+= → increase font size
  - Ctrl+- → decrease font size
  - Ctrl+I → toggle visibility

## Install

### Download (easiest)

1. Grab `DropTerm.app.zip` from the [latest release](https://github.com/nikita-mogilevskii/dropterm/releases/latest)
2. Unzip and drag `DropTerm.app` into `/Applications`
3. **First launch:** the app is ad-hoc signed (no Apple notarization), so macOS will warn you. Right-click `DropTerm.app` → **Open** → **Open**. Or from a terminal:

   ```bash
   xattr -dr com.apple.quarantine /Applications/DropTerm.app
   ```

Requires **macOS 26 (Tahoe)** or newer.

### Build from source

No Xcode needed — Command Line Tools with the macOS 26 SDK are enough:

```bash
git clone https://github.com/nikita-mogilevskii/dropterm.git
cd dropterm
swift scripts/makeicon.swift
iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
./build.sh          # -> build/DropTerm.app
open build/DropTerm.app
```

## Test

```bash
swift run DropTermTests
```

> **Why not `swift test`?** On machines with only Command Line Tools (no Xcode) there is no `xctest` host binary, so `swift test` silently runs zero tests. The suite is therefore an executable swift-testing host — `swift run DropTermTests`.

## Keyboard Reference

| Action | Key |
|---|---|
| Toggle visibility | **Ctrl+I** |
| Add terminal tile (up to 4) | **Ctrl+D** |
| Close focused tile (quits app on the last tile) | **Ctrl+W** |
| Switch focused tile | **Cmd+Left / Cmd+Right** |
| Increase font | **Ctrl+= / Ctrl++** |
| Decrease font | **Ctrl+-** |

## Settings

All settings live in a simple preferences panel accessible via the menu bar. Changes apply instantly:

- **Fonts:** pick from system fonts or drag in custom `.ttf` or `.otf` files
- **Background:** choose Color (with opacity), Image (scaled to fill, aspect-fill), or Liquid Glass (macOS 26 real blur — color/opacity/image controls are disabled in this mode)
- **Terminals:** Dim inactive terminals toggle (default on)
- **Exit behaviour:** a shell exit closes its tile when others remain, or respawns fresh when it's the last one

One setting is not instant:

- **Shell:** set a custom shell command (default: login shell) — applies to the next session (Ctrl+D to open a fresh tile now)

State persists in `UserDefaults` (`~/Library/Preferences`).

## Architecture

`DropTermKit` (`TerminalGrid` managing 1-4 independent `TerminalSession` tiles, `SessionCommand` resolving each tile's tmux session name, `SettingsStore` for persisted preferences) + thin NSStatusItem-driven borderless key panel (`StatusController`, fixed-geometry `NSPanel`) hosting SwiftUI views over SwiftTerm's terminal emulator. Design docs in `docs/superpowers/`.

## License

[MIT](LICENSE) © 2026 Nikita Mogilevskii
