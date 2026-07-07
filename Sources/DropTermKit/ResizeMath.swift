import CoreGraphics

/// Pure geometry for the panel resize path. Extracted so the math that
/// fixed the v1 screen-edge resize bug stays pinned by tests.
public enum ResizeMath {

    /// Bottom-right-corner drag in SCREEN coordinates (AppKit bottom-left
    /// origin): dragging right grows width; dragging DOWN (y decreasing)
    /// grows height.
    public static func resized(start: CGSize, mouseStart: CGPoint, mouseNow: CGPoint) -> CGSize {
        CGSize(width: start.width + (mouseNow.x - mouseStart.x),
               height: start.height + (mouseStart.y - mouseNow.y))
    }

    /// New frame keeping the TOP-RIGHT corner of `oldFrame` fixed.
    public static func topRightAnchored(oldFrame: CGRect, newSize: CGSize) -> CGRect {
        CGRect(x: oldFrame.maxX - newSize.width,
               y: oldFrame.maxY - newSize.height,
               width: newSize.width,
               height: newSize.height)
    }
}
