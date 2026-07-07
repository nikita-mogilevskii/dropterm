import CoreGraphics
import Testing
@testable import DropTermKit

@Suite("ResizeMath")
struct ResizeMathTests {

    @Test func draggingRightGrowsWidthDoubled() {
        #expect(ResizeMath.widthResized(startWidth: 700, mouseStartX: 100, mouseNowX: 160) == 820)
    }

    @Test func draggingLeftShrinksWidthDoubled() {
        #expect(ResizeMath.widthResized(startWidth: 700, mouseStartX: 100, mouseNowX: 80) == 660)
    }

    @Test func spotlightFrameCentersAtSpotlightHeightWithHalfScreenHeight() {
        let f = ResizeMath.spotlightFrame(width: 700,
                                          screenFrame: CGRect(x: 0, y: 0, width: 2000, height: 1200))
        #expect(f.midX == 1000)
        #expect(f.maxY == 900)              // top at 75%
        #expect(f.height == 600)            // half of 1200
        #expect(f.minY == 300)              // bottom lands at 25%
    }

    @Test func spotlightFrameRespectsScreenOrigin() {
        let f = ResizeMath.spotlightFrame(width: 600,
                                          screenFrame: CGRect(x: 1000, y: 500, width: 1000, height: 800))
        #expect(f.midX == 1500)
        #expect(f.maxY == 1100)             // 500 + 800*0.75
        #expect(f.height == 400)            // half of 800
    }
}
