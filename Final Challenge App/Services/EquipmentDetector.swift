import CoreML
import Foundation
import MeasureKit
import MeasureKitVision
import Vision

/// What the detector can name (A10-56): studio lighting of any type, and cameras.
nonisolated enum EquipmentKind: Hashable, Sendable {
    case studioLighting
    case camera

    /// The label each kind has in the model file, compared after `EquipmentFilter.normalized`.
    static let modelLabels: [EquipmentKind: String] = [.studioLighting: "studio lighting", .camera: "camera"]

    /// Matches a model label after trimming spaces and ignoring case. Any other label is nil.
    init?(modelLabel: String) {
        let label = EquipmentFilter.normalized(modelLabel)
        guard let kind = Self.modelLabels.first(where: { $0.value == label })?.key else { return nil }
        self = kind
    }
}

/// What the model saw in one frame (not yet an item: tracking is A10-61).
nonisolated struct EquipmentDetection: Equatable, Sendable {
    let kind: EquipmentKind
    let confidence: Float
    /// 640 x 640 in the model's oriented frame, mapped back to the camera's native orientation.
    let mask: InstanceMask
    /// A light scoring from `weakFloor` up to `minConfidence` (A10-90, D20):
    /// it may only keep an item that is already accepted.
    var isWeak = false
    /// Raw-data logger only: the mask before `CombinedDetector` trimmed it by depth. Nil when it was not trimmed.
    var untrimmedMask: InstanceMask?
}

nonisolated protocol EquipmentDetecting: Sendable {
    func detect(in frame: ScanFrame) async throws -> [EquipmentDetection]
}

