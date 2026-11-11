import simd

/// An object in the map, built from all its sightings.
public struct MappedObject: Equatable, Sendable, Identifiable {
    public let id: Int                   // 0, 1, 2 ... in creation order, never reused (not even after removeAll)
    public let label: String
    public let sightingCount: Int        // every sighting ever merged in
    public let position: SIMD3<Float>    // per-axis median of the kept sightings' positions
    public let axis: SIMD3<Float>?       // mean of kept axes after flipping each to agree (dot >= 0) with the newest; unit; nil if none
    public let confidence: Float         // highest confidence seen
}

/// Where an item is in A10-61's tracking: pending ("Detecting…") until seen for 1 second, then accepted.
public enum ItemStatus: Equatable, Sendable {
    case pending
    case accepted
}

/// An object as tracking sees it (A10-61). `number` is given per label when the item is accepted.
public struct TrackedItem: Equatable, Sendable, Identifiable {
    public let id: Int
    public let label: String
    public let status: ItemStatus
    public let number: Int?
    public let position: SIMD3<Float>
    /// How far along the 1 second to acceptance, 0...1 (A10-62's ring). Accepted items are 1.
    public let progress: Double
    /// Seen at the latest look, so the screen draws its mask now (A10-62).
    public let isSeen: Bool

    public init(id: Int, label: String, status: ItemStatus, number: Int?, position: SIMD3<Float>,
                progress: Double, isSeen: Bool) {
        self.id = id
        self.label = label
        self.status = status
        self.number = number
        self.position = position
        self.progress = progress
        self.isSeen = isSeen
    }
}

public struct MapMeasurement: Equatable, Sendable {
    public let object: MappedObject
    public let isSubject: Bool
    public let distanceToSubject: Float?
    public let heightAboveFloor: Float?
    public let tiltDegrees: Float?
    public let aimOffsetDegrees: Float?
}

public struct ObjectMap: Sendable {
    public static let mergeRadius: Float = 0.2     // metres
    public static let maxKeptSightings = 30        // newest kept per object

    private struct Entry: Sendable {
        let id: Int
        let label: String
        var sightingCount = 0
        var kept: [Sighting] = []
        var confidence: Float = 0
        var position: SIMD3<Float> = .zero
        var axis: SIMD3<Float>?
        // Tracking (A10-61)
        var status = ItemStatus.pending
        var number: Int?
        var seenTime: Double = 0     // seconds of seen time so far (real time, gaps not counted)
        var lastSeen: Double = 0     // time of the last look that saw this item
        var isSeen = false           // seen at the latest look (A10-62: draw its mask now)

        /// One look of the detector. `seen`: the item was seen at this look. `wait`: seconds since the previous look.
        /// Each wait counts toward `seenTime` when the item is seen at the end of it.
        /// Returns false when a PENDING item has not been seen for more than `ObjectMap.maxGap` (a flicker: remove it).
        /// An accepted item is always kept.
        mutating func advance(seen: Bool, wait: Double, at time: Double) -> Bool {
            
            if seen {
                seenTime += wait
                lastSeen = time
                return true
            }
            if status == .accepted {
               return true
            }
            let gap = time - lastSeen
            return gap <= ObjectMap.maxGap + ObjectMap.tolerance
        }

        mutating func merge(_ s: Sighting) {
            sightingCount += 1
            confidence = max(confidence, s.confidence)
            kept.append(s)
            if kept.count > ObjectMap.maxKeptSightings { kept.removeFirst(kept.count - ObjectMap.maxKeptSightings) }
            position = Geometry.medianPoint(kept.map(\.position)) ?? s.position
            axis = Entry.meanAxis(kept.compactMap(\.axis))
        }

        /// Mean of the axes after flipping each to agree with the newest one; unit, nil when empty or cancelling out.
        private static func meanAxis(_ axes: [SIMD3<Float>]) -> SIMD3<Float>? {
            guard let newest = axes.last else { return nil }
            let sum = axes.reduce(SIMD3<Float>.zero) { $0 + (simd_dot($1, newest) < 0 ? -$1 : $1) }
            let length = simd_length(sum)
            return length > 1e-6 ? sum / length : nil
        }

        var mapped: MappedObject {
            MappedObject(id: id, label: label, sightingCount: sightingCount, position: position,
                         axis: axis, confidence: confidence)
        }
    }

    private var entries: [Entry] = []
    private var nextID = 0

    public init() {}

    public var objects: [MappedObject] { entries.map(\.mapped) }      // creation order

    /// Sightings are processed in order. Each merges into the nearest object with the SAME label whose
    /// current position is within `mergeRadius`; otherwise it starts a new object.
    public mutating func add(_ sightings: [Sighting]) {
        for s in sightings {
            if let i = nearestIndex(for: s) {
                entries[i].merge(s)
            } else {
                var entry = Entry(id: nextID, label: s.label)
                nextID += 1
                entry.merge(s)
                entries.append(entry)
            }
        }
    }

