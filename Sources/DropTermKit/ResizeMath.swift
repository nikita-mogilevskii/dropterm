import CoreGraphics

/// Pure geometry for the panel resize path. Extracted so the math that
/// fixed the v1 screen-edge resize bug stays pinned by tests.
public enum ResizeMath {

    /// Bottom-right-corner drag with the panel's horizontal CENTER pinned:
    /// the right edge only moves half the mouse delta unless doubled, so
    /// width applies 2x the horizontal delta to keep the edge under the
    /// cursor. Height is top-pinned and grows downward 1:1 (screen coords,
    /// bottom-left origin: down = y decreasing).
    public static func centerPinnedResized(start: CGSize, mouseStart: CGPoint, mouseNow: CGPoint) -> CGSize {
        CGSize(width: start.width + 2 * (mouseNow.x - mouseStart.x),
               height: start.height + (mouseStart.y - mouseNow.y))
    }

    /// Spotlight-style frame: horizontally centered in `screenFrame`, top
    /// edge at 75% of the visible height (AppKit bottom-left origin).
    public static func spotlightFrame(size: CGSize, screenFrame: CGRect) -> CGRect {
        let top = screenFrame.minY + screenFrame.height * 0.75
        return CGRect(x: screenFrame.midX - size.width / 2,
                      y: top - size.height,
                      width: size.width,
                      height: size.height)
    }
}
