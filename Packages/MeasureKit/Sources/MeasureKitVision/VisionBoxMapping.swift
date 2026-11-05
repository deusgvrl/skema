import CoreGraphics
import MeasureKit

public enum VisionBoxMapping {
    /// Vision's `boundingBox` (normalized, origin bottom-left, in the ORIENTED image)
    /// to a `NormalizedBox` in the NATIVE image (origin top-left).
    ///
    /// Orientation meaning (Apple, ImageIO `CGImagePropertyOrientation`):
    /// - `.right`: "The encoded image data is rotated 90° counter-clockwise from the image's intended display orientation."
    /// - `.left`: "The encoded image data is rotated 90° clockwise from the image's intended display orientation."
    /// - `.down`: "The encoded image data is rotated 180° from the image's intended display orientation."
    public static func nativeBox(fromVision rect: CGRect, orientation: ImageOrientation) -> NormalizedBox {
        // Oriented image, origin top-left.
        let ox = Double(rect.minX)
        let w = Double(rect.width)
        let h = Double(rect.height)
        let oy = 1 - Double(rect.minY) - h
        switch orientation {
        case .up:
            return NormalizedBox(x: ox, y: oy, width: w, height: h)
        case .right: // nx = oy, ny = 1 - ox
            return NormalizedBox(x: oy, y: 1 - ox - w, width: h, height: w)
        case .left: // nx = 1 - oy, ny = ox
            return NormalizedBox(x: 1 - oy - h, y: ox, width: h, height: w)
        case .down: // nx = 1 - ox, ny = 1 - oy
            return NormalizedBox(x: 1 - ox - w, y: 1 - oy - h, width: w, height: h)
        }
    }
}
