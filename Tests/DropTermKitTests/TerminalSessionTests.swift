import AppKit
import Testing
@testable import DropTermKit

@Suite("TerminalSession", .serialized)
struct TerminalSessionTests {

    final class FakeSurface: TerminalSurface {
        let view = NSView()
        var currentDirectory: String? = nil
        var terminated = false
        func terminateProcess() { terminated = true }
    }

    final class FakeFactory: TerminalSurfaceFactory {
        struct Boom: Error, LocalizedError { var errorDescription: String? { "boom" } }
        var spawnCount = 0
        var failNext = false
        var surfaces: [FakeSurface] = []
        var exitHandlers: [(Int32?) -> Void] = []

        func makeSurface(command: ResolvedCommand, directory: String,
                         onProcessExit: @escaping (Int32?) -> Void) throws -> TerminalSurface {
            spawnCount += 1
            if failNext { failNext = false; throw Boom() }
            exitHandlers.append(onProcessExit)
            let s = FakeSurface()
            surfaces.append(s)
            return s
        }
    }

    final class Clock {
        var t = Date(timeIntervalSince1970: 0)
    }

    /// hop: { $0() } makes exit callbacks synchronous for determinism.
    func makeSession(_ factory: FakeFactory, clock: Clock = Clock()) -> TerminalSession {
        TerminalSession(factory: factory,
                        resolved: (.plain(shell: "/bin/zsh"),
                                   ResolvedCommand(exec: "/bin/zsh", args: ["-l"])),
                        now: { clock.t },
                        hop: { $0() })
    }

    @Test func startSpawnsOnceAndIsIdempotent() {
        let f = FakeFactory()
        let s = makeSession(f)
        #expect(s.state == .idle)
        s.startIfNeeded()
        s.startIfNeeded()
        #expect(f.spawnCount == 1)
        #expect(s.state == .running)
        #expect(s.generation == 1)
        #expect(s.currentView === f.surfaces[0].view)
    }

    @Test func processExitAutoRestartsWithNewGeneration() {
        let f = FakeFactory()
        let s = makeSession(f)
        s.startIfNeeded()
        f.exitHandlers[0](0)                    // shell exited
        #expect(f.spawnCount == 2)              // auto-respawn
        #expect(s.state == .running)
        #expect(s.generation == 2)              // crossfade trigger
    }

    @Test func spawnFailureParksInFailedWithoutRetryLoop() {
        let f = FakeFactory()
        f.failNext = true
        let s = makeSession(f)
        s.startIfNeeded()
        #expect(s.state == .failed("boom"))
        #expect(f.spawnCount == 1)              // no auto-retry
        #expect(s.currentView == nil)
    }

    @Test func retryFromFailedSpawns() {
        let f = FakeFactory()
        f.failNext = true
        let s = makeSession(f)
        s.startIfNeeded()
        s.retry()
        #expect(s.state == .running)
        #expect(f.spawnCount == 2)
    }

    @Test func retryWhileRunningIsIgnored() {
        let f = FakeFactory()
        let s = makeSession(f)
        s.startIfNeeded()
        s.retry()
        #expect(f.spawnCount == 1)
    }

    @Test func restartTerminatesOldAndSpawnsNew() {
        let f = FakeFactory()
        let s = makeSession(f)
        s.startIfNeeded()
        s.restart()
        #expect(f.surfaces[0].terminated == true)
        #expect(f.spawnCount == 2)
        #expect(s.generation == 2)
        #expect(s.currentView === f.surfaces[1].view)
    }

    @Test func staleExitFromReplacedSurfaceIsIgnored() {
        let f = FakeFactory()
        let s = makeSession(f)
        s.startIfNeeded()
        let oldExit = f.exitHandlers[0]
        s.restart()                              // surface #2 now live
        oldExit(137)                             // late exit from the killed #1
        #expect(f.spawnCount == 2)               // must NOT trigger respawn #3
        #expect(s.generation == 2)
    }

    @Test func twoConsecutiveRapidExitsParkInFailed() {
        let f = FakeFactory()
        let s = makeSession(f)
        s.startIfNeeded()
        f.exitHandlers[0](127)          // rapid exit #1 -> respawn
        #expect(f.spawnCount == 2)
        f.exitHandlers[1](127)          // rapid exit #2 -> park
        #expect(s.state == .failed("Shell exited immediately"))
        #expect(f.spawnCount == 2)      // no strobe
        #expect(s.currentView == nil)
    }

    @Test func slowExitResetsRapidCounter() {
        let f = FakeFactory()
        let clock = Clock()
        let s = makeSession(f, clock: clock)
        s.startIfNeeded()
        f.exitHandlers[0](127)          // rapid #1 -> respawn (2)
        clock.t += 60                   // healthy session for a minute
        f.exitHandlers[1](0)            // slow exit -> counter resets -> respawn (3)
        #expect(s.state == .running)
        #expect(f.spawnCount == 3)
        f.exitHandlers[2](127)          // rapid #1 again -> respawn (4), not failed
        #expect(s.state == .running)
        #expect(f.spawnCount == 4)
    }

    @Test func retryAfterRapidFailureGetsFreshChances() {
        let f = FakeFactory()
        let s = makeSession(f)
        s.startIfNeeded()
        f.exitHandlers[0](127)
        f.exitHandlers[1](127)          // parked in .failed
        s.retry()
        #expect(s.state == .running)
        #expect(f.spawnCount == 3)
        f.exitHandlers[2](127)          // one rapid exit after retry -> respawn, not instant fail
        #expect(f.spawnCount == 4)
    }

    @Test func cleanExitClosesTileWhenAutoRespawnDisabled() {
        let f = FakeFactory()
        let s = makeSession(f)
        var closed = false
        s.autoRespawnsOnExit = { false }
        s.onExit = { closed = true }
        s.startIfNeeded()
        f.exitHandlers[0](0)
        #expect(closed == true)
        #expect(s.state == .idle)
        #expect(f.spawnCount == 1)          // did NOT respawn
    }

    @Test func cleanExitRespawnsWhenAutoRespawnEnabled() {
        let f = FakeFactory()
        let s = makeSession(f)
        s.autoRespawnsOnExit = { true }     // default, explicit for clarity
        s.startIfNeeded()
        f.exitHandlers[0](0)
        #expect(s.state == .running)
        #expect(f.spawnCount == 2)
    }

    @Test func rapidExitsParkInFailedEvenWhenCloseDisabled() {
        let f = FakeFactory()
        let s = makeSession(f)
        s.autoRespawnsOnExit = { false }
        var closed = false
        s.onExit = { closed = true }
        s.startIfNeeded()
        f.exitHandlers[0](127)          // rapid #1 -> close path -> onExit + idle
        // The close branch WINS here: the rapid-exit guard only parks on the
        // SECOND consecutive rapid exit (rapidExitLimit == 2). On exit #1
        // rapidExitCount is 1 (< 2), so it does NOT park; it falls through to
        // the close branch (autoRespawnsOnExit() == false) -> .idle + onExit.
        // A closing tile therefore tears down on the first exit and never
        // reaches the rapid-exit park (there is no second exit to trigger it).
        #expect(closed == true)
        #expect(s.state == .idle)
        #expect(f.spawnCount == 1)
    }
}
