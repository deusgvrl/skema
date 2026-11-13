import CoreGraphics
import CoreVideo
import MeasureKit
import MeasureKitVision
import Vision

/// Outlines the one object the photographer tapped as the subject (A10-62 follow-up).
nonisolated protocol SubjectSegmenting: Sendable {
    /// The mask of the object under `point` (fractions of the native camera picture, top-left), in the native
    /// picture's frame, like `EquipmentDetection.mask`. Nil when the tap is on the background or nothing was found.
    func mask(atNative point: CGPoint, in frame: ScanFrame) async -> InstanceMask?
}

/// Apple's subject lifting (`VNGenerateForegroundInstanceMaskRequest`): finds the foreground objects in the picture
/// and labels each one's pixels. No model file; the instance under the tap is the subject.
nonisolated final class SubjectSegmenter: SubjectSegmenting {
    /// `@concurrent` so Vision runs off the main actor, like `EquipmentDetector.detect`.
    @concurrent
    func mask(atNative point: CGPoint, in frame: ScanFrame) async -> InstanceMask? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.image, orientation: frame.orientation.cgOrientation)
        guard (try? handler.perform([request])) != nil, let result = request.results?.first else { return nil }
        let buffer = result.instanceMask
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        var labels = [UInt8](repeating: 0, count: width * height)
        for row in 0..<height {
            let source = base.advanced(by: row * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for column in 0..<width {
                labels[row * width + column] = source[column]
            }
        }
        return Self.mask(fromLabels: labels, width: width, height: height,
                         tap: Self.orientedPoint(fromNative: point, orientation: frame.orientation),
                         orientation: frame.orientation)
    }

    /// A tap on the native picture as a tap on the oriented picture (the one Vision looks at), both as fractions.
    /// The reverse of `MaskMapping.nativeMask`: for `.right`, oriented (ox, oy) lands on native (oy, W - 1 - ox).
    static func orientedPoint(fromNative point: CGPoint, orientation: ImageOrientation) -> CGPoint {
        switch orientation {
        case .up: point
        case .right: CGPoint(x: 1 - point.y, y: point.x)
        case .left: CGPoint(x: point.y, y: 1 - point.x)
        case .down: CGPoint(x: 1 - point.x, y: 1 - point.y)
        }
    }

    /// The pixels of the instance under `tap` (fractions of the oriented picture) as a mask in the native frame.
    /// Label 0 is the background, so a tap on it gives nil.
    static func mask(fromLabels labels: [UInt8], width: Int, height: Int, tap: CGPoint,
                     orientation: ImageOrientation) -> InstanceMask? {
        guard width > 0, height > 0, labels.count == width * height else { return nil }
        let column = min(width - 1, max(0, Int(tap.x * Double(width))))
        let row = min(height - 1, max(0, Int(tap.y * Double(height))))
        let label = labels[row * width + column]
        guard label != 0 else { return nil }
        let oriented = InstanceMask(width: width, height: height, pixels: labels.map { $0 == label ? 1 : 0 })
        return MaskMapping.nativeMask(oriented, orientation: orientation)
    }
}
