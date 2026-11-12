import CoreGraphics
import Foundation
import MeasureKit

extension MaskColor {
    /// White for pending items, iOS system green (light mode) for accepted ones, until Sketch R03 is checked.
    var rgb: SIMD3<UInt8> {
        switch self {
        case .white: SIMD3(255, 255, 255)
        case .green: SIMD3(52, 199, 89)
        }
    }
}

/// A detection mask as a tinted, see-through picture laid over the camera (A10-62, cases M1–M6).
/// The mask covers the whole sideways camera picture. It is turned upright the same way as the picture,
/// and fills the screen the same way, so it lines up with the tags from `ScanOverlay.screenPoint`.
nonisolated enum MaskImage {
    /// How see-through a mask is (Amadeus, 12 Nov: 50% until Sketch R03 is checked).
    static let opacity = 0.5

    /// The upright picture of `mask`: its 1s in `color` at `opacity`, its 0s fully see-through.
    /// Nil when the mask has no 1s, so nothing is drawn.
    static func image(of mask: InstanceMask, color: MaskColor) -> CGImage? {
        guard mask.width > 0, mask.height > 0, mask.pixels.contains(where: { $0 != 0 }) else { return nil }
        let width = mask.height
        let height = mask.width
        let alpha = UInt8((255 * opacity).rounded())
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0..<mask.height {
            for column in 0..<mask.width where mask.pixels[row * mask.width + column] != 0 {
                let upright = uprightPixel(column: column, row: row, maskHeight: mask.height)
                let start = (upright.row * width + upright.column) * 4
                bytes[start] = color.rgb.x
                bytes[start + 1] = color.rgb.y
                bytes[start + 2] = color.rgb.z
                bytes[start + 3] = alpha
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Where the upright camera picture sits on the screen: made bigger until it covers the screen,
    /// centred, so the sides (or top and bottom) that don't fit are cut off. Same rule as `ScanOverlay.screenPoint`.
    static func pictureRect(camera: CameraModel, screenSize: CGSize) -> CGRect {
        let upright = CGSize(width: CGFloat(camera.imageResolution.y), height: CGFloat(camera.imageResolution.x))
        guard upright.width > 0, upright.height > 0 else { return .zero }
        let scale = max(screenSize.width / upright.width, screenSize.height / upright.height)
        let size = CGSize(width: upright.width * scale, height: upright.height * scale)
        return CGRect(x: (screenSize.width - size.width) / 2, y: (screenSize.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    /// The screen point of the centre of one sideways mask pixel, after it is turned upright and laid over the picture.
    static func screenPoint(ofMaskPixel column: Int, _ row: Int, mask: InstanceMask, camera: CameraModel,
                            screenSize: CGSize) -> CGPoint {
        let rect = pictureRect(camera: camera, screenSize: screenSize)
        let upright = uprightPixel(column: column, row: row, maskHeight: mask.height)
        let uprightWidth = CGFloat(mask.height)
        let uprightHeight = CGFloat(mask.width)
        return CGPoint(x: rect.minX + (CGFloat(upright.column) + 0.5) / uprightWidth * rect.width,
                       y: rect.minY + (CGFloat(upright.row) + 0.5) / uprightHeight * rect.height)
    }

    /// A sideways mask pixel's place once the mask is turned upright (a quarter turn to the right, like the picture).
    /// The upright mask is `maskHeight` wide. Same turn as `ScanOverlay.screenPoint`: (u, v) becomes (H - v, u).
    static func uprightPixel(column: Int, row: Int, maskHeight: Int) -> (column: Int, row: Int) {
        return (column: maskHeight - 1 - row, row: column)
    }
}
