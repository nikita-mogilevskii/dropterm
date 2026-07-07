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

    @Test func defaultsTo700x420() {
        let s = PanelSizeStore(defaults: freshDefaults())
        #expect(s.size == CGSize(width: 700, height: 420))
    }

    @Test func clampsBothBounds() {
        let s = PanelSizeStore(defaults: freshDefaults())
        s.set(CGSize(width: 100, height: 5000))
        #expect(s.size == CGSize(width: 480, height: 800))
        s.set(CGSize(width: 5000, height: 100))
        #expect(s.size == CGSize(width: 1200, height: 300))
    }

    @Test func persistsAcrossInstances() {
        let d = freshDefaults()
        PanelSizeStore(defaults: d).set(CGSize(width: 900, height: 500))
        #expect(PanelSizeStore(defaults: d).size == CGSize(width: 900, height: 500))
    }

    @Test func corruptDefaultsFallBackToDefaultSize() {
        let d = freshDefaults()
        d.set("garbage", forKey: "panelSize.v1")
        #expect(PanelSizeStore(defaults: d).size == CGSize(width: 700, height: 420))
    }

    @Test func outOfBoundsPersistedDictIsClampedOnLoad() {
        let d = freshDefaults()
        d.set(["w": 50.0, "h": 5000.0], forKey: "panelSize.v1")
        let s = PanelSizeStore(defaults: d)
        #expect(s.size == CGSize(width: 480, height: 800))
    }
}
