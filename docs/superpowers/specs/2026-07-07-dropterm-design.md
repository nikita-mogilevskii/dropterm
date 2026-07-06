# DropTerm — Design Spec

**Date:** 2026-07-07
**Status:** Approved pending user review

## What

A macOS menu-bar-only app hosting a real interactive terminal inside a
Liquid Glass dropdown panel. Click the menu bar icon, get your shell;
click away, the panel closes but the shell session keeps running.

## Requirements

1. Menu bar item: SF Symbol `terminal` icon only (no text).
2. Clicking opens a dropdown panel (MenuBarExtra `.window` style)
   filled by a terminal emulator. Default size **700×420**.
3. **Resizable by dragging the bottom-right corner** (custom drag
   handle). Size clamped 480×300 … 1200×800, persisted in
   `UserDefaults` (`@AppStorage`), restored across panel opens AND app
   restarts. The pty winsize follows the view (SwiftTerm handles
   resize on layout).
4. Terminal is a **real pty** running the user's **login shell**
   (`$SHELL -l`, fallback `/bin/zsh -l`), cwd `$HOME`,
   `TERM=xterm-256color`.
5. **One persistent session**: created lazily on first panel open;
   closing/reopening the panel re-hosts the SAME live session (running
   jobs, cwd, scrollback intact).
6. **Shell exit = reset.** When the shell exits (`exit`, Ctrl+D, kill
   — note: Ctrl+C only interrupts the foreground job, it does not exit
   the shell), a fresh login shell auto-spawns with a **crossfade
   animation**: old terminal fades out, new one fades in (~0.35s
   easeInOut total). No dead-session overlay in the normal path.
7. **Spawn failure only** → dim overlay: "Couldn't start shell" +
   **Retry** button. Never crash.
8. Footer: Launch at login checkbox (`SMAppService.mainApp`), Restart
   button (force reset: kills current shell → same crossfade), Quit.
9. Keyboard input lands in the terminal immediately on panel open
   (first responder on appear).
