import Foundation
import CoreGraphics

public struct TerminalSettings: Codable, Equatable {
    public enum ShellMode: Codable, Equatable {
        case automatic
        case custom(path: String)
    }

    public var shellMode: ShellMode = .automatic
    /// nil = SwiftTerm's default monospaced font.
    public var fontName: String? = nil
    public var fontSize: CGFloat = 13
    public var backgroundColorHex: String = "#000000"
    public var backgroundOpacity: CGFloat = 1.0
    public var backgroundImagePath: String? = nil

    public init() {}

    public static let minFontSize: CGFloat = 8
    public static let maxFontSize: CGFloat = 28
}

/// Observable persistence for TerminalSettings (UserDefaults JSON blob).
public final class SettingsStore: ObservableObject {
    private static let key = "settings.v1"

    @Published public var settings: TerminalSettings {
        didSet { persist() }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(TerminalSettings.self, from: data) {
            var s = decoded
            s.fontSize = min(max(s.fontSize, TerminalSettings.minFontSize), TerminalSettings.maxFontSize)
            s.backgroundOpacity = min(max(s.backgroundOpacity, 0.1), 1.0)
            self.settings = s
        } else {
            self.settings = TerminalSettings()
        }
        persist()   // self-heal corrupt blobs (didSet does not fire in init)
    }

    /// Ctrl+= / Ctrl+- entry point: ±1pt, clamped.
    public func bumpFontSize(_ delta: CGFloat) {
        var s = settings
        s.fontSize = min(max(s.fontSize + delta, TerminalSettings.minFontSize), TerminalSettings.maxFontSize)
        settings = s
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
