import CoreML
import CoreVideo
import Foundation
import Vision
import MeasureKit

/// Thread-safe holder for the last inference time. A reference type, so copies of the detector share it.
final class InferenceTimer: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Double = 0
    var milliseconds: Double { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ ms: Double) { lock.lock(); value = ms; lock.unlock() }
}

public struct YOLOSegmentDetector: ObjectDetector {
    public enum Failure: Error, Equatable {
        /// The model's metadata has no usable `names` entry.
        case missingClassNames
        /// The model did not return a [1, N, 38] array and a [1, 32, H, W] array.
        case unexpectedOutputs
    }

    public let targetLabels: Set<String>
    public let minConfidence: Float
    public let maxObjects: Int
    private let visionModel: VNCoreMLModel
    private let classNames: [Int: String]
    private let modelName: String
    private let timer = InferenceTimer()

    /// Class names come from `model.modelDescription.metadata[.creatorDefinedKey]["names"]` (Ultralytics writes them there).
    public init(model: MLModel, targetLabels: Set<String> = VisionDetector.defaultTargets,
                minConfidence: Float = 0.35, maxObjects: Int = 8) throws {
        let creatorDefined = model.modelDescription.metadata[.creatorDefinedKey] as? [String: String]
        guard let namesString = creatorDefined?["names"] else { throw Failure.missingClassNames }
        let names = YOLOSegmentDecoder.classNames(fromMetadata: namesString)
        guard !names.isEmpty else { throw Failure.missingClassNames }
        self.classNames = names
        self.visionModel = try VNCoreMLModel(for: model)
        self.targetLabels = targetLabels
        self.minConfidence = minConfidence
        self.maxObjects = maxObjects
        // Ultralytics writes "Ultralytics YOLO26s-seg model trained on ..." into the description.
        let description = model.modelDescription.metadata[.description] as? String ?? ""
        let variant = description.split(separator: " ").first { $0.hasPrefix("YOLO") }.map(String.init) ?? "YOLO-seg"
        self.modelName = "\(variant) (Core ML)"
    }

    public var name: String { modelName }

    /// Last detect's Vision + Core ML time in milliseconds. Safe to read from any thread.
    public var lastInferenceMilliseconds: Double { timer.milliseconds }

    /// Apple, VNCoreMLRequest: "Vision infers that an VNCoreMLModel object is a predictor model if that model predicts
    /// multiple features" (its results are VNCoreMLFeatureValueObservation); "Vision forwards all MLMultiArray values
    /// from Core ML models as-is". Apple, VNImageCropAndScaleOption.scaleFill: "scales the image to fill the input
    /// dimensions, resizing it if necessary", so oriented pixel (x, y) is input pixel (x / W * 640, y / H * 640).
    public func detect(in image: CVPixelBuffer, orientation: ImageOrientation) async throws -> [Detection] {
        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .scaleFill
        let handler = VNImageRequestHandler(cvPixelBuffer: image, orientation: orientation.cgOrientation, options: [:])
        let start = ContinuousClock.now
        try handler.perform([request])
        let elapsed = ContinuousClock.now - start
        timer.set(Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15)

        let arrays = (request.results ?? []).compactMap { ($0 as? VNCoreMLFeatureValueObservation)?.featureValue.multiArrayValue }
        guard let rowArray = arrays.first(where: { $0.shape.count == 3 }),
              let protoArray = arrays.first(where: { $0.shape.count == 4 }) else { throw Failure.unexpectedOutputs }

        let rowCount = rowArray.shape[1].intValue
        let protoSize = protoArray.shape[2].intValue
        let rows = YOLOSegmentDecoder.rows(output: try Self.floats(from: rowArray), count: rowCount, minConfidence: minConfidence)
            .filter { targetLabels.contains(classNames[$0.classIndex] ?? "") }
            .sorted { $0.confidence > $1.confidence }
            .prefix(maxObjects)
        guard !rows.isEmpty else { return [] }

        let protos = try Self.floats(from: protoArray)
        var detections: [Detection] = []
        for row in rows {
            let oriented = YOLOSegmentDecoder.mask(for: row, protos: protos, protoSize: protoSize)
            let native = MaskMapping.nativeMask(oriented, orientation: orientation)
            guard let box = MaskMapping.bounds(of: native), let label = classNames[row.classIndex] else { continue }
            detections.append(Detection(label: label, confidence: row.confidence, box: box, mask: native))
        }
        return detections
    }

    /// Copies an MLMultiArray into a row-major [Float], honouring dataType (Float16, Float32, Double, Int32) and strides.
    public static func floats(from array: MLMultiArray) throws -> [Float] {
        let shape = array.shape.map(\.intValue)
        let strides = array.strides.map(\.intValue)
        let total = shape.reduce(1, *)
        var out = [Float](repeating: 0, count: total)
        func copy<T>(_ type: T.Type, _ convert: (T) -> Float, from raw: UnsafeRawBufferPointer) {
            let base = raw.baseAddress!.assumingMemoryBound(to: T.self)
            // Row-major strides: a flat copy is enough.
            var expected = 1, contiguous = true
            for d in stride(from: shape.count - 1, through: 0, by: -1) {
                if shape[d] > 1 && strides[d] != expected { contiguous = false }
                expected *= shape[d]
            }
            if contiguous {
                for i in 0..<total { out[i] = convert(base[i]) }
                return
            }
            var index = [Int](repeating: 0, count: shape.count)
            for i in 0..<total {
                var offset = 0
                for d in 0..<shape.count { offset += index[d] * strides[d] }
                out[i] = convert(base[offset])
                var d = shape.count - 1
                while d >= 0 { index[d] += 1; if index[d] < shape[d] { break }; index[d] = 0; d -= 1 }
            }
        }
        var unsupported = false
        array.withUnsafeBytes { raw in
            switch array.dataType {
            case .float32: copy(Float.self, { $0 }, from: raw)
            case .double: copy(Double.self, { Float($0) }, from: raw)
            case .int32: copy(Int32.self, { Float($0) }, from: raw)
            case .float16: copy(UInt16.self, halfToFloat, from: raw)
            default: unsupported = true
            }
        }
        if unsupported { throw Failure.unexpectedOutputs }
        return out
    }
}

/// IEEE 754 half to Float by hand: Swift's `Float16` is not available on macOS x86_64.
func halfToFloat(_ bits: UInt16) -> Float {
    let sign: Float = bits & 0x8000 != 0 ? -1 : 1
    let exponent = Int((bits >> 10) & 0x1F)
    let fraction = Float(bits & 0x3FF)
    switch exponent {
    case 0: return sign * fraction * Float(sign: .plus, exponent: -24, significand: 1)
    case 0x1F: return fraction == 0 ? sign * .infinity : .nan
    default: return sign * (1 + fraction / 1024) * Float(sign: .plus, exponent: exponent - 15, significand: 1)
    }
}
