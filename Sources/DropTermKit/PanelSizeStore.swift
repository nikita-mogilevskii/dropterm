import Foundation
import CoreGraphics

/// Panel dimensions: clamped, observable, persisted. The resize handle
/// writes here; the panel frame reads here.
public final class PanelSizeStore: ObservableObject {

    public static let defaultSize = CGSize(width: 700, height: 420)
    public static let minSize = CGSize(width: 480, height: 300)
    public static let maxSize = CGSize(width: 1200, height: 800)
    private static let key = "panelSize.v1"

    @Published public private(set) var size: CGSize

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let dict = defaults.dictionary(forKey: Self.key),
           let w = dict["w"] as? Double,
           let h = dict["h"] as? Double {
            self.size = Self.clamped(CGSize(width: w, height: h))
        } else {
            self.size = Self.defaultSize
        }
    }

    public func set(_ new: CGSize) {
        size = Self.clamped(new)
        defaults.set(["w": size.width, "h": size.height], forKey: Self.key)
    }

    private static func clamped(_ s: CGSize) -> CGSize {
        CGSize(width: min(max(s.width, minSize.width), maxSize.width),
               height: min(max(s.height, minSize.height), maxSize.height))
    }
}
