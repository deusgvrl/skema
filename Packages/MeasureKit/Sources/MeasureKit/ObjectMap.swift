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
            let nearest = entries.indices
                .filter { entries[$0].label == s.label }
                .map { ($0, simd_distance(entries[$0].position, s.position)) }
                .filter { $0.1 <= ObjectMap.mergeRadius }
                .min { $0.1 < $1.1 }?.0
            if let i = nearest {
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
