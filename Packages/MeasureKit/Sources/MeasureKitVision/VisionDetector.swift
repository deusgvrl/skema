import CoreGraphics
import CoreVideo
import ImageIO
import Vision
import MeasureKit

public struct VisionDetector: ObjectDetector {
    /// Labels in both Apple's classifier list and COCO's 80 classes, so Phase 2 compares like with like.
    /// Checked on 3 Nov 2026 against VNClassifyImageRequest.supportedIdentifiers() on macOS 27.
    public static let defaultTargets: Set<String> = ["bottle", "cup", "vase", "bowl", "book", "laptop", "scissors", "clock"]

    public let targetLabels: Set<String>
    public let minConfidence: Float
    public let maxObjects: Int

    public init(targetLabels: Set<String> = defaultTargets, minConfidence: Float = 0.3, maxObjects: Int = 5) {
        self.targetLabels = targetLabels
        self.minConfidence = minConfidence
        self.maxObjects = maxObjects
    }

    public var name: String { "Apple Vision (saliency + classify)" }

    /// 1. Objectness saliency boxes. 2. Classify each box. 3. Keep target labels. 4. Map to native coordinates.
    public func detect(in image: CVPixelBuffer, orientation: ImageOrientation) async throws -> [Detection] {
        let boxes = try Self.salientBoxes(in: image, orientation: orientation).prefix(maxObjects)
        var detections: [Detection] = []
        for box in boxes {
            let classifications = try Self.classify(image, orientation: orientation, region: box)
            guard let pick = LabelPicker.pick(classifications, targets: targetLabels, minConfidence: minConfidence) else { continue }
            detections.append(Detection(label: pick.label, confidence: pick.confidence,
                                        box: VisionBoxMapping.nativeBox(fromVision: box, orientation: orientation)))
        }
        return detections
    }

    /// Step 1. Boxes are in Vision's normalized, bottom-left-origin coordinates of the ORIENTED image.
    public static func salientBoxes(in image: CVPixelBuffer, orientation: ImageOrientation) throws -> [CGRect] {
        let request = VNGenerateObjectnessBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: image, orientation: orientation.cgOrientation, options: [:])
        try handler.perform([request])
        return (request.results?.first?.salientObjects ?? []).map(\.boundingBox)
    }

    /// Step 2. `region` (a saliency box) is used directly as `regionOfInterest`: both are normalized,
    /// lower-left origin, in the oriented image.
    static func classify(_ image: CVPixelBuffer, orientation: ImageOrientation, region: CGRect) throws -> [(identifier: String, confidence: Float)] {
        let request = VNClassifyImageRequest()
        request.regionOfInterest = region
        let handler = VNImageRequestHandler(cvPixelBuffer: image, orientation: orientation.cgOrientation, options: [:])
        try handler.perform([request])
        return (request.results ?? []).map { (identifier: $0.identifier, confidence: $0.confidence) }
    }
}

extension ImageOrientation {
    /// Same meaning as `CGImagePropertyOrientation` (see the contract in `Types.swift`).
    public var cgOrientation: CGImagePropertyOrientation {
        switch self {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        }
    }
}
