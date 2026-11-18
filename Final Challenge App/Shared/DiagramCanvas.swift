import CoreGraphics

/// The canvas the PDF diagram is drawn on (A10-98). It is big enough for every item, so nothing is cut off;
/// the PDF then scales the picture down into its box, and the 1 m scale bar shrinks with it.
enum DiagramCanvas {
    /// Room around the farthest item for its icon and its name.
    static let itemPadding: CGFloat = 70

    /// Grows `base` (keeping its shape) until every item fits around the centre. Never smaller than `base`.
    /// - Parameter offsets: each item's position relative to the subject, in diagram points.
    static func size(fitting offsets: [CGPoint], base: CGSize) -> CGSize {
        let halfWidthNeeded = (offsets.map { abs($0.x) }.max() ?? 0) + itemPadding
        let halfHeightNeeded = (offsets.map { abs($0.y) }.max() ?? 0) + itemPadding
        let scale = max(1, 2 * halfWidthNeeded / base.width, 2 * halfHeightNeeded / base.height)
        return CGSize(width: base.width * scale, height: base.height * scale)
    }
}
