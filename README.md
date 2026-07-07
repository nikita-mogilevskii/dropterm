# DropTerm

A real terminal in your macOS menu bar. Click the icon, get your shell;
click away, the session keeps running.

- **Persistent session** — tmux-backed when tmux is installed (survives
  even app restarts), plain login shell otherwise
- **Exit = reset** — `exit`/Ctrl+D respawns a fresh shell with a crossfade
- **Resizable** — drag the bottom-right corner; size is remembered
- **macOS 26** — native material chrome, black rounded terminal card,
  no Dock icon

## Build

No Xcode required — Command Line Tools with the macOS 26 SDK suffice:

```bash
./build.sh          # -> build/DropTerm.app
open build/DropTerm.app
```

## Test

```bash
swift run DropTermTests
```

(`swift test` is a silent no-op on Command Line Tools-only machines — no
xctest host binary — so the suite is an executable swift-testing host.)

## Architecture

`DropTermKit` (session state machine behind an injectable surface factory,
pure tmux/resize resolvers, persisted size store) + an `NSStatusItem`-driven
borderless key panel (`StatusController`) hosting a thin SwiftUI view over
SwiftTerm's terminal view. Design docs in `docs/superpowers/`.
