import AppKit

/// One live terminal: an NSView to host plus the process behind it.
public protocol TerminalSurface: AnyObject {
    var view: NSView { get }
    /// Best-effort shell cwd (OSC 7 updates when the shell emits them).
    var currentDirectory: String? { get }
    func terminateProcess()
}

/// Creates surfaces. The real factory wraps SwiftTerm (Task 5);
/// tests inject a fake to drive the state machine without ptys.
public protocol TerminalSurfaceFactory {
    func makeSurface(command: ResolvedCommand,
                     directory: String,
                     onProcessExit: @escaping (Int32?) -> Void) throws -> TerminalSurface
}
