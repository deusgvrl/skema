#if DEBUG
import CoreGraphics
import CoreImage
import MeasureKit
import MeasureKitVision

/// Draws the masks on a clear picture the size of the camera frame, turned upright (Debug-only test screen).
/// The live camera is shown underneath by `ARSCNView`. Masks are in the camera's native orientation and cover
/// the whole frame (scaleFill), so each is stretched to the frame's size before the picture is turned.
nonisolated enum DebugOverlayRenderer {
    private static let context = CIContext()

    @concurrent
    static func render(_ frame: ScanFrame, _ detections: [EquipmentDetection]) async -> CGImage? {
        let extent = CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(frame.image),
                            height: CVPixelBufferGetHeight(frame.image))
        var picture = CIImage(color: .clear).cropped(to: extent)
        for detection in detections {
            guard let mask = maskImage(detection.mask, color: color(for: detection.kind)) else { continue }
            let scale = CGAffineTransform(scaleX: extent.width / CGFloat(detection.mask.width),
                                          y: extent.height / CGFloat(detection.mask.height))
            picture = CIImage(cgImage: mask).transformed(by: scale).composited(over: picture)
        }
        let upright = picture.oriented(frame.orientation.cgOrientation)
        return context.createCGImage(upright, from: upright.extent)
    }

    private struct Color {
        let red: UInt8, green: UInt8, blue: UInt8
    }

    private static func color(for kind: EquipmentKind) -> Color {
        switch kind {
        case .studioLighting: Color(red: 255, green: 204, blue: 0)
        case .camera: Color(red: 0, green: 200, blue: 255)
        }
    }

    /// The mask as a see-through colored picture: on pixels at 45% opacity, off pixels clear.
    private static func maskImage(_ mask: InstanceMask, color: Color) -> CGImage? {
        let alpha: Float = 0.45
        let premultiplied = (UInt8(Float(color.red) * alpha), UInt8(Float(color.green) * alpha),
                             UInt8(Float(color.blue) * alpha), UInt8(255 * alpha))
        var bytes = [UInt8](repeating: 0, count: mask.width * mask.height * 4)
        for index in mask.pixels.indices where mask.pixels[index] == 1 {
            bytes[index * 4] = premultiplied.0
            bytes[index * 4 + 1] = premultiplied.1
            bytes[index * 4 + 2] = premultiplied.2
            bytes[index * 4 + 3] = premultiplied.3
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: mask.width, height: mask.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: mask.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
#endif
