import Foundation
import CoreGraphics

/// Panel width: clamped, observable, persisted. Height is not stored —
/// it is always derived from the screen (ResizeMath.spotlightFrame).
public final class PanelSizeStore: ObservableObject {

    public static let defaultWidth: CGFloat = 700
    public static let minWidth: CGFloat = 480
    public static let maxWidth: CGFloat = 1200
    private static let key = "panelWidth.v2"

    @Published public private(set) var width: CGFloat

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.double(forKey: Self.key)
        self.width = stored > 0 ? Self.clamped(stored) : Self.defaultWidth
    }

    public func set(width new: CGFloat) {
        width = Self.clamped(new)
        defaults.set(Double(width), forKey: Self.key)
    }

    private static func clamped(_ w: CGFloat) -> CGFloat {
        min(max(w, minWidth), maxWidth)
    }
}
