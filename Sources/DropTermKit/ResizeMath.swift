import CoreGraphics

/// Pure geometry for the panel's Spotlight-style placement and resize.
public enum ResizeMath {

    /// Fraction of the screen's visible height the panel always occupies.
    public static let heightFraction: CGFloat = 0.5
    /// Fraction of the visible height where the panel's TOP edge sits.
    public static let topFraction: CGFloat = 0.75

    /// Corner drag with the panel's horizontal center pinned: width applies
    /// 2x the horizontal mouse delta so the edge keeps tracking the cursor.
    /// Height is fixed (see spotlightFrame) — the drag only changes width.
    public static func widthResized(startWidth: CGFloat, mouseStartX: CGFloat, mouseNowX: CGFloat) -> CGFloat {
        startWidth + 2 * (mouseNowX - mouseStartX)
    }

    /// Spotlight-style frame: horizontally centered, top edge at 75% of the
    /// visible height, height fixed at half the visible height.
    public static func spotlightFrame(width: CGFloat, screenFrame: CGRect) -> CGRect {
        let height = screenFrame.height * heightFraction
        let top = screenFrame.minY + screenFrame.height * topFraction
        return CGRect(x: screenFrame.midX - width / 2,
                      y: top - height,
                      width: width,
                      height: height)
    }
}
