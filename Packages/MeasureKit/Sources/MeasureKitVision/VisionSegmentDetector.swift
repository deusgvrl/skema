import CoreGraphics
import CoreVideo
import Vision
import MeasureKit

public struct VisionSegmentDetector: ObjectDetector {
    public let targetLabels: Set<String>
    public let minConfidence: Float
    public let maxObjects: Int

    public init(targetLabels: Set<String> = VisionDetector.defaultTargets, minConfidence: Float = 0.3, maxObjects: Int = 6) {
        self.targetLabels = targetLabels
        self.minConfidence = minConfidence
        self.maxObjects = maxObjects
    }

    public var name: String { "Apple Vision (foreground instances + classify)" }

    /// 1. Foreground instances. 2. Classify each instance in its bounds. 3. Keep target labels.
    /// 4. Detection with the mask in native coordinates; `box` is the mask's bounds.
    public func detect(in image: CVPixelBuffer, orientation: ImageOrientation) async throws -> [Detection] {
        var detections: [Detection] = []
        for oriented in try Self.instanceMasks(in: image, orientation: orientation).prefix(maxObjects) {
            // Bounds in the oriented image (top-left) -> Vision's lower-left origin for regionOfInterest.
            guard let ob = MaskMapping.bounds(of: oriented) else { continue }
            let region = CGRect(x: ob.x, y: 1 - ob.y - ob.height, width: ob.width, height: ob.height)
            let classifications = try VisionDetector.classify(image, orientation: orientation, region: region)
            guard let pick = LabelPicker.pick(classifications, targets: targetLabels, minConfidence: minConfidence) else { continue }
            let native = MaskMapping.nativeMask(oriented, orientation: orientation)
            guard let box = MaskMapping.bounds(of: native) else { continue }
            detections.append(Detection(label: pick.label, confidence: pick.confidence, box: box, mask: native))
        }
        return detections
    }

    /// One mask per foreground instance, in the ORIENTED image (see `MaskMapping`), 1 inside the instance.
    ///
    /// Apple, VNGenerateForegroundInstanceMaskRequest: "generates an instance mask of noticable objects to
    /// separate from the background". VNInstanceMaskObservation.allInstances: "all instances, excluding the
    /// background". generateMask(forInstances:): "Creates a low-resolution mask from the instances you specify."
    /// The docs do not state the mask's frame; the synthetic-image test shows it matches the oriented image
    /// (the orientation passed to the handler).
    public static func instanceMasks(in image: CVPixelBuffer, orientation: ImageOrientation) throws -> [InstanceMask] {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: image, orientation: orientation.cgOrientation, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first else { return [] }
        return try observation.allInstances.map { index in
            try inferMask(from: observation.generateMask(forInstances: IndexSet(integer: index)))
        }
    }

    /// Reads a one-channel mask buffer (8-bit or 32-bit float) into 0/1 pixels.
    private static func inferMask(from buffer: CVPixelBuffer) -> InstanceMask {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let base = CVPixelBufferGetBaseAddress(buffer)!
        let isFloat = CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent32Float
        var pixels = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            let row = base + y * stride
            for x in 0..<w {
                let on = isFloat ? row.assumingMemoryBound(to: Float.self)[x] > 0.5
                                 : row.assumingMemoryBound(to: UInt8.self)[x] != 0
                pixels[y * w + x] = on ? 1 : 0
            }
        }
        return InstanceMask(width: w, height: h, pixels: pixels)
    }
}
