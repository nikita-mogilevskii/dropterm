import AppKit
import SwiftTerm

/// Real factory: SwiftTerm's LocalProcessTerminalView running the resolved
/// command on a pty.
public final class SwiftTermSurfaceFactory: TerminalSurfaceFactory {
    public init() {}

    public func makeSurface(command: ResolvedCommand,
                            directory: String,
                            onProcessExit: @escaping (Int32?) -> Void) throws -> TerminalSurface {
        SwiftTermSurface(command: command, directory: directory, onProcessExit: onProcessExit)
    }
}

final class SwiftTermSurface: NSObject, TerminalSurface, LocalProcessTerminalViewDelegate {

    private let terminalView: LocalProcessTerminalView
    private let onProcessExit: (Int32?) -> Void
    private(set) var lastReportedDirectory: String?

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
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let out = String(data: data, encoding: .utf8) else { return nil }
        // Output lines: "p<pid>", "fcwd", "n/actual/path"
        return out.split(separator: "\n")
            .first { $0.hasPrefix("n") }
            .map { String($0.dropFirst()) }
    }

    init(command: ResolvedCommand, directory: String, onProcessExit: @escaping (Int32?) -> Void) {
        self.onProcessExit = onProcessExit
        self.terminalView = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 700, height: 400))
        super.init()

        terminalView.processDelegate = self
        terminalView.nativeBackgroundColor = .black
        terminalView.nativeForegroundColor = .white

        var environment = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        environment.append("LANG=en_US.UTF-8")

        // LocalProcessTerminalView.startProcess takes currentDirectory directly
        // (forwarded to LocalProcess -> PseudoTerminalHelpers.fork, which chdirs
        // in the forked child before exec) — no need to mutate the app's cwd.
        terminalView.startProcess(executable: command.exec,
                                  args: command.args,
                                  environment: environment,
                                  currentDirectory: directory)
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
