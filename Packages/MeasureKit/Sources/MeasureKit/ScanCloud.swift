import simd

/// The room scan: world points thinned to one per voxel, so memory stays bounded while it builds up.
public struct ScanCloud: Sendable {
    public static let voxelSize: Float = 0.01        // metres
    public static let maxPoints = 600_000

    private let capacity: Int
    private var voxels: Set<SIMD3<Int32>> = []
    private var points: [(world: SIMD3<Float>, rgb: SIMD3<UInt8>)] = []

    public init() { capacity = Self.maxPoints }
    init(maxPoints: Int) { capacity = maxPoints }

    public var count: Int { points.count }
    public var allPoints: [(world: SIMD3<Float>, rgb: SIMD3<UInt8>)] { points }

    /// Adds points whose voxel is still empty (first point wins). Stops adding at maxPoints.
    /// Returns the points actually added this call (the app renders them as a new chunk).
    public mutating func add(_ new: [(world: SIMD3<Float>, rgb: SIMD3<UInt8>)]) -> [(world: SIMD3<Float>, rgb: SIMD3<UInt8>)] {
        var added: [(world: SIMD3<Float>, rgb: SIMD3<UInt8>)] = []
        for p in new {
            guard points.count < capacity else { break }
            let cell = SIMD3<Int32>((p.world / Self.voxelSize).rounded(.down), rounding: .towardZero)
            if voxels.insert(cell).inserted {
                points.append(p)
                added.append(p)
            }
        }
        return added
    }

    public mutating func removeAll() {
        voxels.removeAll()
        points.removeAll()
    }
}
