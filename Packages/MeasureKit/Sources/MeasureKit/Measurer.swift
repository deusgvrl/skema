import simd

/// Turns detections plus one depth frame into per-object measurements.
public struct Measurer {
    public let minPoints: Int

    public init(minPoints: Int = 20) {
        self.minPoints = minPoints
    }

    /// One measurement per detection, same order. Objects with fewer than `minPoints` depth points
    /// get nil position and nil values (pointCount still set). If the subject has no position,
    /// every distanceToSubject is nil.
    public func measure(
        detections: [Detection], subjectIndex: Int,
        depth: DepthFrame, camera: CameraModel, floorY: Float?
    ) -> [ObjectMeasurement] {
        let clouds = detections.map { DepthSampler.worldPoints(in: $0.box, depth: depth, camera: camera) }
        let positions: [SIMD3<Float>?] = clouds.map { $0.count >= minPoints ? Geometry.medianPoint($0) : nil }
        let subject = detections.indices.contains(subjectIndex) ? positions[subjectIndex] : nil

        return detections.indices.map { i in
            guard let position = positions[i] else {
                return ObjectMeasurement(detection: detections[i], position: nil, pointCount: clouds[i].count,
                                         distanceToSubject: nil, heightAboveFloor: nil,
                                         tiltDegrees: nil, aimOffsetDegrees: nil)
            }
            let axis = Geometry.principalAxis(clouds[i])
            return ObjectMeasurement(
                detection: detections[i],
                position: position,
                pointCount: clouds[i].count,
                distanceToSubject: subject.map { i == subjectIndex ? 0 : simd_distance(position, $0) },
                heightAboveFloor: floorY.map { Geometry.heightAboveFloor(position, floorY: $0) },
                tiltDegrees: axis.map { Geometry.tiltDegrees(axis: $0) },
                aimOffsetDegrees: axis.flatMap { a in
                    subject.flatMap { Geometry.aimOffsetDegrees(axis: a, from: position, to: $0) }
                })
        }
    }
}
