# DropTerm — Design Spec

**Date:** 2026-07-07
**Status:** v4 — post-smoke iteration (v1.1)

## v1.1 amendments (supersede conflicting v1 requirements below)

Smoke feedback drove these changes:

1. **Window architecture**: manual `NSStatusItem` + borderless key-able
   `NSPanel` (hosting the SwiftUI panel via `NSHostingView`) replaces
   `MenuBarExtra` — required because v1.1 needs right-click menus and
   programmatic open, which MenuBarExtra cannot do.
   - Left-click status item: toggle the panel (anchored under the item,
     top-right corner pinned; grows leftward/downward).
   - Right-click status item: NSMenu with "Launch at login" (checkmark
     state, toggles SMAppService) and "Quit DropTerm".
   - Panel closes on outside click (event monitor) and Esc-free: no
     titlebar, no chrome buttons.
2. **Footer chin REMOVED entirely** — no Jump-to-iTerm2, no Restart, no
   Quit buttons, no launch-at-login toggle in the panel. Panel = terminal
   card only. Restart path = exit/Ctrl+D (auto-respawn) or Retry on the
   failure overlay. Quit + launch-at-login live in the right-click menu.
3. **iTerm2 jump feature DELETED** (kit code + scripts + tests). tmux
   session backing stays (persistence across app restarts). Manual
   `tmux attach -t dropterm` from any terminal still works by design.
4. **Terminal content inset**: 8pt padding between the black rounded
   card's edges and the terminal view so glyphs never clip under the
   corner radius.
5. **Scrollbar hidden** — SwiftTerm's embedded scroller is not shown
   (scrolling behavior unchanged).
6. **Resize handle invisible** — same bottom-right drag region (~18pt),
   no glyph. Feature unchanged.
7. **Resize math is screen-anchored**: deltas computed from
   `NSEvent.mouseLocation` (screen coords) captured at drag start — NOT
   from SwiftUI gesture translation, which breaks when macOS shifts the
   panel away from the screen edge mid-drag (v1 bug: hitting the right
   screen edge inverted/exploded the size). Height delta is
   y-flipped (AppKit origin bottom-left). Panel repositions to keep its
   top-right anchor as size changes.
8. **Global hotkey Ctrl+I** toggles the panel from anywhere (Carbon
   `RegisterEventHotKey` — no TCC permission needed). Known trade-off,
   user-accepted: system-wide Ctrl+I capture shadows Tab semantics in
   terminal apps; combo is one constant if it needs changing.
9. **Spotlight-style positioning (supersedes under-item anchoring)**:
   the panel is ALWAYS horizontally centered on the screen with the
   status item (fallback main screen), its top edge at Spotlight height
   (top edge at 75% of the visible frame, AppKit coords). Applies to
   click-open, hotkey-open, and every resize: the anchor is TOP-CENTER
   — width grows symmetrically around the center line. Because the
   center is pinned, the resize drag applies 2× the horizontal mouse
   delta so the right edge keeps tracking the cursor.
10. **Fixed height (supersedes height resizing/persistence)**: panel
    height is ALWAYS 50% of the current screen's visible height,
    computed at open/resize time — never user-adjustable, never
    persisted. The corner drag adjusts WIDTH only (still 2× delta,
    center-pinned, clamped 480…1200, persisted). PanelSizeStore stores
    width alone.

## v1.2 amendments (settings + publish)

11. **In-panel keyboard commands** (local NSEvent monitor, active ONLY
    while the panel is key — never global; Ctrl+I stays the only global
    binding):
    - **Ctrl+W → quit DropTerm entirely** (NSApp.terminate). tmux-backed
      sessions survive in the tmux server by design.
    - **Ctrl+= / Ctrl+- → font scale up/down** (±1pt per press, clamped
      8…28, applied live to the terminal view, persisted). Panel frame
      never changes — bigger/smaller glyphs fit less/more content.
    Monitor consumes matched events (returns nil) so the shell never
    sees them; installed on panel show, removed on hide.
