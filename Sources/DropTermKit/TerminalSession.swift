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
public final class TerminalSession: ObservableObject {

    @Published public private(set) var state: SessionState = .idle
    /// Increments on every spawn; the UI keys the crossfade off this.
    @Published public private(set) var generation = 0

    public let mode: SessionMode
    private let command: ResolvedCommand
    private let factory: TerminalSurfaceFactory
    /// Marshals exit callbacks (main queue in production, identity in tests).
    private let hop: (@escaping () -> Void) -> Void
    private var surface: TerminalSurface?

    public var currentView: NSView? { surface?.view }
    public var currentDirectory: String? { surface?.currentDirectory }

    public init(factory: TerminalSurfaceFactory,
                resolved: (mode: SessionMode, command: ResolvedCommand) = SessionCommand.resolve(),
                hop: @escaping (@escaping () -> Void) -> Void = { work in DispatchQueue.main.async(execute: work) }) {
        self.factory = factory
        self.mode = resolved.mode
        self.command = resolved.command
        self.hop = hop
    }

    public func startIfNeeded() {
        guard state == .idle else { return }
        spawn()
    }

    /// Force reset: kill the current process (if any) and spawn fresh.
    public func restart() {
        surface?.terminateProcess()
        surface = nil
        spawn()
    }

    /// Explicit escape from .failed only (spawn failures never auto-loop).
    public func retry() {
        guard case .failed = state else { return }
        spawn()
    }

    private func spawn() {
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
        spawn()
    }
}
