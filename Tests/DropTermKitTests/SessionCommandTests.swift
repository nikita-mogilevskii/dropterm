import Foundation
import Testing
@testable import DropTermKit

@Suite("SessionCommand")
struct SessionCommandTests {

    @Test func picksHomebrewTmuxFirst() {
        let r = SessionCommand.resolve(
            fileExists: { $0 == "/opt/homebrew/bin/tmux" || $0 == "/usr/bin/tmux" },
            shell: "/bin/zsh")
        #expect(r.mode == .tmux(path: "/opt/homebrew/bin/tmux"))
        #expect(r.command == ResolvedCommand(exec: "/opt/homebrew/bin/tmux",
                                             args: ["new-session", "-A", "-s", "dropterm"]))
    }

    @Test func fallsThroughTmuxLocations() {
        let r = SessionCommand.resolve(fileExists: { $0 == "/usr/local/bin/tmux" },
                                       shell: "/bin/zsh")
        #expect(r.mode == .tmux(path: "/usr/local/bin/tmux"))
    }

    @Test func noTmuxMeansLoginShell() {
        let r = SessionCommand.resolve(fileExists: { _ in false }, shell: "/opt/homebrew/bin/fish")
        #expect(r.mode == .plain(shell: "/opt/homebrew/bin/fish"))
        #expect(r.command == ResolvedCommand(exec: "/opt/homebrew/bin/fish", args: ["-l"]))
    }

    @Test func missingShellEnvFallsBackToZsh() {
        let r = SessionCommand.resolve(fileExists: { _ in false }, shell: nil)
        #expect(r.command == ResolvedCommand(exec: "/bin/zsh", args: ["-l"]))
    }

    @Test func customShellModeBypassesTmux() {
        var settings = TerminalSettings()
        settings.shellMode = .custom(path: "/opt/homebrew/bin/nu")
        let r = SessionCommand.resolve(settings: settings,
                                       fileExists: { _ in true },   // tmux "installed"
                                       shell: "/bin/zsh")
        #expect(r.mode == .plain(shell: "/opt/homebrew/bin/nu"))
        #expect(r.command == ResolvedCommand(exec: "/opt/homebrew/bin/nu", args: []))
    }

    @Test func automaticSettingsModeDelegatesToExistingResolution() {
        let r = SessionCommand.resolve(settings: TerminalSettings(),
                                       fileExists: { $0 == "/usr/bin/tmux" },
                                       shell: "/bin/zsh")
        #expect(r.mode == .tmux(path: "/usr/bin/tmux"))
    }
}
