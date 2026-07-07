import CoreGraphics
import Foundation
import Testing
@testable import DropTermKit

@Suite("PanelSizeStore", .serialized)
struct PanelSizeStoreTests {

    static let suiteName = "DropTermSizeTests"

    func freshDefaults() -> UserDefaults {
        let d = UserDefaults(suiteName: Self.suiteName)!
        d.removePersistentDomain(forName: Self.suiteName)
        return d
    }

    @Test func defaultsTo700() {
        #expect(PanelSizeStore(defaults: freshDefaults()).width == 700)
    }

    @Test func clampsBothBounds() {
        let s = PanelSizeStore(defaults: freshDefaults())
        s.set(width: 100)
        #expect(s.width == 480)
        s.set(width: 5000)
        #expect(s.width == 1200)
    }

    @Test func persistsAcrossInstances() {
        let d = freshDefaults()
        PanelSizeStore(defaults: d).set(width: 900)
        #expect(PanelSizeStore(defaults: d).width == 900)
    }

    @Test func outOfBoundsPersistedWidthClampedOnLoad() {
        let d = freshDefaults()
        d.set(50.0, forKey: "panelWidth.v2")
        #expect(PanelSizeStore(defaults: d).width == 480)
    }

    @Test func corruptOrMissingDefaultsFallBack() {
        let d = freshDefaults()
        d.set("garbage", forKey: "panelWidth.v2")
        #expect(PanelSizeStore(defaults: d).width == 700)
    }
}
