import Testing
@testable import DropTermKit

@Suite("ITermScript")
struct ITermScriptTests {

    @Test func attachScriptTargetsSession() {
        let s = ITermScript.attachScript(tmuxPath: "/opt/homebrew/bin/tmux")
        #expect(s.contains("tell application \"iTerm\""))
        #expect(s.contains("create window with default profile command \"/opt/homebrew/bin/tmux attach -t dropterm\""))
        #expect(s.contains("activate"))
    }

    @Test func cdScriptQuotesPlainPath() {
        let s = ITermScript.cdScript(directory: "/Users/nikita/projects")
        #expect(s.contains("write text \"cd '/Users/nikita/projects'\""))
    }

    @Test func cdScriptEscapesSpacesViaSingleQuotes() {
        let s = ITermScript.cdScript(directory: "/Users/nikita/My Stuff")
        #expect(s.contains("write text \"cd '/Users/nikita/My Stuff'\""))
    }

    @Test func cdScriptSurvivesSingleQuoteInPath() {
        // shell-quoting: ' closes, \' escapes, ' reopens
        let s = ITermScript.cdScript(directory: "/tmp/it's here")
        #expect(s.contains("cd '/tmp/it'\\\\''s here'"))
    }

    @Test func applescriptEscapingHandlesQuotesAndBackslashes() {
        #expect(ITermScript.applescriptEscaped(#"say "hi" \now"#) == #"say \"hi\" \\now"#)
    }
}
