import CoreGraphics
import MeasureKit
import MeasureKitVision

/// Finds cameras with Apple Vision (A10-90): Vision's foreground objects, each with its mask,
/// then Vision's image classifier on each object's area. Only the "camera" label counts.
/// Reuses the PoC's Vision steps from MeasureKitVision (`VisionSegmentDetector`, `VisionDetector.classify`).
nonisolated struct CameraDetector: EquipmentDetecting {
    /// Amadeus, 13 Nov: 60% on both YOLOE and Vision for now.
    static let minConfidence: Float = 0.60
    /// The one label asked for, from Vision's classifier list (checked on 13 Nov: "camera" is one of its 1,303 labels).
    static let label = "camera"
    /// The most objects classified per look, to keep each look short.
    static let maxObjects = 6

    /// `@concurrent` keeps Vision off the caller's actor, like `EquipmentDetector.detect`.
    /// Keeps no reference to the frame.
    @concurrent
    func detect(in frame: ScanFrame) async throws -> [EquipmentDetection] {
        let objects = try VisionSegmentDetector.instanceMasks(in: frame.image, orientation: frame.orientation)
        var cameras: [EquipmentDetection] = []
        for object in objects.prefix(Self.maxObjects) {
            // Bounds in the oriented image (top-left origin) → Vision's lower-left origin for the classifier's area.
            guard let bounds = MaskMapping.bounds(of: object) else { continue }
            let area = CGRect(x: bounds.x, y: 1 - bounds.y - bounds.height, width: bounds.width, height: bounds.height)
            let labels = try VisionDetector.classify(frame.image, orientation: frame.orientation, region: area)
            RawCandidateStore.shared.record(
                [Self.candidate(box: [Float(bounds.x), Float(bounds.y), Float(bounds.width), Float(bounds.height)],
                                classifications: labels)], at: frame.timestamp)
            if let camera = Self.camera(from: object, classifications: labels, orientation: frame.orientation) {
                cameras.append(camera)
            }
        }
        return cameras
    }

    /// Raw-data logger: one Vision blob with its "camera" score and its best label, kept or not.
    static func candidate(box: [Float],
                          classifications: [(identifier: String, confidence: Float)]) -> RawCandidate {
        let score = classifications.first { $0.identifier == label }?.confidence ?? 0
        let top = classifications.max { $0.confidence < $1.confidence }
        return RawCandidate(source: "vision", label: label, confidence: score, box: box,
                            kept: score >= minConfidence, topLabel: top?.identifier, topConfidence: top?.confidence)
    }

    /// Cases D3–D5: a camera when "camera" scores at least 60%, whatever the other labels score.
    /// The mask is turned from Vision's oriented frame into the native picture, the same way as YOLOE's masks.
    static func camera(from mask: InstanceMask, classifications: [(identifier: String, confidence: Float)],
                       orientation: ImageOrientation) -> EquipmentDetection? {
        guard let pick = LabelPicker.pick(classifications, targets: [label], minConfidence: minConfidence) else {
            return nil
        }
        return EquipmentDetection(kind: .camera, confidence: pick.confidence,
                                  mask: MaskMapping.nativeMask(mask, orientation: orientation))
    }
}
