import Foundation
import CoreGraphics
import AppKit

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

/// Shared by SwiftTermSurface (render the setting) and SettingsView (edit
/// it via ColorPicker) — one hex<->NSColor conversion, not two.
public extension NSColor {
    /// Parses "#RRGGBB" (case-insensitive, leading # optional). `nil` on
    /// anything else — per the settings contract, callers fall back to black.
    convenience init?(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255.0,
                  green: CGFloat((value >> 8) & 0xFF) / 255.0,
                  blue: CGFloat(value & 0xFF) / 255.0,
                  alpha: 1.0)
    }

    /// "#RRGGBB" round-trip for persistence/UI. Alpha is dropped —
    /// `TerminalSettings.backgroundOpacity` tracks that separately.
    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
