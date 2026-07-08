import Foundation
import CoreGraphics
import AppKit
import SwiftUI

public struct TerminalSettings: Codable, Equatable {
    public enum ShellMode: Codable, Equatable {
        case automatic
        case custom(path: String)
    }

    public var shellMode: ShellMode = .automatic
    /// nil = SwiftTerm's default monospaced font.
    public var fontName: String? = nil
    /// Path to the .ttf/.otf a custom `fontName` was loaded from, so it can
    /// be re-registered with CTFontManager on next launch — registration is
    /// process-scoped and does not survive relaunch on its own.
    public var fontFilePath: String? = nil
    public var fontSize: CGFloat = 13
    public var backgroundColorHex: String = "#000000"
    public var backgroundOpacity: CGFloat = 1.0
    public var backgroundImagePath: String? = nil
    public enum BackdropStyle: String, Codable, Equatable {
        case color, image, glass
    }
    public var backdropStyle: BackdropStyle = .color
    public var dimInactive: Bool = true

    public init() {}

    /// Schema-tolerant decode: merge present keys onto defaults so a blob
    /// written by an older build (missing keys added in a later version)
    /// decodes to defaults for those keys instead of throwing keyNotFound.
    /// Without this, adding a non-Optional field would make JSONDecoder throw
    /// on every pre-existing "settings.v1" blob, SettingsStore's `try?` would
    /// treat it as corrupt, and persist() would silently wipe the user's
    /// saved shell/font/background. Encodable stays synthesized.
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try c.decodeIfPresent(ShellMode.self, forKey: .shellMode) { shellMode = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .fontName) { fontName = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .fontFilePath) { fontFilePath = v }
        if let v = try c.decodeIfPresent(CGFloat.self, forKey: .fontSize) { fontSize = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .backgroundColorHex) { backgroundColorHex = v }
        if let v = try c.decodeIfPresent(CGFloat.self, forKey: .backgroundOpacity) { backgroundOpacity = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .backgroundImagePath) { backgroundImagePath = v }
        if let v = try c.decodeIfPresent(BackdropStyle.self, forKey: .backdropStyle) { backdropStyle = v }
        if let v = try c.decodeIfPresent(Bool.self, forKey: .dimInactive) { dimInactive = v }
    }

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

/// SwiftUI bridge over the NSColor hex parser above — one parser, not two.
/// Used by PanelView's backdrop (spec amendment 15: color/image/opacity
/// style the whole panel card, not the terminal view).
public extension Color {
    /// `nil` on anything `NSColor(hex:)` can't parse; callers fall back to
    /// `.black` per the settings contract.
    init?(hex: String) {
        guard let ns = NSColor(hex: hex) else { return nil }
        self.init(nsColor: ns)
    }
}
