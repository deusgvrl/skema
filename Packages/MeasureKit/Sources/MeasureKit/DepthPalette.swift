import simd

public enum DepthPalette {
    private static let stops: [SIMD3<Float>] = [SIMD3(255, 0, 0), SIMD3(255, 255, 0), SIMD3(0, 255, 0), SIMD3(0, 0, 255)]

    /// DepthEye-like depth colours: position 0 (near) red, 1/3 yellow, 2/3 green, 1 (far) blue, linear between stops.
    /// Positions outside 0...1 are clamped.
    public static func rgb(_ position: Float) -> SIMD3<UInt8> {
        let t = min(1, max(0, position.isNaN ? 0 : position)) * 3
        let k = min(2, Int(t))
        let c = stops[k] + (stops[k + 1] - stops[k]) * (t - Float(k))
        return SIMD3<UInt8>(c.rounded(.toNearestOrEven).clamped(lowerBound: .zero, upperBound: SIMD3(repeating: 255)), rounding: .towardZero)
    }
}