12. **Settings window**, opened from a new "Settings…" item in the
    status item's right-click menu (standard titled NSWindow hosting a
    SwiftUI Form; single instance, front-and-center on open):
    - **Font**: picker over installed monospaced font families + size
      stepper (base size; Ctrl± scales from it). "Load font file…"
      button registers a .ttf/.otf via CTFontManagerRegisterFontsForURL
      (process scope) and selects it.
    - **Shell**: mode radio — "Automatic" (existing tmux→login-shell
      resolution) or "Custom command" with a full-path text field
      (e.g. /opt/homebrew/bin/fish or any binary; run with no args,
      cwd $HOME). Applies on next session (respawn note shown).
    - **Background**: color well + opacity slider (10…100%), optional
      background image (file picker, aspect-fill behind the text,
      clear button). Color/opacity/image apply LIVE to the terminal
      view (Terminal.app-style "Color & Effects" scope).
13. **TerminalSettings model** (Codable, UserDefaults key
    "settings.v1", SettingsStore ObservableObject): shellMode
    (.automatic | .custom(path)), fontName (nil = system mono),
    fontSize (8…28, default 13), backgroundColorHex (default #000000),
    backgroundOpacity (0.1…1.0, default 1.0), backgroundImagePath
    (optional). Corrupt/missing → defaults. Font/background apply live;
    shellMode on respawn.
15. **Unified panel backdrop (supersedes terminal-scoped background in
    12/13)**: color, image, and opacity style the WHOLE panel card as
    one visual surface — not the terminal view alone.
    - The terminal view is ALWAYS fully transparent (clear background,
      no embedded image view); glyphs render at full alpha.
    - The panel card's backdrop layer: background image (aspect-fill)
      when set, else the background color; the opacity setting applies
      to that backdrop layer — at <100% the DESKTOP shows through the
      entire panel (text stays crisp).
    - Rounded-corner clipping applies to the composite, so backdrop +
      terminal read as one piece.
14. **Public release, cadence-style**: app icon (generated, gradient +
    terminal glyph), MIT LICENSE, hero README (icon, badges, install
    with Gatekeeper note, usage table), public GitHub repo
    nikita-mogilevskii/dropterm, v1.2.0 release with ad-hoc signed
    Cadence-pattern zip. Clean noreply identity (already the case since
    commit #1).

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
4. Terminal is a **real pty**. Session command is resolved at spawn:
   - **tmux mode** (tmux binary found): `tmux new-session -A -s dropterm`
     — attach-or-create the named session. The session lives in the
     tmux server, so it survives DropTerm quits/relaunches too.
   - **plain mode** (no tmux): user's login shell (`$SHELL -l`,
     fallback `/bin/zsh -l`).
   Both: cwd `$HOME`, `TERM=xterm-256color`.
5. **One persistent session**: created lazily on first panel open;
   closing/reopening the panel re-hosts the SAME live session (running
   jobs, cwd, scrollback intact).
6. **Jump to iTerm2** footer button (visible only when iTerm2 is
   installed):
   - tmux mode: detach DropTerm's client, then AppleScript iTerm2 to
     open a window running `tmux attach -t dropterm` — true session
     transfer (same jobs, scrollback, cwd). Reopening the DropTerm
     panel re-attaches; if both stay attached, tmux `window-size
     latest` keeps sizing sane.
   - plain mode fallback: open a new iTerm2 window `cd`'d to the
     DropTerm shell's current directory (jobs stay behind).
   - First use triggers the macOS automation permission prompt
     ("DropTerm wants to control iTerm2") — expected, once.
7. **Client exit = reset.** When the hosted process exits (`exit`,
   Ctrl+D, kill — note: Ctrl+C only interrupts the foreground job, it
   does not exit the shell), a fresh spawn happens with a **crossfade
   animation**: old terminal fades out, new one fades in (~0.35s
   easeInOut total). No dead-session overlay in the normal path.
   tmux nuance: ending the shell inside tmux kills the tmux session →
   respawn creates a fresh one; a mere detach re-attaches to the
   living session (crossfade into the same content — fine).
8. **Spawn failure only** → dim overlay: "Couldn't start shell" +
   **Retry** button. Never crash.
9. Footer: Launch at login checkbox (`SMAppService.mainApp`),
   Jump to iTerm2 (req. 6), Restart button (force reset: kills current
   client → same crossfade), Quit.
10. Keyboard input lands in the terminal immediately on panel open
    (first responder on appear).
11. Menu bar only: `LSUIElement = true`, no Dock icon.
12. Chrome: the dropdown panel is **standard macOS 26 material** (the
    system's window/glass appearance); inside it sits the terminal as
    a **black, rounded-corner** surface (corner radius matching the
    panel's curvature, inset padding) — dark terminal card on native
    glass.
13. Panel dismisses on outside click (standard MenuBarExtra behavior)
    — acceptable because the session persists.

## Stack & constraints

| Piece | Choice |
|---|---|
| UI | SwiftUI, `MenuBarExtra` `.window` style |
| Terminal | **SwiftTerm** (`LocalProcessTerminalView`) — the only external build dependency |
| Session backing | **tmux when present** (optional runtime dep; plain login shell otherwise) |
| iTerm2 jump | AppleScript via `osascript`/NSAppleScript; button hidden if iTerm2 absent |
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
 ├── SessionCommand    (pure resolver, injectable for tests)
 │     - findTmux(): first existing of /opt/homebrew/bin/tmux,
 │       /usr/local/bin/tmux, /usr/bin/tmux → mode
 │     - .tmux(path)  → exec: path, args: ["new-session","-A","-s","dropterm"]
 │     - .plain(shell) → exec: $SHELL (fallback /bin/zsh), args: ["-l"]
 ├── TerminalSession   (ObservableObject; app-lifetime singleton owned by App)
 │     - owns the CURRENT LocalProcessTerminalView + pty/process lifecycle
 │     - state: .idle | .running | .failed(String); mode: .tmux | .plain
 │     - generation: Int (increments per spawn — drives the crossfade)
 │     - start(): spawns SessionCommand result in $HOME, TERM=xterm-256color
 │     - restart(): kills current process (if any), spawns fresh, generation += 1
 │     - LocalProcessTerminalViewDelegate.processTerminated → auto restart()
 │       (normal path: client exit = reset; tmux detach = re-attach)
 │     - spawn failure → .failed(message), no auto-retry loop
 ├── ITermJump         (footer action; enabled iff iTerm2 installed —
 │     NSWorkspace lookup of bundle id com.googlecode.iterm2)
 │     - tmux mode: send detach to our client, then AppleScript iTerm2:
 │       create window running "tmux attach -t dropterm", activate
 │     - plain mode: read shell cwd (lsof -a -p <pid> -d cwd), AppleScript
 │       iTerm2: new window, "cd <cwd>"
 │     - script strings built by a pure, unit-testable builder
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
- Jump failures (AppleScript error, automation permission denied,
  iTerm2 vanished): NSLog + transient inline message near the button;
  session untouched. Never crash.

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
- SessionCommand: tmux found → tmux argv; not found → $SHELL -l argv;
  no $SHELL → /bin/zsh -l
- ITermJump script builder: tmux mode emits attach command; plain mode
  emits cd command with the provided cwd; cwd with spaces/quotes is
  escaped correctly
- PanelSizeStore: clamping both bounds, persistence roundtrip,
  corrupt/missing defaults → 700×420

Suite runs via `swift run DropTermTests` (executable Swift Testing
host, same as Cadence).

Manual smoke: build bundle, launch, type commands, close/reopen panel
(session persists), Ctrl+D → crossfade into fresh shell, Restart
button same, resize via corner drag → quit → relaunch → size
remembered, launch-at-login checkbox, Quit.

## Out of scope (YAGNI, possible v2)

Tabs/splits, theming preferences, global hotkey, scrollback
persistence in plain mode, multiple named tmux sessions, GitHub
publishing (on request).

## Decisions log

| Decision | Choice | Why |
|---|---|---|
| Session model | tmux-backed when available, plain shell otherwise | enables true iTerm2 handoff; survives app quits in tmux mode |
| iTerm2 jump | Detach + AppleScript attach (tmux) / cwd-only (plain) | pty cannot cross processes; tmux is the only true transfer |
| Reset | Shell exit auto-respawns + crossfade | exit/Ctrl+D as the reset gesture; no dead-end overlay |
| Panel | Resizable via corner drag, size persisted | user request; custom handle, not window-manager resize |
| Chrome | Standard macOS 26 material outside, black rounded terminal card inside | user request |
| Bar | Icon only, standard dismiss | session persists, nothing lost |
| Name | DropTerm | says what it does |
| Terminal engine | SwiftTerm | mature, LocalProcessTerminalView does pty+emulation |
| Repo | `~/tradify/dropterm`, clean identity from first commit | scope guard; noreply email set at init |