    public mutating func removeAll() {
        entries.removeAll()
    }

    /// The nearest object with the same label within `mergeRadius`, or nil.
    private func nearestIndex(for s: Sighting) -> Int? {
        entries.indices
            .filter { entries[$0].label == s.label }
            .map { ($0, simd_distance(entries[$0].position, s.position)) }
            .filter { $0.1 <= ObjectMap.mergeRadius }
            .min { $0.1 < $1.1 }?.0
    }

    // MARK: - Tracking (A10-61)

    /// Seen for this long (real time, gaps not counted), a pending item becomes accepted (Amadeus, 11 Nov).
    public static let acceptAfter: Double = 1.0
    /// A pending item not seen for longer than this is a flicker and is removed (Amadeus, 11 Nov).
    public static let maxGap: Double = 0.2
    /// Rounding room: 0.1 added ten times is 0.9999999…, not exactly 1.0.
    static let tolerance: Double = 1e-6

    private var lastLook: Double?
    private var lastNumber: [String: Int] = [:]

    /// Tracked items in creation order.
    public var items: [TrackedItem] {
        entries.map {
            TrackedItem(id: $0.id, label: $0.label, status: $0.status, number: $0.number, position: $0.position,
                        progress: $0.status == .accepted ? 1 : min(1, $0.seenTime / ObjectMap.acceptAfter),
                        isSeen: $0.isSeen)
        }
    }

    /// One look of the detector at `time` (seconds, from the frame's timestamp). Call it for EVERY look,
    /// also when nothing was found, so gaps are measured. Sightings merge as in `add`; new ones start pending.
    /// Returns the id of the item each sighting joined, in the same order as `sightings`,
    /// so a caller can match each detection's mask to its item (A10-62).
    @discardableResult
    public mutating func update(_ sightings: [Sighting], at time: Double) -> [Int] {
        let wait = lastLook.map { time - $0 } ?? 0
        lastLook = time
        var seen = Set<Int>()
        var created = Set<Int>()
        var joined: [Int] = []
        for s in sightings {
            if let i = nearestIndex(for: s) {
                entries[i].merge(s)
                seen.insert(entries[i].id)
                joined.append(entries[i].id)
            } else {
                var entry = Entry(id: nextID, label: s.label)
                nextID += 1
                entry.merge(s)
                entry.lastSeen = time
                created.insert(entry.id)
                joined.append(entry.id)
                entries.append(entry)
            }
        }
        for i in entries.indices {
            entries[i].isSeen = seen.contains(entries[i].id) || created.contains(entries[i].id)
        }
        var flickers = Set<Int>()
        for i in entries.indices where !created.contains(entries[i].id) {
            if !entries[i].advance(seen: seen.contains(entries[i].id), wait: wait, at: time) {
                flickers.insert(entries[i].id)
            }
        }
        entries.removeAll { flickers.contains($0.id) }
        for i in entries.indices
        where entries[i].status == .pending && entries[i].seenTime + ObjectMap.tolerance >= ObjectMap.acceptAfter {
            let label = entries[i].label
            let number = (lastNumber[label] ?? 0) + 1
            lastNumber[label] = number
            entries[i].status = .accepted
            entries[i].number = number
        }
        return joined
    }

    /// Forgets an item, for example one the user deleted on the Review page (A10-63).
    /// If it is seen again, it starts over as a new pending item.
    public mutating func forget(id: Int) {
        entries.removeAll { $0.id == id }
    }

    /// One per object, creation order. subjectID nil or unknown: distances and aims are nil.
    /// The subject itself: distance 0, aim nil. Tilt from axis (nil without axis). Height needs floorY.
    /// Aim uses Geometry.aimOffsetDegrees(axis:, from: object, to: subject).
    public func measurements(subjectID: Int?, floorY: Float?) -> [MapMeasurement] {
        let all = objects
        let subject = all.first { $0.id == subjectID }
        return all.map { o in
            let isSubject = o.id == subject?.id
            var distance: Float?
            var aim: Float?
            if let subject {
                distance = isSubject ? 0 : simd_distance(o.position, subject.position)
                if !isSubject, let axis = o.axis {
                    aim = Geometry.aimOffsetDegrees(axis: axis, from: o.position, to: subject.position)
                }
            }
            return MapMeasurement(
                object: o, isSubject: isSubject, distanceToSubject: distance,
                heightAboveFloor: floorY.map { Geometry.heightAboveFloor(o.position, floorY: $0) },
                tiltDegrees: o.axis.map { Geometry.tiltDegrees(axis: $0) },
                aimOffsetDegrees: aim)
        }
    }
}
