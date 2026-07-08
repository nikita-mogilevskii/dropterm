import Combine
import Foundation

/// Owns 1-4 terminal tiles, tracks focus, and wires each session's exit
/// policy: a shell exit closes its tile when others remain, or respawns
/// (crossfade) when it is the last tile. Tiles carry a STABLE slot id
/// (0..3) used both as the per-tile tmux session index and as SwiftUI
/// identity — so closing a middle tile and adding a new one never reuses
/// a live tile's tmux name.
public final class TerminalGrid: ObservableObject {

    public struct Tile: Identifiable {
        public let id: Int              // stable slot 0..3
        public let session: TerminalSession
    }

    public static let maxTiles = 4

    @Published public private(set) var tiles: [Tile]
    /// Index into `tiles` (NOT a slot). Always valid: 0..<tiles.count.
    @Published public private(set) var focusIndex: Int = 0

    /// Builds a session for a given slot (slot feeds tmux tile naming).
    private let makeSession: (Int) -> TerminalSession

    public init(makeSession: @escaping (Int) -> TerminalSession) {
        self.makeSession = makeSession
        let first = Tile(id: 0, session: makeSession(0))
        self.tiles = [first]
        wire(first.session)
    }

    public var focusedSession: TerminalSession { tiles[focusIndex].session }
    public var canAddTile: Bool { tiles.count < Self.maxTiles }

    /// Start every tile that hasn't spawned yet (panel-open entry point).
    public func startAll() { tiles.forEach { $0.session.startIfNeeded() } }

    public func addTile() {
        guard canAddTile else { return }
        let used = Set(tiles.map(\.id))
        guard let slot = (0..<Self.maxTiles).first(where: { !used.contains($0) }) else { return }
        let tile = Tile(id: slot, session: makeSession(slot))
        wire(tile.session)
        tiles.append(tile)
        focusIndex = tiles.count - 1
        tile.session.startIfNeeded()
    }

    /// Close the focused tile. Returns false when it was the LAST tile
    /// (the caller should quit the app); true after removing + refocusing.
    public func closeFocusedTile() -> Bool {
        guard tiles.count > 1 else { return false }
        let removed = tiles.remove(at: focusIndex)
        removed.session.terminate()
        if focusIndex >= tiles.count { focusIndex = tiles.count - 1 }
        return true
    }

    public func focusPrev() {
        guard !tiles.isEmpty else { return }
        focusIndex = (focusIndex - 1 + tiles.count) % tiles.count
    }

    public func focusNext() {
        guard !tiles.isEmpty else { return }
        focusIndex = (focusIndex + 1) % tiles.count
    }

    public func focus(slot: Int) {
        if let idx = tiles.firstIndex(where: { $0.id == slot }) { focusIndex = idx }
    }

    /// Move focus to whichever tile hosts `session` — the sync target for
    /// "focus follows first responder" (TerminalSession.onFocusRequested).
    public func focus(session: TerminalSession) {
        if let idx = tiles.firstIndex(where: { $0.session === session }) { focusIndex = idx }
    }

    private func wire(_ session: TerminalSession) {
        session.autoRespawnsOnExit = { [weak self] in (self?.tiles.count ?? 1) == 1 }
        session.onExit = { [weak self, weak session] in
            guard let self, let session,
                  let idx = self.tiles.firstIndex(where: { $0.session === session }) else { return }
            self.removeTile(at: idx)
        }
        session.onFocusRequested = { [weak self, weak session] in
            guard let self, let session else { return }
            self.focus(session: session)
        }
    }

    /// Removal driven by a shell exit (not the Ctrl+W path). The session
    /// already went .idle via handleExit; just drop it and fix focus.
    private func removeTile(at index: Int) {
        guard tiles.count > 1, tiles.indices.contains(index) else { return }
        tiles.remove(at: index)
        if focusIndex >= tiles.count { focusIndex = tiles.count - 1 }
        else if focusIndex > index { focusIndex -= 1 }
    }
}
