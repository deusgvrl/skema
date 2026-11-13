import Foundation
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
    /// `scanResult(isSubject:)` uses it to decide "out of range".
    public private(set) var sawPointsBeyondRange = false

    /// The 1 cm cells that already hold a point, so the same spot seen in many frames is stored once.
    private var voxels: Set<SIMD3<Int32>> = []

    public init() {}

    /// Adds the equipment's points from one frame: its mask when it has one, else its box.
    /// Only points within `DepthSampler.maxRange` are kept, and a cell that already has a point is skipped.
    public mutating func add(box: NormalizedBox, mask: InstanceMask?, depth: DepthFrame, camera: CameraModel) {
        // The mask's points when there is a mask, else the box's points (the same rule as `Sighting.make`).
        func worldPoints(maxRange: Float) -> [SIMD3<Float>] {
            if let mask {
                return DepthSampler.worldPoints(in: mask, depth: depth, camera: camera, maxRange: maxRange)
            }
            return DepthSampler.worldPoints(in: box, depth: depth, camera: camera, maxRange: maxRange)
        }
        let inRange = worldPoints(maxRange: DepthSampler.maxRange)
        guard !inRange.isEmpty else {
            // Nothing within range. Look again without the limit: points farther away mean the equipment
            // was seen but too far; no points at all mean nothing usable was seen (low confidence, empty region).
            if !worldPoints(maxRange: .infinity).isEmpty { sawPointsBeyondRange = true }
            return
        }
        insert(inRange)
    }

    /// Adds world points that were collected by another rule (a painted column, `DepthSampler.columnPoints`).
    /// The same range and cell rules as `add(box:mask:depth:camera:)`: a point farther than `DepthSampler.maxRange`
    /// from `camera` is dropped, and only far points (and none near) make the item `outOfRange`.
    public mutating func add(points newPoints: [SIMD3<Float>], camera: CameraModel) {
        let toCamera = camera.cameraToWorld.inverse
        let near = newPoints.filter { -(toCamera * SIMD4<Float>($0, 1)).z <= DepthSampler.maxRange }
        if near.isEmpty, !newPoints.isEmpty { sawPointsBeyondRange = true }
        insert(near)
    }

    /// Keeps each point whose 1 cm cell has no point yet.
    private mutating func insert(_ newPoints: [SIMD3<Float>]) {
        for point in newPoints {
            // Same cell rule as `ScanCloud`: the cell is the point's position divided by the cell size, rounded down.
            let cell = SIMD3<Int32>((point / ScanCloud.voxelSize).rounded(.down), rounding: .towardZero)
            if voxels.insert(cell).inserted { points.append(point) }
        }
    }

    /// The centres of this equipment from everything collected over the scan, with `outOfRange` decided.
    ///
    /// An item that was only ever seen too far away (beyond `DepthSampler.maxRange`) is `outOfRange`.
    /// Everything else is decided by `Geometry.centres`: `tooFewPoints` or `measured`.
    /// An item seen far once but near later has points, so it is not `outOfRange`.
    public func scanResult(isSubject: Bool) -> EquipmentCentres {
        // Out of range: no points were kept, but a frame did see the item farther than the range.
        // No points and nothing seen far away is not out of range: that is `tooFewPoints`.
        if points.isEmpty, sawPointsBeyondRange {
            return EquipmentCentres(status: .outOfRange, baseCentre: nil, topCentre: nil)
        }
        return Geometry.centres(of: points, isSubject: isSubject)
    }
}

/// The points of every piece of equipment in one scan, and what they say once the floor and the subject are known.
public struct ScanMeasurements: Sendable {
    private var equipment: [UUID: EquipmentPoints] = [:]

    public init() {}

    /// Adds one frame's view of the equipment `id` (see `EquipmentPoints.add`).
    public mutating func add(
        to id: UUID, box: NormalizedBox, mask: InstanceMask?, depth: DepthFrame, camera: CameraModel
    ) {
        equipment[id, default: EquipmentPoints()].add(box: box, mask: mask, depth: depth, camera: camera)
    }

    /// Adds world points for the equipment `id` (see `EquipmentPoints.add(points:camera:)`).
    public mutating func add(points: [SIMD3<Float>], to id: UUID, camera: CameraModel) {
        equipment[id, default: EquipmentPoints()].add(points: points, camera: camera)
    }

    /// Forgets everything collected for the equipment `id`. An id that was never added does nothing.
    public mutating func remove(_ id: UUID) {
        equipment[id] = nil
    }

    /// The centres of every piece of equipment, or the reason there are none (see `EquipmentPoints.scanResult`).
    private func centres(subject: UUID) -> [UUID: EquipmentCentres] {
        var centres: [UUID: EquipmentCentres] = [:]
        for (id, points) in equipment {
            centres[id] = points.scanResult(isSubject: id == subject)
        }
        return centres
    }

    /// The result for every piece of equipment, measured against the floor at `floorY` and the equipment `subject`.
    ///
    /// A distance or floor position needs both the equipment and the subject to be measured, so without a measured
    /// subject they are all nil. A height needs only the equipment itself.
    public func results(subject: UUID, floorY: Float) -> [UUID: EquipmentResult] {
        let centres = centres(subject: subject)
        let subjectCentres = centres[subject]
        var results: [UUID: EquipmentResult] = [:]
        for (id, own) in centres {
            results[id] = EquipmentResult(
                status: own.status,
                distanceToSubject: subjectCentres.flatMap { Geometry.floorDistance(from: $0, to: own) },
                height: Geometry.height(of: own, floorY: floorY),
                floorOffset: subjectCentres.flatMap { Geometry.floorOffset(of: own, from: $0) },
                pointCount: equipment[id]?.points.count ?? 0
            )
        }
        return results
    }
}
