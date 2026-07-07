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

    /// Stable wrapper: `imageView` (background, hidden unless a settings
    /// image is loaded) sits BEHIND `terminalView`. Identity never changes
    /// after init — appearance updates mutate the image view in place —
    /// so TerminalHostView's NSViewRepresentable never sees `view`'s
    /// identity change and never has to notice a re-parent between SwiftUI
    /// render passes (it only re-attaches when `view` itself is a new
    /// object; nothing currently forces that update if we swapped roots
    /// out from under it after settings changes).
    private let containerView: NSView
    private let imageView: NSImageView

    var view: NSView { containerView }
    /// The container itself never accepts key events (plain NSView) — the
    /// real interactive surface is always `terminalView`.
    var focusView: NSView { terminalView }

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
        self.imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: 700, height: 400))
        self.containerView = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 400))
        super.init()

        containerView.wantsLayer = true
        imageView.wantsLayer = true
        imageView.isHidden = true   // no image configured until applyAppearance says otherwise

        // Image behind, terminal on top — CALayer sublayers always paint
        // over their parent's own drawn content, so this only needs
        // sibling z-order, not any special "insert below" trick.
        containerView.addSubview(imageView)
        containerView.addSubview(terminalView)
        for v in [imageView, terminalView] {
            v.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: containerView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            terminalView.topAnchor.constraint(equalTo: containerView.topAnchor),
            terminalView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            terminalView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
        ])

        terminalView.processDelegate = self
        terminalView.nativeForegroundColor = .white

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

    /// Font + background color/opacity + background image, all live-updatable.
    ///
    /// Background: TerminalView.nativeBackgroundColor feeds two paint paths
    /// (checked in SwiftTerm's Apple/AppleTerminalView.swift +
    /// Mac/MacTerminalView.swift) — (1) every default-background glyph cell
    /// is filled per-run via `mapColor(.defaultColor) -> nativeBackgroundColor`
    /// directly (alpha intact, no lossy Color-struct round trip), and (2) the
    /// view's own CALayer.backgroundColor, painted once in setupOptions()
    /// during init and NOT refreshed by the nativeBackgroundColor setter — so
    /// we refresh it here ourselves on every appearance change, plus force a
    /// redisplay since the setter doesn't request one either (unlike the
    /// `font` setter, which calls resetFont() -> needsDisplay = true).
    /// CALayer's default isOpaque is false, so an alpha < 1 here composites
    /// straight through to imageView underneath with no extra flag to flip.
    private func applyAppearance(_ settings: TerminalSettings) {
        terminalView.font = Self.resolvedFont(settings)

        let color = (NSColor(hex: settings.backgroundColorHex) ?? .black)
            .withAlphaComponent(settings.backgroundOpacity)
        terminalView.nativeBackgroundColor = color
        terminalView.layer?.backgroundColor = color.cgColor
        terminalView.needsDisplay = true

        updateBackgroundImage(path: settings.backgroundImagePath)
    }

    private func updateBackgroundImage(path: String?) {
        guard let path,
              let nsImage = NSImage(contentsOfFile: path),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            imageView.isHidden = true
            imageView.layer?.contents = nil
            return
        }
        // NSImageView.imageScaling has no true "fill and crop" option; the
        // layer's contentsGravity does (this is the standard AppKit trick
        // for aspect-fill), so drive the image through the layer directly.
        imageView.layer?.contentsGravity = .resizeAspectFill
        imageView.layer?.contents = cgImage
        imageView.isHidden = false
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
