import Foundation

public struct ResolvedCommand: Equatable {
    public let exec: String
    public let args: [String]

    public init(exec: String, args: [String]) {
        self.exec = exec
        self.args = args
    }
}

public enum SessionMode: Equatable {
    case tmux(path: String)
    case plain(shell: String)
}

/// Resolves what the terminal should run: an attach-or-create tmux session
/// when tmux is installed (enables true iTerm2 handoff and survival across
/// app restarts), the user's login shell otherwise.
public enum SessionCommand {
    public static let tmuxSessionName = "dropterm"

    static let tmuxLocations = [
        "/opt/homebrew/bin/tmux",
        "/usr/local/bin/tmux",
        "/usr/bin/tmux",
    ]

    public static func resolve(
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        shell: String? = ProcessInfo.processInfo.environment["SHELL"]
    ) -> (mode: SessionMode, command: ResolvedCommand) {
        if let tmux = tmuxLocations.first(where: fileExists) {
            return (.tmux(path: tmux),
                    ResolvedCommand(exec: tmux,
                                    args: ["new-session", "-A", "-s", tmuxSessionName]))
        }
        let loginShell = shell ?? "/bin/zsh"
        return (.plain(shell: loginShell),
                ResolvedCommand(exec: loginShell, args: ["-l"]))
    }
}
