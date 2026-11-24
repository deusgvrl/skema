import Foundation
import simd

/// How far around an item the phone has seen it, seen from above: the widest angle between the spots it was seen from.
/// Scan screen phase 3 (team decision, 24 Nov 2026): an item is done only once seen from two spots at least 45° apart,
/// so standing in one place and tapping everything never counts as a scan.
public struct ViewSpread: Equatable, Sendable {
    /// The spread an item needs to be done.
    public static let doneDegrees: Float = 45
    /// A frame counts as a view of an item only if it gave the item at least this many points.
    public static let minFramePoints = 20
    /// A spot closer than this to the item, seen from above, is ignored: straight above it the angle means nothing.
    public static let minDistance: Float = 0.2

    /// The angle of the first spot, around the item; the others are measured from it.
    private var first: Float?
    /// The lowest and highest angle seen, relative to the first spot, in radians (-π…π).
    private var low: Float = 0
    private var high: Float = 0

    public init() {}

    /// Adds the spot `camera` the item at `item` was seen from (world points; only x and z count).
    public mutating func add(from camera: SIMD3<Float>, around item: SIMD3<Float>) {
        let offset = SIMD2(camera.x - item.x, camera.z - item.z)
        guard simd_length(offset) >= Self.minDistance else { return }
        let angle = atan2(offset.y, offset.x)
        guard let first else {
            self.first = angle
            return
        }
        // The shortest way round from the first spot, so walking past the back counts as a small step.
        let relative = Float(remainder(Double(angle - first), 2 * .pi))
        low = min(low, relative)
        high = max(high, relative)
    }

    /// The spread in degrees: 0 until there are two spots apart.
    public var degrees: Float {
        (high - low) * 180 / .pi
    }

    /// Seen from far enough around (`doneDegrees`).
    public var isEnough: Bool {
        degrees >= Self.doneDegrees - 1e-3
    }
}
