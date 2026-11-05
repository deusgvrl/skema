import simd

public enum ColorConversion {
    /// Full-range BT.601 YCbCr (ARKit capturedImage, 420f) to RGB, clamped 0...255.
    public static func rgb(y: UInt8, cb: UInt8, cr: UInt8) -> SIMD3<UInt8> {
        let y = Float(y), cb = Float(cb) - 128, cr = Float(cr) - 128
        let c = SIMD3<Float>(y + 1.402 * cr, y - 0.344136 * cb - 0.714136 * cr, y + 1.772 * cb)
        return SIMD3<UInt8>(c.rounded(.toNearestOrAwayFromZero).clamped(lowerBound: .zero, upperBound: SIMD3(repeating: 255)), rounding: .towardZero)
    }
}
