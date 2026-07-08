import AppKit
import Combine

public enum SessionState: Equatable {
    case idle
    case running
    case failed(String)
}

/// Owns the live terminal surface and its lifecycle. The pty and NSView
/// live HERE, never in SwiftUI view state — MenuBarExtra recreates its
/// content on every open, and the session must survive that.
///
/// Not thread-safe: call all public API on the main thread; exit callbacks
/// are marshalled onto it via `hop`.
public final class TerminalSession: ObservableObject {

    @Published public private(set) var state: SessionState = .idle
    /// Increments on every spawn; the UI keys the crossfade off this.
    @Published public private(set) var generation = 0

    /// The mode the most recent spawn resolved to. Not `let`: a
    /// settings-backed provider re-resolves on every spawn, so shell-mode
    /// changes take effect on the next respawn with no extra plumbing.
    public private(set) var mode: SessionMode
    private var command: ResolvedCommand
    /// Re-resolved fresh on every spawn(). The `resolved:` init below seeds
    /// this with a provider that always returns the same captured value
    /// (matching the old `let command` behavior exactly, for existing
    /// tests); the `settingsStore:` init seeds it with a provider that reads
    /// the store live.
    private var commandProvider: () -> (mode: SessionMode, command: ResolvedCommand)
    private let factory: TerminalSurfaceFactory
    /// Marshals exit callbacks (main queue in production, identity in tests).
    private let hop: (@escaping () -> Void) -> Void
    private var surface: TerminalSurface?

    /// Injectable clock so rapid-exit detection is deterministic in tests.
    private let now: () -> Date
    private var lastSpawnAt: Date?
    private var rapidExitCount = 0
    private static let rapidExitWindow: TimeInterval = 1.0
    private static let rapidExitLimit = 2

    public var currentView: NSView? { surface?.view }
    public var currentFocusView: NSView? { surface?.focusView }
    public var currentDirectory: String? { surface?.currentDirectory }

    /// When a running shell exits cleanly, respawn (last-tile crossfade
    /// behavior) if this returns true, otherwise go idle and fire `onExit`
    /// so an owner (the grid) can tear the tile down. Default: always
    /// respawn — matches single-session v1.2 behavior.
    public var autoRespawnsOnExit: () -> Bool = { true }

    /// Fired (on the hop queue) when a running shell exits and
    /// `autoRespawnsOnExit()` returned false — i.e. the owner should remove
    /// this tile. Never fired on the rapid-exit → .failed path.
    public var onExit: (() -> Void)?

    public init(factory: TerminalSurfaceFactory,
                resolved: (mode: SessionMode, command: ResolvedCommand) = SessionCommand.resolve(),
                now: @escaping () -> Date = Date.init,
                hop: @escaping (@escaping () -> Void) -> Void = { work in DispatchQueue.main.async(execute: work) }) {
        self.factory = factory
        self.commandProvider = { resolved }
        self.mode = resolved.mode
        self.command = resolved.command
        self.now = now
        self.hop = hop
    }

    /// Settings-aware convenience init: shell mode is re-resolved from the
    /// store on every spawn (see `commandProvider`), so flipping
    /// automatic/custom shell in Settings applies on the next respawn.
    public init(factory: TerminalSurfaceFactory,
                settingsStore: SettingsStore,
                now: @escaping () -> Date = Date.init,
                hop: @escaping (@escaping () -> Void) -> Void = { work in DispatchQueue.main.async(execute: work) }) {
        self.factory = factory
        self.commandProvider = { SessionCommand.resolve(settings: settingsStore.settings) }
        let initial = SessionCommand.resolve(settings: settingsStore.settings)
        self.mode = initial.mode
        self.command = initial.command
        self.now = now
        self.hop = hop
    }

    /// Per-tile settings-aware init: resolves with a tile index so tmux
    /// tiles get distinct session names.
    public convenience init(factory: TerminalSurfaceFactory,
                            settingsStore: SettingsStore,
                            tileIndex: Int,
                            now: @escaping () -> Date = Date.init,
                            hop: @escaping (@escaping () -> Void) -> Void = { work in DispatchQueue.main.async(execute: work) }) {
        self.init(factory: factory,
                  resolved: SessionCommand.resolve(settings: settingsStore.settings, tileIndex: tileIndex),
                  now: now, hop: hop)
        // Re-resolve per spawn so shell-mode changes still apply on respawn,
        // preserving the tile index.
        self.overrideProvider { SessionCommand.resolve(settings: settingsStore.settings, tileIndex: tileIndex) }
    }

    private func overrideProvider(_ provider: @escaping () -> (mode: SessionMode, command: ResolvedCommand)) {
        commandProvider = provider
    }

    public func startIfNeeded() {
        guard state == .idle else { return }
        spawn()
    }

    /// Force reset: kill the current process (if any) and spawn fresh.
    public func restart() {
        surface?.terminateProcess()
        surface = nil
        rapidExitCount = 0
        spawn()
    }

    /// Explicit escape from .failed only (spawn failures never auto-loop).
    public func retry() {
        guard case .failed = state else { return }
        rapidExitCount = 0
        spawn()
    }

    /// Live-apply appearance settings (font, background) to whatever surface
    /// is currently running. No-op if no session has spawned yet.
    public func applySettings(_ settings: TerminalSettings) {
        surface?.apply(settings: settings)
    }

    /// Stop this session's process and release its surface, for tile close.
    /// Sets .idle FIRST so the resulting processTerminated callback is
    /// guarded out (handleExit only acts while .running) — closing a tile
    /// must never fire onExit or respawn.
    public func terminate() {
        state = .idle
        surface?.terminateProcess()
        surface = nil
    }

    private func spawn() {
        let resolved = commandProvider()
        mode = resolved.mode
        command = resolved.command
        let gen = generation + 1
        do {
            let newSurface = try factory.makeSurface(
                command: command,
                directory: NSHomeDirectory(),
                onProcessExit: { [weak self] _ in
                    guard let self else { return }
                    self.hop { self.handleExit(generation: gen) }
                })
            surface = newSurface
            generation = gen
            state = .running
            lastSpawnAt = self.now()
        } catch {
            surface = nil
            state = .failed(error.localizedDescription)
        }
    }

    private func handleExit(generation gen: Int) {
        // Stale callbacks from replaced surfaces must not respawn (a restart
        // already did); and only .running auto-resets — .failed waits for Retry.
        guard gen == generation, state == .running else { return }
        surface = nil

        // The real factory cannot throw: exec failures surface as instant
        // process exits. Two consecutive sub-second lifetimes = broken spawn;
        // park in .failed instead of strobing respawns forever.
        let lifetime = now().timeIntervalSince(lastSpawnAt ?? .distantPast)
        if lifetime < Self.rapidExitWindow {
            rapidExitCount += 1
            if rapidExitCount >= Self.rapidExitLimit {
                state = .failed("Shell exited immediately")
                return
            }
        } else {
            rapidExitCount = 0
        }

        if autoRespawnsOnExit() {
            spawn()
        } else {
            state = .idle
            onExit?()
        }
    }
}
