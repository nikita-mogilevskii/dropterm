import CoreGraphics
import Foundation
import Testing
@testable import DropTermKit

@Suite("SettingsStore", .serialized)
struct TerminalSettingsTests {

    static let suiteName = "DropTermSettingsTests"

    func freshDefaults() -> UserDefaults {
        let d = UserDefaults(suiteName: Self.suiteName)!
        d.removePersistentDomain(forName: Self.suiteName)
        return d
    }

    @Test func defaultsAreSane() {
        let s = SettingsStore(defaults: freshDefaults()).settings
        #expect(s == TerminalSettings())
        #expect(s.shellMode == .automatic)
        #expect(s.fontSize == 13)
        #expect(s.backgroundColorHex == "#000000")
    }

    @Test func roundTripsAllFields() {
        let d = freshDefaults()
        let a = SettingsStore(defaults: d)
        var s = a.settings
        s.shellMode = .custom(path: "/opt/homebrew/bin/fish")
        s.fontName = "JetBrains Mono"
        s.fontSize = 16
        s.backgroundColorHex = "#1A1B26"
        s.backgroundOpacity = 0.85
        s.backgroundImagePath = "/tmp/bg.png"
        a.settings = s
        #expect(SettingsStore(defaults: d).settings == s)
    }

    @Test func corruptBlobFallsBackToDefaultsAndSelfHeals() {
        let d = freshDefaults()
        d.set(Data("junk".utf8), forKey: "settings.v1")
        #expect(SettingsStore(defaults: d).settings == TerminalSettings())
        let healed = d.data(forKey: "settings.v1")
            .flatMap { try? JSONDecoder().decode(TerminalSettings.self, from: $0) }
        #expect(healed == TerminalSettings())
    }

    @Test func loadClampsOutOfRangeValues() {
        let d = freshDefaults()
        var s = TerminalSettings()
        s.fontSize = 100
        s.backgroundOpacity = 0.0
        d.set(try! JSONEncoder().encode(s), forKey: "settings.v1")
        let loaded = SettingsStore(defaults: d).settings
        #expect(loaded.fontSize == 28)
        #expect(loaded.backgroundOpacity == 0.1)
    }

    @Test func bumpFontSizeClampsBothEnds() {
        let store = SettingsStore(defaults: freshDefaults())
        store.bumpFontSize(100)
        #expect(store.settings.fontSize == 28)
        store.bumpFontSize(-100)
        #expect(store.settings.fontSize == 8)
        store.bumpFontSize(1)
        #expect(store.settings.fontSize == 9)
    }
}