/// Finds and outlines studio items in camera frames with the bundled YOLOE model (A10-60).
/// `nonisolated`, and `detect` is `@concurrent`, so the model runs off the main actor and the scan stays smooth.
/// It reads the frame's image and keeps no reference to it.
nonisolated final class EquipmentDetector: EquipmentDetecting, @unchecked Sendable {
    enum Failure: Error, Equatable {
        case modelNotFound
        /// The model's metadata has no usable `names` entry.
        case missingClassNames
        /// The model has a label the app doesn't know.
        case unknownLabel(String)
        /// The model did not return a [1, N, 38] array and a [1, 32, H, W] array.
        case unexpectedOutputs
    }

    /// A10-60 decisions (10 Nov 2026): drop boxes over 80% of the frame, one box per object within a label.
    /// A10-90 (Amadeus, 13 Nov): 60% cutoff, to stop flickering (was 30%).
    static let minConfidence: Float = 0.50
    /// A10-90 (option A, Amadeus, 13 Nov): YOLOE keeps only studio lighting. Its camera prompts stay in the model,
    /// so a camera is labelled "camera" (and dropped here) instead of passing as studio lighting. Vision finds cameras.
    static let keptLabels: Set<String> = ["studio lighting"]
    /// A10-90 (Amadeus, 16 Nov): from here up to `minConfidence` a light is weak: it may only keep an accepted item.
    static let weakFloor: Float = 0.35
    static let maxAreaFraction: Float = 0.8
    static let overlapThreshold: Float = 0.5
    static let inputSize = 640

    /// How many prompts in the model name each kind.
    let promptCounts: [EquipmentKind: Int]
    private let classNames: [Int: String]
    private let visionModel: VNCoreMLModel

    /// Loads `yoloe-26m-seg` from the app bundle (Xcode compiles the .mlpackage into a .mlmodelc).
    convenience init() throws {
        guard let url = Bundle(for: EquipmentDetector.self).url(forResource: "yoloe-26m-seg", withExtension: "mlmodelc")
        else { throw Failure.modelNotFound }
        try self.init(model: MLModel(contentsOf: url))
    }

    init(model: MLModel) throws {
        let creatorDefined = model.modelDescription.metadata[.creatorDefinedKey] as? [String: String]
        guard let namesString = creatorDefined?["names"] else { throw Failure.missingClassNames }
        let names = YOLOSegmentDecoder.classNames(fromMetadata: namesString)
        guard !names.isEmpty else { throw Failure.missingClassNames }
        var counts: [EquipmentKind: Int] = [:]
        for name in names.values {
            guard let kind = EquipmentKind(modelLabel: name) else { throw Failure.unknownLabel(name) }
            counts[kind, default: 0] += 1
        }
        self.classNames = names
        self.promptCounts = counts
        self.visionModel = try VNCoreMLModel(for: model)
    }

    /// Apple, VNImageCropAndScaleOption.scaleFill: the image is resized to fill the 640 x 640 input,
    /// so the whole frame is the model's frame.
    /// `@concurrent`: with SWIFT_APPROACHABLE_CONCURRENCY a plain nonisolated async function runs on the caller's
    /// actor, so a ViewModel's call would run the model on the main actor. This keeps it off.
    @concurrent
    func detect(in frame: ScanFrame) async throws -> [EquipmentDetection] {
        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .scaleFill
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.image, orientation: frame.orientation.cgOrientation)
        try handler.perform([request])

        let arrays = (request.results ?? []).compactMap {
            ($0 as? VNCoreMLFeatureValueObservation)?.featureValue.multiArrayValue
        }
        guard let rowArray = arrays.first(where: { $0.shape.count == 3 }),
              let protoArray = arrays.first(where: { $0.shape.count == 4 }) else { throw Failure.unexpectedOutputs }
        // Raw-data logger: decode down to 30% so rows under the weak line can be logged, then apply the weak line.
        let candidateRows = YOLOSegmentDecoder.rows(output: try YOLOSegmentDetector.floats(from: rowArray),
                                                    count: rowArray.shape[1].intValue,
                                                    minConfidence: Self.candidateFloor)
        RawCandidateStore.shared.record(Self.candidates(from: candidateRows, classNames: classNames),
                                        at: frame.timestamp)
        let rows = candidateRows.filter { $0.confidence >= Self.weakFloor }
        guard !rows.isEmpty else { return [] }
        return Self.detections(from: rows, protos: try YOLOSegmentDetector.floats(from: protoArray),
                               protoSize: protoArray.shape[2].intValue, classNames: classNames,
                               orientation: frame.orientation)
    }

    /// Raw-data logger: rows from this confidence up are logged as candidates.
    static let candidateFloor: Float = 0.30
    static let maxCandidates = 20

    /// Raw-data logger: the best rows from 30% up, each marked kept when it has a kept label and reaches the
    /// weak line (35%); rows under `minConfidence` are kept as weak.
    static func candidates(from rows: [YOLORow], classNames: [Int: String]) -> [RawCandidate] {
        rows.sorted { $0.confidence > $1.confidence }.prefix(maxCandidates).map { row in
            let label = classNames[row.classIndex] ?? "class \(row.classIndex)"
            let size = Float(inputSize)
            return RawCandidate(source: "yoloe", label: label, confidence: row.confidence,
                                box: [row.x1 / size, row.y1 / size, (row.x2 - row.x1) / size, (row.y2 - row.y1) / size],
                                kept: keptLabels.contains(label) && row.confidence >= weakFloor)
        }
    }

    /// Decoded rows → filter (`EquipmentFilter.keep`) → 640 x 640 masks → native orientation. Best first.
    static func detections(from rows: [YOLORow], protos: [Float], protoSize: Int, classNames: [Int: String],
                           orientation: ImageOrientation) -> [EquipmentDetection] {
        let kept = EquipmentFilter.keep(rows, classNames: classNames, labels: keptLabels,
                                        maxAreaFraction: maxAreaFraction, iouThreshold: overlapThreshold,
                                        inputSize: Float(inputSize))
        return kept.compactMap { row in
            guard let kind = classNames[row.classIndex].flatMap(EquipmentKind.init(modelLabel:)) else { return nil }
            let mask = YOLOSegmentDecoder.upsampledMask(for: row, protos: protos, protoSize: protoSize,
                                                        inputSize: inputSize)
            return EquipmentDetection(kind: kind, confidence: row.confidence,
                                      mask: MaskMapping.nativeMask(mask, orientation: orientation),
                                      isWeak: row.confidence < minConfidence)
        }
    }
}
