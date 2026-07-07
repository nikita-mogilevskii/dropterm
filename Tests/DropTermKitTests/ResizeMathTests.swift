import CoreGraphics
import Testing
@testable import DropTermKit

@Suite("ResizeMath")
struct ResizeMathTests {

    @Test func draggingRightGrowsWidth() {
        let s = ResizeMath.resized(start: CGSize(width: 700, height: 420),
                                   mouseStart: CGPoint(x: 100, y: 500),
                                   mouseNow: CGPoint(x: 160, y: 500))
        #expect(s == CGSize(width: 760, height: 420))
    }

    @Test func draggingDownGrowsHeight() {
        // Screen coords are bottom-left origin: down = y decreasing.
        let s = ResizeMath.resized(start: CGSize(width: 700, height: 420),
                                   mouseStart: CGPoint(x: 100, y: 500),
                                   mouseNow: CGPoint(x: 100, y: 440))
        #expect(s == CGSize(width: 700, height: 480))
    }

    @Test func draggingUpLeftShrinksBoth() {
        let s = ResizeMath.resized(start: CGSize(width: 700, height: 420),
                                   mouseStart: CGPoint(x: 100, y: 500),
                                   mouseNow: CGPoint(x: 60, y: 550))
        #expect(s == CGSize(width: 660, height: 370))
    }

    @Test func topRightStaysPinnedWhenGrowing() {
        let f = ResizeMath.topRightAnchored(oldFrame: CGRect(x: 500, y: 300, width: 700, height: 420),
                                            newSize: CGSize(width: 800, height: 500))
        #expect(f == CGRect(x: 400, y: 220, width: 800, height: 500))
        // top-right corner: (maxX, maxY) unchanged
        #expect(f.maxX == 1200)
        #expect(f.maxY == 720)
    }
}
