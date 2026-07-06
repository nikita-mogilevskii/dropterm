# DropTerm — Design Spec

**Date:** 2026-07-07
**Status:** Approved pending user review

## What

A macOS menu-bar-only app hosting a real interactive terminal inside a
Liquid Glass dropdown panel. Click the menu bar icon, get your shell;
click away, the panel closes but the shell session keeps running.

## Requirements

1. Menu bar item: SF Symbol `terminal` icon only (no text).
2. Clicking opens a **fixed 700×420** dropdown panel (MenuBarExtra
   `.window` style) filled by a terminal emulator.
3. Terminal is a **real pty** running the user's **login shell**
   (`$SHELL -l`, fallback `/bin/zsh -l`), cwd `$HOME`,
   `TERM=xterm-256color`.
4. **One persistent session**: created lazily on first panel open;
   closing/reopening the panel re-hosts the SAME live session (running
   jobs, cwd, scrollback intact). Session dies only on app quit or
   shell exit.
5. Shell exit (or spawn failure) → dim overlay over the terminal:
   "Session ended" + **Restart** button (spawns a fresh login shell).
6. Footer: Launch at login checkbox (`SMAppService.mainApp`), Restart
   button, Quit button.
7. Keyboard input lands in the terminal immediately on panel open
   (first responder on appear).
8. Menu bar only: `LSUIElement = true`, no Dock icon.
9. Native **Liquid Glass** chrome (macOS 26 APIs) around the terminal;
   terminal area itself is a standard dark emulator surface.
10. Panel dismisses on outside click (standard MenuBarExtra behavior)
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
 │     - owns the ONE LocalProcessTerminalView + pty/process lifecycle
 │     - state: .idle | .running | .exited(code: Int32?)
 │     - start(): spawns $SHELL -l in $HOME with TERM=xterm-256color
 │     - restart(): tears down old view/process, spawns fresh
 │     - LocalProcessTerminalViewDelegate.processTerminated → .exited
 ├── TerminalHostView  (NSViewRepresentable)
 │     - returns session's existing NSView every time (no re-creation)
 │     - makeFirstResponder on appear
 └── PanelView (700×420)
       ├── TerminalHostView (fills)
       ├── if .exited → overlay: "Session ended" + Restart (.glassProminent)
       │     (spawn failure also lands in .exited(code: nil))
       └── footer: Launch at login · Restart · Quit
```

**The critical invariant:** the pty and its NSView live in
`TerminalSession`, NEVER in SwiftUI view state. MenuBarExtra recreates
its content view hierarchy on every open; the representable must
re-host the same NSView or the session dies with the panel.

`LoginItem` wrapper reused from the Cadence pattern (SMAppService,
log-don't-alert).

## Data flow

- No persistence of terminal state (scrollback lives in the emulator
  view for the app's lifetime; gone on quit — intended).
- Only persisted setting: launch-at-login (owned by SMAppService itself).
- No UserDefaults schema in v1.

## Error handling

- Shell spawn failure → `.exited` overlay (message + Restart). Never
  crash.
- Process exit for any reason (exit, kill, crash) → same overlay.
- `SMAppService` registration failure → checkbox reverts, NSLog only.

## Testing

SwiftTerm's emulation is upstream's concern. Ours is the session state
machine. `TerminalSession` isolates process operations behind an
injectable factory so tests drive transitions without real ptys:

- idle → running on start
- running → exited on processTerminated
- exited → running on restart (old resources torn down)
- restart from running replaces the session
- spawn failure → exited(nil)

Suite runs via `swift run DropTermTests` (executable Swift Testing
host, same as Cadence).

Manual smoke: build bundle, launch, type commands, close/reopen panel
(session persists), `exit` → overlay → Restart, launch-at-login
checkbox, Quit.

## Out of scope (YAGNI, possible v2)

tmux session sharing, resizable panel, tabs/splits, theming
preferences, global hotkey, scrollback persistence across app
restarts, GitHub publishing (on request).

## Decisions log

| Decision | Choice | Why |
|---|---|---|
| Session model | Persistent own shell | zero deps, survives reopen; tmux = v2 |
| Panel | Fixed 700×420 | MenuBarExtra resizes poorly; solid v1 |
| Bar | Icon only, standard dismiss | session persists, nothing lost |
| Name | DropTerm | says what it does |
| Terminal engine | SwiftTerm | mature, LocalProcessTerminalView does pty+emulation |
| Repo | `~/tradify/dropterm`, clean identity from first commit | scope guard; noreply email set at init |
