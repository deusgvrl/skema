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

/// The 3D points of one piece of equipment, merged over many frames while the user walks around.
public struct EquipmentPoints: Sendable {
    /// World points, at most one per 1 cm cell.
    public private(set) var points: [SIMD3<Float>] = []
    /// True when a frame showed the equipment only farther than `DepthSampler.maxRange`.
    /// `scanResult(floorY:isSubject:)` uses it to decide "out of range".
    public private(set) var sawPointsBeyondRange = false

    /// The 1 cm cells that already hold a point, so the same spot seen in many frames is stored once.
    private var voxels: Set<SIMD3<Int32>> = []

    public init() {}

    /// Adds the equipment's points from one frame: its mask when it has one, else its box.
    /// Only points within `DepthSampler.maxRange` are kept, and a cell that already has a point is skipped.
    public mutating func add(box: NormalizedBox, mask: InstanceMask?, depth: DepthFrame, camera: CameraModel) {
        let limit = DepthSampler.maxRange
        let inRange = Self.worldPoints(box: box, mask: mask, depth: depth, camera: camera, maxRange: limit)
        guard !inRange.isEmpty else {
            // Nothing within range. Look again without the limit: points farther away mean the equipment
            // was seen but too far; no points at all mean nothing usable was seen (low confidence, empty region).
            let anyDistance = Self.worldPoints(box: box, mask: mask, depth: depth, camera: camera, maxRange: .infinity)
            if !anyDistance.isEmpty { sawPointsBeyondRange = true }
            return
        }
        for point in inRange {
            // Same cell rule as `ScanCloud`: the cell is the point's position divided by the cell size, rounded down.
            let cell = SIMD3<Int32>((point / ScanCloud.voxelSize).rounded(.down), rounding: .towardZero)
            if voxels.insert(cell).inserted { points.append(point) }
        }
    }

    /// The centres of this equipment from everything collected over the scan, with `outOfRange` decided.
    ///
    /// An item that was only ever seen too far away (beyond `DepthSampler.maxRange`) is `outOfRange`.
    /// Everything else is decided by `Geometry.centres`: `tooFewPoints`, `baseNotSeen` or `measured`.
    /// An item seen far once but near later has points, so it is not `outOfRange`.
    public func scanResult(floorY: Float, isSubject: Bool) -> EquipmentCentres {
        // Out of range: no points were kept, but a frame did see the item farther than the range.
        // No points and nothing seen far away is not out of range: that is `tooFewPoints`.
        if points.isEmpty, sawPointsBeyondRange {
            return EquipmentCentres(status: .outOfRange, baseCentre: nil, topCentre: nil)
        }
        return Geometry.centres(of: points, floorY: floorY, isSubject: isSubject)
    }

    /// The mask's points when there is a mask, else the box's points (the same rule as `Sighting.make`).
    private static func worldPoints(
        box: NormalizedBox, mask: InstanceMask?, depth: DepthFrame, camera: CameraModel, maxRange: Float
    ) -> [SIMD3<Float>] {
        mask.map { DepthSampler.worldPoints(in: $0, depth: depth, camera: camera, maxRange: maxRange) }
            ?? DepthSampler.worldPoints(in: box, depth: depth, camera: camera, maxRange: maxRange)
    }
}
