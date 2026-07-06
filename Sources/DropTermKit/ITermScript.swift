import Foundation

/// Pure AppleScript source builders for the iTerm2 jump. Kept side-effect
/// free so escaping is unit-testable; execution lives in ITermJump.
public enum ITermScript {

    /// tmux mode: open iTerm2 attached to the shared session.
    public static func attachScript(tmuxPath: String) -> String {
        let command = "\(tmuxPath) attach -t \(SessionCommand.tmuxSessionName)"
        return """
        tell application "iTerm"
            activate
            create window with default profile command "\(applescriptEscaped(command))"
        end tell
        """
    }

    /// plain mode: open iTerm2 and cd to the given directory.
    public static func cdScript(directory: String) -> String {
        let command = "cd \(shellQuoted(directory))"
        return """
        tell application "iTerm"
            activate
            set newWindow to (create window with default profile)
            tell current session of newWindow
                write text "\(applescriptEscaped(command))"
            end tell
        end tell
        """
    }

    /// POSIX single-quote wrapping; embedded ' becomes '\'' .
    static func shellQuoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Escapes a Swift string for embedding inside an AppleScript "…" literal.
    static func applescriptEscaped(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
