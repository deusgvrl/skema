import Foundation
import simd

/// The 3D points of one piece of equipment, merged over many frames while the user walks around.
public struct EquipmentPoints: Sendable {
    /// World points, at most one per 1 cm cell.
    public private(set) var points: [SIMD3<Float>] = []
    /// True when a frame showed the equipment only farther than `DepthSampler.maxRange`.
    /// `scanResult(isSubject:)` uses it to decide "out of range".
    public private(set) var sawPointsBeyondRange = false

    /// The side of a cell (metres): the points keep at most one per cell.
    public static let cellSize: Float = 0.01

    /// The 1 cm cells that already hold a point, so the same spot seen in many frames is stored once.
    private var voxels: Set<SIMD3<Int32>> = []

    public init() {}

    /// Adds world points of the equipment (a painted column, `DepthSampler.columnPoints`). A point farther than
    /// `DepthSampler.maxRange` from `camera` is dropped, a cell that already has a point is skipped, and only far points
    /// (and none near) make the item `outOfRange`.
    public mutating func add(points newPoints: [SIMD3<Float>], camera: CameraModel) {
        let toCamera = camera.cameraToWorld.inverse
        let near = newPoints.filter { -(toCamera * SIMD4<Float>($0, 1)).z <= DepthSampler.maxRange }
        if near.isEmpty, !newPoints.isEmpty { sawPointsBeyondRange = true }
        insert(near)
    }

    /// Keeps each point whose 1 cm cell has no point yet.
    private mutating func insert(_ newPoints: [SIMD3<Float>]) {
        for point in newPoints {
            // The cell is the point's position divided by the cell size, rounded down.
            let cell = SIMD3<Int32>((point / Self.cellSize).rounded(.down), rounding: .towardZero)
            if voxels.insert(cell).inserted { points.append(point) }
        }
    }

    /// The centres of this equipment from everything collected over the scan, with `outOfRange` decided.
    ///
    /// An item that was only ever seen too far away (beyond `DepthSampler.maxRange`) is `outOfRange`.
    /// Everything else is decided by `Geometry.centres`: `tooFewPoints` or `measured`.
    /// An item seen far once but near later has points, so it is not `outOfRange`.
    public func scanResult(isSubject: Bool, rule: CentreRule = .topPoint) -> EquipmentCentres {
        // Out of range: no points were kept, but a frame did see the item farther than the range.
        // No points and nothing seen far away is not out of range: that is `tooFewPoints`.
        if points.isEmpty, sawPointsBeyondRange {
            return EquipmentCentres(status: .outOfRange, baseCentre: nil, topCentre: nil)
        }
        return Geometry.centres(of: points, isSubject: isSubject, rule: rule)
    }

    /// A10-106 cases 26–29: only the status of `scanResult(isSubject:rule:)`, from how many points there are, with no
    /// centres and no sorting. For an item measured from its big box, which needs nothing else from its points.
    public var status: MeasurementStatus {
        if points.isEmpty, sawPointsBeyondRange { return .outOfRange }
        return points.count >= Geometry.minPointCount ? .measured : .tooFewPoints
    }
}

/// The points of every piece of equipment in one scan, and what they say once the floor and the subject are known.
public struct ScanMeasurements: Sendable {
    private var equipment: [UUID: EquipmentPoints] = [:]
    private var rules: [UUID: CentreRule] = [:]
    /// The small boxes of equipment collected with `addSurface`, newest last.
    private var boxes: [UUID: [WorldBox]] = [:]

    public init() {}

    /// Adds world points for the equipment `id` (see `EquipmentPoints.add(points:camera:)`).
    public mutating func add(points: [SIMD3<Float>], to id: UUID, camera: CameraModel) {
        equipment[id, default: EquipmentPoints()].add(points: points, camera: camera)
    }

    /// Forgets everything collected for the equipment `id`. An id that was never added does nothing.
    public mutating func remove(_ id: UUID) {
        equipment[id] = nil
        rules[id] = nil
        boxes[id] = nil
    }

    /// The smallest box (world, axis-aligned) holding every point kept for the equipment `id`; nil before any.
    /// The scan screen draws its outline around the tapped item.
    public func bounds(for id: UUID) -> (min: SIMD3<Float>, max: SIMD3<Float>)? {
        guard let points = equipment[id]?.points, let first = points.first else { return nil }
        return points.dropFirst().reduce((min: first, max: first)) { box, point in
            (min: simd_min(box.min, point), max: simd_max(box.max, point))
        }
    }

    /// A small box needs at least this many points of one frame (A10-106, Amadeus: 20, as the A10-90 sightings).
    public static let minSurfacePoints = 20
    /// The big box is the union of this many newest small boxes (A10-90 rule E, 30).
    public static let maxKeptBoxes = 30

    /// A10-106 cases 6–7: one frame's painted surface of the equipment `id` (`DepthGrouping.surface`). Its points join
    /// the equipment's points as `add(points:to:camera:)` does, and with `minSurfacePoints` or more they make a small
    /// box; the newest `maxKeptBoxes` are kept.
    public mutating func addSurface(points: [SIMD3<Float>], to id: UUID, camera: CameraModel) {
        add(points: points, to: id, camera: camera)
        guard points.count >= Self.minSurfacePoints, let box = WorldBox.around(points) else { return }
        var kept = boxes[id, default: []]
        kept.append(box)
        boxes[id] = Array(kept.suffix(Self.maxKeptBoxes))
    }

    /// The grown box of the equipment `id`: the union of its kept small boxes. Nil before its first small box.
    public func bigBox(for id: UUID) -> WorldBox? {
        guard let kept = boxes[id], let first = kept.first else { return nil }
        return kept.dropFirst().reduce(first) { $0.union($1) }
    }

    /// How the top centre of the equipment `id` is found (default: `.topPoint`). A light uses `.middle`.
    public mutating func setRule(_ rule: CentreRule, for id: UUID) {
        rules[id] = rule
    }

    /// The centres of every piece of equipment, or the reason there are none (see `EquipmentPoints.scanResult`).
    private func centres(subject: UUID) -> [UUID: EquipmentCentres] {
        var centres: [UUID: EquipmentCentres] = [:]
        for (id, points) in equipment {
            // A10-106 commit 7: an item with a big box is measured from the box (`results`), so the centres of its
            // points would be thrown away; only its status is worked out.
            if boxes[id]?.isEmpty == false {
                centres[id] = EquipmentCentres(status: points.status, baseCentre: nil, topCentre: nil)
            } else {
                centres[id] = points.scanResult(isSubject: id == subject, rule: rules[id] ?? .topPoint)
            }
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
        for (id, found) in centres {
            // A10-106: an item with a grown box is measured at the middle height of the box's back.
            var own = found
            if own.status == .measured, let box = bigBox(for: id) {
                own = Geometry.backCentres(of: box, subjectBase: id == subject ? nil : subjectCentres?.baseCentre)
            }
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
