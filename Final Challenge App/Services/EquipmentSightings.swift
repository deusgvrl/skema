import MeasureKit
import MeasureKitVision

/// A sighting together with the mask of the detection it came from (A10-62).
/// Keeping them paired means a detection without a sighting can never shift masks onto the wrong item.
nonisolated struct SightedDetection: Equatable, Sendable {
    let sighting: Sighting
    let mask: InstanceMask
}

/// Detection masks + the LiDAR depth → 3D sightings for tracking (A10-62).
nonisolated enum EquipmentSightings {
    /// One entry per detection that has enough good depth points inside its mask, in the detections' order.
    /// No depth (first frames, no LiDAR) gives no sightings. Depth past `DepthSampler.maxRange` (5 m) is ignored
    /// (Amadeus, 11 Nov: LiDAR is unreliable that far).
    static func make(from detections: [EquipmentDetection], depth: DepthFrame?,
                     camera: CameraModel) -> [SightedDetection] {
        guard let depth else { return [] }
        return detections.compactMap { found in
            guard let box = MaskMapping.bounds(of: found.mask), let label = EquipmentKind.modelLabels[found.kind] else {
                return nil
            }
            let detection = Detection(label: label, confidence: found.confidence, box: box, mask: found.mask)
            return Sighting.make(from: detection, depth: depth, camera: camera, maxRange: DepthSampler.maxRange)
                .map { SightedDetection(sighting: $0, mask: found.mask) }
        }
    }
}
