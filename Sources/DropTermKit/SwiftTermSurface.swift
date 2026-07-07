import AppKit
import SwiftTerm

/// Real factory: SwiftTerm's LocalProcessTerminalView running the resolved
/// command on a pty.
public final class SwiftTermSurfaceFactory: TerminalSurfaceFactory {
    private let settingsStore: SettingsStore

    public init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    public func makeSurface(command: ResolvedCommand,
                            directory: String,
                            onProcessExit: @escaping (Int32?) -> Void) throws -> TerminalSurface {
        SwiftTermSurface(command: command, directory: directory,
                         settings: settingsStore.settings, onProcessExit: onProcessExit)
    }
}

final class SwiftTermSurface: NSObject, TerminalSurface, LocalProcessTerminalViewDelegate {

    private let terminalView: LocalProcessTerminalView
    private let onProcessExit: (Int32?) -> Void
    private(set) var lastReportedDirectory: String?

    /// Background/image/opacity now live on the panel card (PanelView's
    /// backdrop, spec amendment 15) — the terminal view is the whole
    /// surface here, always transparent, so it doubles as `focusView` via
    /// the protocol's default extension.
    var view: NSView { terminalView }

    /// OSC 7 report when the shell emits one; lsof on the shell pid
    /// otherwise (a bare `zsh -l` never emits OSC 7).
    var currentDirectory: String? {
        lastReportedDirectory ?? lsofCwd()
    }

    private func lsofCwd() -> String? {
        // SwiftTerm 1.13.0 exposes the child pid via LocalProcess.shellPid.
        let pid = terminalView.process.shellPid
        guard pid > 0 else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        p.arguments = ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return nil }
        // Bound the wait: currentDirectory can be read from the main thread,
        // and a hung lsof must not freeze the app.
        let sem = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            p.waitUntilExit()
            sem.signal()
        }
        if sem.wait(timeout: .now() + .milliseconds(500)) == .timedOut {
            p.terminate()
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let out = String(data: data, encoding: .utf8) else { return nil }
        // Output lines: "p<pid>", "fcwd", "n/actual/path"
        return out.split(separator: "\n")
            .first { $0.hasPrefix("n") }
            .map { String($0.dropFirst()) }
    }

    init(command: ResolvedCommand, directory: String, settings: TerminalSettings,
         onProcessExit: @escaping (Int32?) -> Void) {
        self.onProcessExit = onProcessExit
        self.terminalView = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 700, height: 400))
        super.init()

        terminalView.processDelegate = self
        terminalView.nativeForegroundColor = .white
        Self.makeFullyTransparent(terminalView)

        // SwiftTerm's macOS TerminalView has no public scrollerVisible /
        // allowScrolling switch (checked MacTerminalView.swift) — it wires an
        // NSScroller as a private subview in setup() -> setupScroller(),
        // created synchronously and unconditionally (before this initializer
        // returns), so hiding it here is not racing a later layout pass.
        // Hidden scroller still tracks state (updateScroller toggles isEnabled/
        // doubleValue, never isHidden), and wheel/trackpad scrolling is a
        // separate code path (scrollWheel(with:) -> scrollUp/scrollDown) that
        // doesn't touch the scroller view at all, so it keeps working.
        Self.hideScroller(in: terminalView)

        applyAppearance(settings)

        let environment = Terminal.getEnvironmentVariables(termName: "xterm-256color")

        // LocalProcessTerminalView.startProcess takes currentDirectory directly
        // (forwarded to LocalProcess -> PseudoTerminalHelpers.fork, which chdirs
        // in the forked child before exec) — no need to mutate the app's cwd.
        terminalView.startProcess(executable: command.exec,
                                  args: command.args,
                                  environment: environment,
                                  currentDirectory: directory)
    }

    func apply(settings: TerminalSettings) {
        applyAppearance(settings)
    }

    /// Font only, live-updatable. Background/opacity/image moved to the
    /// panel card (spec amendment 15, PanelView.backdrop) — this surface no
    /// longer has an appearance path for any of them.
    private func applyAppearance(_ settings: TerminalSettings) {
        terminalView.font = Self.resolvedFont(settings)
    }

    /// The terminal view is ALWAYS fully transparent so the panel card's
    /// backdrop (color/image/opacity) shows straight through and glyphs
    /// render at full alpha regardless of backdrop opacity. Set once, here,
    /// for the surface's whole lifetime — nothing in settings ever touches
    /// this again.
    ///
    /// TerminalView.nativeBackgroundColor feeds two paint paths (checked in
    /// SwiftTerm's Apple/AppleTerminalView.swift + Mac/MacTerminalView.swift):
    /// (1) every default-background glyph cell is filled per-run via
    /// `mapColor(.defaultColor) -> nativeBackgroundColor` directly, and (2)
    /// the view's own CALayer.backgroundColor, painted once in
    /// setupOptions() during init and NOT refreshed by the
    /// nativeBackgroundColor setter — so both must be set to clear
    /// explicitly, plus a forced redisplay since the setter doesn't request
    /// one either (unlike the `font` setter, which calls resetFont() ->
    /// needsDisplay = true). CALayer's default isOpaque is false, so alpha 0
    /// here composites straight through to whatever sits behind the view.
    private static func makeFullyTransparent(_ terminalView: LocalProcessTerminalView) {
        terminalView.nativeBackgroundColor = .clear
        terminalView.layer?.backgroundColor = NSColor.clear.cgColor
        terminalView.needsDisplay = true
    }

    private static func resolvedFont(_ settings: TerminalSettings) -> NSFont {
        if let name = settings.fontName, let font = NSFont(name: name, size: settings.fontSize) {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: settings.fontSize, weight: .regular)
    }

    /// No public API hides SwiftTerm's macOS scroller, so reach into its
    /// subviews directly.
    private static func hideScroller(in terminalView: NSView) {
        terminalView.subviews.compactMap { $0 as? NSScroller }.forEach { $0.isHidden = true }
    }

    func terminateProcess() {
        // LocalProcess.terminate() sends SIGTERM to the child pid and tears
        // down the pty's DispatchIO.
        terminalView.process.terminate()
    }

    // MARK: - LocalProcessTerminalViewDelegate

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        onProcessExit(exitCode)
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        lastReportedDirectory = directory
    }
}