10. Menu bar only: `LSUIElement = true`, no Dock icon.
11. Chrome: the dropdown panel is **standard macOS 26 material** (the
    system's window/glass appearance); inside it sits the terminal as
    a **black, rounded-corner** surface (corner radius matching the
    panel's curvature, inset padding) — dark terminal card on native
    glass.
12. Panel dismisses on outside click (standard MenuBarExtra behavior)
    — acceptable because the session persists.

## Stack & constraints

| Piece | Choice |
|---|---|
| UI | SwiftUI, `MenuBarExtra` `.window` style |
| Terminal | **SwiftTerm** (`LocalProcessTerminalView`) — the only external dependency |
| Target | macOS 26 (Tahoe) minimum |
| Glass | `.glassEffect()` / `.buttonStyle(.glass)` / `.glassProminent` |
| App type | `LSUIElement = true` |
| Login item | `SMAppService.mainApp` |
| Build | SwiftPM + `build.sh` (no Xcode.app — CLT 26.6 + macOS 26 SDK). Release build uses `--product DropTerm` (test target cannot compile in release). |
| Tests | Swift Testing via executable host: `swift run DropTermTests` (`swift test` is a silent no-op on CLT-only machines — no xctest host). Package.swift carries the CLT Testing.framework `-F`/rpath flags. |

### Known machine risks (from Cadence build-out)

- First `swift package resolve` fetches SwiftTerm from GitHub; the
  local egress guard may block agent-run fetches → user runs
  `swift package resolve` once manually; cached afterward.
- `./build.sh` direct execution is guard-blocked for agents → agents
  run its commands inline; script committed for human use.

## Architecture

```
DropTermApp (@main, MenuBarExtra .window, Image(systemName: "terminal"))
 ├── TerminalSession   (ObservableObject; app-lifetime singleton owned by App)
 │     - owns the CURRENT LocalProcessTerminalView + pty/process lifecycle
 │     - state: .idle | .running | .failed(String)
 │     - generation: Int (increments per spawn — drives the crossfade)
 │     - start(): spawns $SHELL -l in $HOME with TERM=xterm-256color
 │     - restart(): kills current process (if any), spawns fresh, generation += 1
 │     - LocalProcessTerminalViewDelegate.processTerminated → auto restart()
 │       (normal path: shell exit = reset)
 │     - spawn failure → .failed(message), no auto-retry loop
 ├── TerminalHostView  (NSViewRepresentable)
 │     - returns session's CURRENT NSView (keyed by generation)
 │     - makeFirstResponder on appear
 └── PanelView (size from PanelSizeStore, default 700×420)
       ├── terminal card: black background, rounded corners (radius ≈
       │   panel curvature), inset from panel edges — hosted on standard
       │   macOS 26 material chrome
       ├── crossfade: terminal card content is .id(session.generation)
       │   with .transition(.opacity) inside withAnimation(.easeInOut)
       │   — old fades out, fresh shell fades in on every reset
       ├── if .failed → dim overlay: "Couldn't start shell" + Retry
       ├── footer: Launch at login · Restart · Quit
       └── resize handle (bottom-right): DragGesture updates
           PanelSizeStore live; panel .frame follows
 └── PanelSizeStore (ObservableObject)
       - width/height, clamped 480×300…1200×800
       - persisted via UserDefaults key "panelSize.v1", loaded at init
```

**Critical invariant #1:** the pty and its NSView live in
`TerminalSession`, NEVER in SwiftUI view state. MenuBarExtra recreates
its content view hierarchy on every open; the representable must
re-host the same NSView or the session dies with the panel.

**Critical invariant #2:** auto-restart must not loop. Restart on
`processTerminated` only when the previous state was `.running`; a
spawn that fails lands in `.failed` and waits for explicit Retry.

`LoginItem` wrapper reused from the Cadence pattern (SMAppService,
log-don't-alert).

## Data flow

- Terminal scrollback lives in the emulator view for the session's
  lifetime; cleared on reset, gone on quit — intended.
- Persisted: panel size (`panelSize.v1` in UserDefaults),
  launch-at-login (owned by SMAppService itself).

## Error handling

- Shell spawn failure → `.failed` overlay (message + Retry). Never
  crash. No auto-retry (prevents spawn-crash loops).
- Shell exit for any reason while `.running` → auto-reset with
  crossfade (the feature, not an error).
- `SMAppService` registration failure → checkbox reverts, NSLog only.
- Resize: values clamped at the store boundary; garbage in
  UserDefaults → default 700×420.

## Testing

SwiftTerm's emulation is upstream's concern. Ours: session state
machine + size store. `TerminalSession` isolates process operations
behind an injectable factory so tests drive transitions without real
ptys:

- idle → running on start; generation increments
- running + processTerminated → auto-restart: running again,
  generation incremented (crossfade trigger observable)
- spawn failure → .failed, NO auto-retry on subsequent terminations
- explicit restart() from running kills old, spawns new
- PanelSizeStore: clamping both bounds, persistence roundtrip,
  corrupt/missing defaults → 700×420

Suite runs via `swift run DropTermTests` (executable Swift Testing
host, same as Cadence).

Manual smoke: build bundle, launch, type commands, close/reopen panel
(session persists), Ctrl+D → crossfade into fresh shell, Restart
button same, resize via corner drag → quit → relaunch → size
remembered, launch-at-login checkbox, Quit.

## Out of scope (YAGNI, possible v2)

tmux session sharing, tabs/splits, theming preferences, global
hotkey, scrollback persistence across app restarts, GitHub publishing
(on request).

## Decisions log

| Decision | Choice | Why |
|---|---|---|
| Session model | Persistent own shell | zero deps, survives reopen; tmux = v2 |
| Reset | Shell exit auto-respawns + crossfade | exit/Ctrl+D as the reset gesture; no dead-end overlay |
| Panel | Resizable via corner drag, size persisted | user request; custom handle, not window-manager resize |
| Chrome | Standard macOS 26 material outside, black rounded terminal card inside | user request |
| Bar | Icon only, standard dismiss | session persists, nothing lost |
| Name | DropTerm | says what it does |
| Terminal engine | SwiftTerm | mature, LocalProcessTerminalView does pty+emulation |
| Repo | `~/tradify/dropterm`, clean identity from first commit | scope guard; noreply email set at init |
