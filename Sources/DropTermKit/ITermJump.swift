import AppKit
import Foundation

/// Hands the session over to iTerm2. tmux mode: detach our client and let
/// iTerm2 attach to the same session (true transfer). plain mode: new
/// iTerm2 window at the shell's last-known directory (jobs stay behind).
public enum ITermJump {

    static let iTermBundleID = "com.googlecode.iterm2"

    public static var isITermInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: iTermBundleID) != nil
    }

    /// Returns nil on success, a short human-readable message on failure.
    public static func jump(session: TerminalSession) -> String? {
        let script: String
        switch session.mode {
        case .tmux(let path):
            detachOurClient(tmuxPath: path)
            script = ITermScript.attachScript(tmuxPath: path)
        case .plain:
            let dir = session.currentDirectory ?? NSHomeDirectory()
            script = ITermScript.cdScript(directory: dir)
        }
        return run(script)
    }

    /// Best-effort: detach every client on the dropterm session so iTerm2
    /// attaches at full size. Failure is fine (session may have no client).
    private static func detachOurClient(tmuxPath: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tmuxPath)
        p.arguments = ["detach-client", "-s", SessionCommand.tmuxSessionName]
        // waitUntilExit on an unlaunched Process raises an ObjC exception —
        // only wait if the launch actually succeeded.
        guard (try? p.run()) != nil else { return }
        p.waitUntilExit()
    }

    private static func run(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else {
            return "Could not build AppleScript"
        }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            let message = (error[NSAppleScript.errorBriefMessage] as? String)
                ?? (error[NSAppleScript.errorMessage] as? String)
                ?? "AppleScript error"
            NSLog("DropTerm: iTerm2 jump failed: %@", message)
            return message
        }
        return nil
    }
}
