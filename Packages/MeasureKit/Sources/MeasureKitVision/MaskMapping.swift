import MeasureKit

public enum MaskMapping {
    /// Rotates a mask from the ORIENTED image (as Vision returns it, origin top-left in the pixel buffer
    /// Vision gives) into the NATIVE image frame, using the same orientation meaning as VisionBoxMapping.
    ///
    /// Oriented pixel (ox, oy) in a W x H oriented mask lands at native pixel:
    /// - .up:    (ox, oy)
    /// - .right: (oy, W - 1 - ox)      native is H x W
    /// - .left:  (H - 1 - oy, ox)      native is H x W
    /// - .down:  (W - 1 - ox, H - 1 - oy)
    public static func nativeMask(_ oriented: InstanceMask, orientation: ImageOrientation) -> InstanceMask {
        let w = oriented.width, h = oriented.height
        let swaps = orientation == .left || orientation == .right
        let nw = swaps ? h : w, nh = swaps ? w : h
        var out = [UInt8](repeating: 0, count: nw * nh)
        for oy in 0..<h {
            for ox in 0..<w {
                let v = oriented.pixels[oy * w + ox]
                guard v != 0 else { continue }
                let (x, y): (Int, Int)
                switch orientation {
                case .up: (x, y) = (ox, oy)
                case .right: (x, y) = (oy, w - 1 - ox)
                case .left: (x, y) = (h - 1 - oy, ox)
                case .down: (x, y) = (w - 1 - ox, h - 1 - oy)
                }
                out[y * nw + x] = v
            }
        }
        return InstanceMask(width: nw, height: nh, pixels: out)
    }

    /// Bounds of the non-zero pixels as a NormalizedBox (native, top-left). Nil when the mask is empty.
    public static func bounds(of mask: InstanceMask) -> NormalizedBox? {
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in 0..<mask.height {
            for x in 0..<mask.width where mask.pixels[y * mask.width + x] != 0 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        let w = Double(mask.width), h = Double(mask.height)
        return NormalizedBox(x: Double(minX) / w, y: Double(minY) / h,
                             width: Double(maxX + 1 - minX) / w, height: Double(maxY + 1 - minY) / h)
    }
}
