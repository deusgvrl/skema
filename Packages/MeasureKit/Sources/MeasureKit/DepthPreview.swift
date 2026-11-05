/// LiDAR preview dots for the camera view: the same depth data the measurements use.
public struct PreviewDot: Equatable, Sendable {
    public let u: Float      // normalized native-image x (0 left ... 1 right), pixel centre
    public let v: Float      // normalized native-image y (0 top ... 1 bottom), pixel centre
    public let depth: Float  // metres
}

public enum DepthPreview {
    /// Every `stride`-th depth pixel in both directions (starting at 0), confidence >= minConfidence,
    /// finite positive depth.
    public static func dots(from depth: DepthFrame, stride: Int = 4, minConfidence: UInt8 = 2) -> [PreviewDot] {
        guard stride > 0, depth.width > 0, depth.height > 0,
              depth.depth.count == depth.width * depth.height,
              depth.confidence.count == depth.depth.count else { return [] }
        var dots: [PreviewDot] = []
        for j in Swift.stride(from: 0, to: depth.height, by: stride) {
            for i in Swift.stride(from: 0, to: depth.width, by: stride) {
                let idx = j * depth.width + i
                let d = depth.depth[idx]
                guard depth.confidence[idx] >= minConfidence, d.isFinite, d > 0 else { continue }
                dots.append(PreviewDot(u: (Float(i) + 0.5) / Float(depth.width),
                                       v: (Float(j) + 0.5) / Float(depth.height), depth: d))
            }
        }
        return dots
    }

    /// 0 at `near`, 1 at `far`, clamped to 0...1 (for colouring near warm, far cool).
    public static func colorPosition(depth: Float, near: Float = 0.3, far: Float = 4) -> Float {
        guard far > near else { return 0 }
        return min(1, max(0, (depth - near) / (far - near)))
    }
}
