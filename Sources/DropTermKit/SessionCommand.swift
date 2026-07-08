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

    /// tmux session name for tile `index` (0-based). Tile 0 keeps the
    /// canonical "dropterm" (so a lone tile matches what a manual
    /// `tmux attach -t dropterm` expects); further tiles get suffixed
    /// names so they don't mirror each other.
    public static func tmuxSessionName(forTile index: Int) -> String {
        index == 0 ? tmuxSessionName : "\(tmuxSessionName)-\(index + 1)"
    }

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

    /// Settings-aware resolution: a custom command bypasses tmux/login
    /// resolution entirely and runs the given binary with no args.
    public static func resolve(
        settings: TerminalSettings,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        shell: String? = ProcessInfo.processInfo.environment["SHELL"]
    ) -> (mode: SessionMode, command: ResolvedCommand) {
        if case .custom(let path) = settings.shellMode {
            return (.plain(shell: path), ResolvedCommand(exec: path, args: []))
        }
        return resolve(fileExists: fileExists, shell: shell)
    }

    /// Settings + tile-aware resolution. Custom shell mode bypasses tmux
    /// (every tile runs the same custom binary, no session naming). In
    /// automatic mode, tmux tiles get a per-tile session name.
    public static func resolve(
        settings: TerminalSettings,
        tileIndex: Int,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        shell: String? = ProcessInfo.processInfo.environment["SHELL"]
    ) -> (mode: SessionMode, command: ResolvedCommand) {
        if case .custom(let path) = settings.shellMode {
            return (.plain(shell: path), ResolvedCommand(exec: path, args: []))
        }
        if let tmux = tmuxLocations.first(where: fileExists) {
            return (.tmux(path: tmux),
                    ResolvedCommand(exec: tmux,
                                    args: ["new-session", "-A", "-s", tmuxSessionName(forTile: tileIndex)]))
        }
        let loginShell = shell ?? "/bin/zsh"
        return (.plain(shell: loginShell), ResolvedCommand(exec: loginShell, args: ["-l"]))
    }
}
