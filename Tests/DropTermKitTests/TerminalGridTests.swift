import AppKit
import Testing
@testable import DropTermKit

@Suite("TerminalGrid", .serialized)
struct TerminalGridTests {

    final class FakeSurface: TerminalSurface {
        let view = NSView()
        var currentDirectory: String? = nil
        func terminateProcess() {}
    }
    final class FakeFactory: TerminalSurfaceFactory {
        func makeSurface(command: ResolvedCommand, directory: String,
                         onProcessExit: @escaping (Int32?) -> Void) throws -> TerminalSurface {
            FakeSurface()
        }
    }

    func grid() -> TerminalGrid {
        let factory = FakeFactory()
        return TerminalGrid(makeSession: { _ in
            TerminalSession(factory: factory,
                            resolved: (.plain(shell: "/bin/zsh"),
                                       ResolvedCommand(exec: "/bin/zsh", args: ["-l"])),
                            hop: { $0() })
        })
    }

    @Test func startsWithOneFocusedTile() {
        let g = grid()
        #expect(g.tiles.count == 1)
        #expect(g.tiles[0].id == 0)
        #expect(g.focusIndex == 0)
    }

    @Test func addTileFocusesNewAndCapsAtFour() {
        let g = grid()
        g.addTile(); g.addTile(); g.addTile()
        #expect(g.tiles.count == 4)
        #expect(g.tiles.map(\.id) == [0, 1, 2, 3])
        #expect(g.focusIndex == 3)
        #expect(g.canAddTile == false)
        g.addTile()                              // no-op at 4
        #expect(g.tiles.count == 4)
    }

    @Test func closingMiddleTileFreesItsSlotForReuse() {
        let g = grid()
        g.addTile(); g.addTile(); g.addTile()    // slots 0,1,2,3
        g.focus(slot: 1)
        #expect(g.closeFocusedTile() == true)    // remove slot 1
        #expect(g.tiles.map(\.id) == [0, 2, 3])
        g.addTile()                              // must reuse freed slot 1, not collide with 2/3
        #expect(g.tiles.map(\.id).sorted() == [0, 1, 2, 3])
    }

    @Test func closingLastTileReturnsFalseAndKeepsIt() {
        let g = grid()
        #expect(g.closeFocusedTile() == false)
        #expect(g.tiles.count == 1)
    }

    @Test func closeFixesFocusWhenFocusWasLast() {
        let g = grid()
        g.addTile()                              // focus at index 1
        #expect(g.focusIndex == 1)
        #expect(g.closeFocusedTile() == true)
        #expect(g.focusIndex == 0)               // clamped
        #expect(g.tiles.count == 1)
    }

    @Test func focusWraps() {
        let g = grid()
        g.addTile()                              // 2 tiles, focus 1
        g.focusNext()
        #expect(g.focusIndex == 0)               // wrapped
        g.focusPrev()
        #expect(g.focusIndex == 1)               // wrapped back
    }

    @Test func autoRespawnPolicyTracksTileCount() {
        let g = grid()
        #expect(g.tiles[0].session.autoRespawnsOnExit() == true)   // lone tile respawns
        g.addTile()
        #expect(g.tiles[0].session.autoRespawnsOnExit() == false)  // now closes on exit
    }

    @Test func sessionOnExitClosesItsTile() {
        let g = grid()
        g.addTile()                              // 2 tiles
        let slot1Session = g.tiles[1].session
        slot1Session.onExit?()                   // simulate a non-last shell exit
        #expect(g.tiles.count == 1)
        #expect(g.tiles.map(\.id) == [0])
    }

    /// Clicking a tile's terminal CONTENT never reaches the SwiftUI
    /// .onTapGesture on the tile wrapper (SwiftTerm's AppKit view consumes
    /// the mouseDown first) — focus must instead follow wherever first
    /// responder actually lands. TerminalGrid.wire() connects each session's
    /// onFocusRequested straight to focus(session:); this exercises that
    /// wiring without any real AppKit event.
    @Test func focusFollowsSessionRequest() {
        let g = grid()
        g.addTile(); g.addTile()                 // 3 tiles, focus currently at index 2
        #expect(g.focusIndex == 2)
        let slot0Session = g.tiles[0].session
        slot0Session.onFocusRequested?()         // simulate its surface becoming first responder
        #expect(g.focusIndex == 0)
    }
}
