import AppKit

/// One live terminal: an NSView to host plus the process behind it.
public protocol TerminalSurface: AnyObject {
    var view: NSView { get }
    /// The interactive view that should receive keyboard focus. Defaults to
    /// `view` via the extension below; a surface that wraps its real
    /// interactive view in a non-key-handling container overrides this to
    /// point at the actual key-event target, so TerminalHostView never hands
    /// first responder to a plain, non-interactive container view.
    var focusView: NSView { get }
    /// Best-effort shell cwd (OSC 7 updates when the shell emits them).
    var currentDirectory: String? { get }
    func terminateProcess()
    /// Live-apply appearance settings (font, background). Defaults to a
    /// no-op via the extension below so existing fakes/tests need no changes.
    func apply(settings: TerminalSettings)
}

public extension TerminalSurface {
    var focusView: NSView { view }
    func apply(settings: TerminalSettings) {}
}

/// Creates surfaces. The real factory wraps SwiftTerm (Task 5);
/// tests inject a fake to drive the state machine without ptys.
public protocol TerminalSurfaceFactory {
    func makeSurface(command: ResolvedCommand,
                     directory: String,
                     onProcessExit: @escaping (Int32?) -> Void) throws -> TerminalSurface
}
