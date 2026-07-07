import CoreGraphics
import Testing
@testable import DropTermKit

@Suite("ResizeMath")
struct ResizeMathTests {

    @Test func draggingRightGrowsWidthDoubled() {
        let s = ResizeMath.centerPinnedResized(start: CGSize(width: 700, height: 420),
                                               mouseStart: CGPoint(x: 100, y: 500),
                                               mouseNow: CGPoint(x: 160, y: 500))
        #expect(s == CGSize(width: 820, height: 420))
    }

    @Test func draggingDownGrowsHeight() {
        let s = ResizeMath.centerPinnedResized(start: CGSize(width: 700, height: 420),
                                               mouseStart: CGPoint(x: 100, y: 500),
                                               mouseNow: CGPoint(x: 100, y: 440))
        #expect(s == CGSize(width: 700, height: 480))
    }

    @Test func draggingUpLeftShrinksBoth() {
        let s = ResizeMath.centerPinnedResized(start: CGSize(width: 700, height: 420),
                                               mouseStart: CGPoint(x: 100, y: 500),
                                               mouseNow: CGPoint(x: 80, y: 550))
        #expect(s == CGSize(width: 660, height: 370))
    }

    @Test func spotlightFrameCentersHorizontallyAtSpotlightHeight() {
        let f = ResizeMath.spotlightFrame(size: CGSize(width: 700, height: 420),
                                          screenFrame: CGRect(x: 0, y: 0, width: 2000, height: 1200))
        #expect(f.midX == 1000)                 // horizontal center
        #expect(f.maxY == 900)                  // top at 75% of height
        #expect(f.size == CGSize(width: 700, height: 420))
    }

    @Test func spotlightFrameRespectsScreenOrigin() {
        // secondary display with offset origin
        let f = ResizeMath.spotlightFrame(size: CGSize(width: 600, height: 400),
                                          screenFrame: CGRect(x: 1000, y: 500, width: 1000, height: 800))
        #expect(f.midX == 1500)
        #expect(f.maxY == 1100)                 // 500 + 800*0.75
    }
}
