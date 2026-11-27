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

    /// The 1 cm cells that already hold a point, so the same spot seen in many frames is stored once: each cell's
    /// place in `points`.
    private var voxels: [SIMD3<Int32>: Int] = [:]
    /// For each point, the last frame that saw its cell.
    private var lastSeen: [Int] = []
    /// How many frames added a point closer than `DepthSampler.maxRange`.
    public private(set) var frames = 0

    /// The outline uses the spots seen in the newest this many frames, so old spots fade (27 Nov).
    public static let recentWindow = 30

    public init() {}

    /// The points seen in the newest `recentWindow` frames: what the outline is drawn around, so it follows the item
    /// and lets go of old spots, such as the copies ARKit's drift corrections leave behind.
    public var recentPoints: [SIMD3<Float>] {
        points.indices.filter { frames - lastSeen[$0] < Self.recentWindow }.map { points[$0] }
    }

    /// Adds world points of the equipment (a painted column, `DepthSampler.columnPoints`). A point farther than
    /// `DepthSampler.maxRange` from `camera` is dropped, a cell that already has a point is skipped, and only far points
    /// (and none near) make the item `outOfRange`.
    ///
    /// Each call that keeps a near point is one frame; every cell it sees remembers it (`recentPoints`).
    ///
    /// Returns true when the points changed: a new cell got a point, or `sawPointsBeyondRange` turned on.
    @discardableResult
    public mutating func add(points newPoints: [SIMD3<Float>], camera: CameraModel) -> Bool {
        let countBefore = points.count
        let sawBeyondBefore = sawPointsBeyondRange
        let toCamera = camera.cameraToWorld.inverse
        let near = newPoints.filter { -(toCamera * SIMD4<Float>($0, 1)).z <= DepthSampler.maxRange }
        if near.isEmpty, !newPoints.isEmpty { sawPointsBeyondRange = true }
        if !near.isEmpty { frames += 1 }
        insert(near)
        return points.count != countBefore || sawPointsBeyondRange != sawBeyondBefore
    }

    /// Keeps each point whose 1 cm cell has no point yet, and marks every cell it sees as seen in this frame.
    private mutating func insert(_ newPoints: [SIMD3<Float>]) {
        for point in newPoints {
            // The cell is the point's position divided by the cell size, rounded down.
            let cell = SIMD3<Int32>((point / Self.cellSize).rounded(.down), rounding: .towardZero)
            if let index = voxels[cell] {
                lastSeen[index] = frames
            } else {
                voxels[cell] = points.count
                points.append(point)
                lastSeen.append(frames)
            }
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
    /// Equipment measured from its box (`bigBox`), not from its points: a light, once a frame painted enough of it.
    private var boxMeasured: Set<UUID> = []
    /// Each box-measured item's box, worked out again when its points change.
    private var measuredBoxes: [UUID: WorldBox] = [:]
    /// The sizes of each item's newest frames (`maxFrameSizes`), for the bad-frame check in `addFrame`.
    private var frameSizes: [UUID: [SIMD3<Float>]] = [:]
    /// The centres of each item as `cachedResults` last worked them out. An item leaves it when it changes.
    private var cachedCentres: [UUID: EquipmentCentres] = [:]
    /// The subject the cached centres were worked out for (the subject decides how its own centres are found).
    private var cachedSubject: UUID?
    /// How many times the centres of one item were worked out by `cachedResults` (tests and profiling read it).
    public private(set) var centresCalculations = 0

    public init() {}

    /// Adds world points for the equipment `id` (see `EquipmentPoints.add(points:camera:)`).
    /// Returns how many new points were kept. An item that changed without a new point (it was only seen too far
    /// away) still works out its centres again at the next `cachedResults`.
    @discardableResult
    public mutating func add(points: [SIMD3<Float>], to id: UUID, camera: CameraModel) -> Int {
        let countBefore = equipment[id]?.points.count ?? 0
        if equipment[id, default: EquipmentPoints()].add(points: points, camera: camera) {
            cachedCentres[id] = nil
            if boxMeasured.contains(id) { measuredBoxes[id] = equipment[id].flatMap { WorldBox.around($0.points, trim: WorldBox.itemTrim) } }
        }
        return (equipment[id]?.points.count ?? 0) - countBefore
    }

    /// Forgets everything collected for the equipment `id`. An id that was never added does nothing.
    public mutating func remove(_ id: UUID) {
        equipment[id] = nil
        rules[id] = nil
        boxMeasured.remove(id)
        measuredBoxes[id] = nil
        frameSizes[id] = nil
        cachedCentres[id] = nil
    }

    /// A frame is ignored when its box is more than this many times the usual size (the median of the item's
    /// newest `maxFrameSizes` frames) on any side, plus `frameSizeSlack`: a leak or a glitchy depth frame.
    public static let maxFrameGrowth: Float = 2
    public static let frameSizeSlack: Float = 0.02
    public static let maxFrameSizes = 15
    /// The check starts once this many frames are known.
    public static let minFrameSizes = 5

    /// Adds one frame's dots of the equipment `id` (`DepthGrouping.itemPoints`): a light's as `addSurface`, the
    /// subject's and a camera's as `add(points:to:camera:)`. A frame far bigger than the item's usual frames
    /// (`maxFrameGrowth`) is ignored. Returns true when what the item is measured from changed.
    @discardableResult
    public mutating func addFrame(_ points: [SIMD3<Float>], to id: UUID, kind: ItemKind, camera: CameraModel) -> Bool {
        if let box = WorldBox.around(points) {
            let size = box.max - box.min
            let known = frameSizes[id, default: []]
            if known.count >= Self.minFrameSizes {
                let usual = SIMD3((0..<3).map { axis in known.map { $0[axis] }.sorted()[known.count / 2] })
                guard all(size .<= usual * Self.maxFrameGrowth + Self.frameSizeSlack) else { return false }
            }
            frameSizes[id] = Array((known + [size]).suffix(Self.maxFrameSizes))
        }
        if kind == .light {
            return addSurface(points: points, to: id, camera: camera)
        }
        return add(points: points, to: id, camera: camera) > 0 || cachedCentres[id] == nil
    }

    /// The box the scan screen draws around the equipment `id`: around the spots seen in the newest frames
    /// (`EquipmentPoints.recentPoints`), with the strays at each end trimmed (`WorldBox.around`). It follows the item
    /// and can shrink again. Nil before any frame.
    public func outline(for id: UUID) -> WorldBox? {
        equipment[id].flatMap { WorldBox.around($0.recentPoints, trim: WorldBox.itemTrim) }
    }

    /// A light is measured from its box once a frame painted at least this many of its dots (A10-106, Amadeus: 20,
    /// as the A10-90 sightings).
    public static let minSurfacePoints = 20

    /// A10-106 cases 6–7: one frame's painted surface of the equipment `id` (`DepthGrouping.itemPoints`). Its points
    /// join the equipment's points as `add(points:to:camera:)` does; with `minSurfacePoints` or more the equipment is
    /// measured from its box (`bigBox`), worked out here. Returns true when what it is measured from changed.
    @discardableResult
    public mutating func addSurface(points: [SIMD3<Float>], to id: UUID, camera: CameraModel) -> Bool {
        let countBefore = equipment[id]?.points.count ?? 0
        let changed = equipment[id, default: EquipmentPoints()].add(points: points, camera: camera)
        let firstBox = points.count >= Self.minSurfacePoints && boxMeasured.insert(id).inserted
        guard changed || firstBox else { return (equipment[id]?.points.count ?? 0) != countBefore }
        cachedCentres[id] = nil
        if boxMeasured.contains(id) { measuredBoxes[id] = equipment[id].flatMap { WorldBox.around($0.points, trim: WorldBox.itemTrim) } }
        return true
    }

    /// The box the equipment `id` is measured from: around all its points, with the strays at each end trimmed
    /// (`WorldBox.around`). Nil before it is measured from a box (27 Nov: was the union of the newest 30 frames'
    /// boxes, which one bad frame could stretch; a bad frame is now left out by `addFrame`).
    public func bigBox(for id: UUID) -> WorldBox? {
        measuredBoxes[id]
    }

    /// How the top centre of the equipment `id` is found (default: `.topPoint`). A light and a camera use `.middle`.
    public mutating func setRule(_ rule: CentreRule, for id: UUID) {
        rules[id] = rule
        cachedCentres[id] = nil
    }

    /// The centres of the equipment `id` when `subject` is the subject; nil when it has no points. Tests read it.
    func centres(for id: UUID, subject: UUID) -> EquipmentCentres? {
        equipment[id].map { centres(of: id, points: $0, subject: subject) }
    }

    /// The centres of the equipment `id`, or the reason there are none (see `EquipmentPoints.scanResult`).
    private func centres(of id: UUID, points: EquipmentPoints, subject: UUID) -> EquipmentCentres {
        // A10-106 commit 7: an item with a big box is measured from the box (`results`), so the centres of its
        // points would be thrown away; only its status is worked out.
        if boxMeasured.contains(id) {
            return EquipmentCentres(status: points.status, baseCentre: nil, topCentre: nil)
        }
        return points.scanResult(isSubject: id == subject, rule: rules[id] ?? .topPoint)
    }

    /// The result for every piece of equipment, measured against the floor at `floorY` and the equipment `subject`.
    ///
    /// A distance or floor position needs both the equipment and the subject to be measured, so without a measured
    /// subject they are all nil. A height needs only the equipment itself.
    public func results(subject: UUID, floorY: Float) -> [UUID: EquipmentResult] {
        var centres: [UUID: EquipmentCentres] = [:]
        for (id, points) in equipment {
            centres[id] = self.centres(of: id, points: points, subject: subject)
        }
        return results(from: centres, subject: subject, floorY: floorY)
    }

    /// The same values as `results(subject:floorY:)`, but the centres of an item are worked out again only when the
    /// item changed since the last call: new points, a new small box, a new rule, or the item was removed. A call with
    /// another `subject` starts again. For the scan loop, which asks for results every frame.
    public mutating func cachedResults(subject: UUID, floorY: Float) -> [UUID: EquipmentResult] {
        if cachedSubject != subject {
            cachedCentres = [:]
            cachedSubject = subject
        }
        var centres: [UUID: EquipmentCentres] = [:]
        for (id, points) in equipment {
            if let known = cachedCentres[id] {
                centres[id] = known
            } else {
                let worked = self.centres(of: id, points: points, subject: subject)
                cachedCentres[id] = worked
                centresCalculations += 1
                centres[id] = worked
            }
        }
        return results(from: centres, subject: subject, floorY: floorY)
    }

    /// Turns the centres of every item into results (shared by `results` and `cachedResults`).
    private func results(
        from centres: [UUID: EquipmentCentres], subject: UUID, floorY: Float
    ) -> [UUID: EquipmentResult] {
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
