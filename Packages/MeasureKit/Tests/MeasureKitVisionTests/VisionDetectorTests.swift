import Testing
import CoreVideo
import CoreGraphics
import ImageIO
import Foundation
@testable import MeasureKitVision

// MARK: helpers

/// Black BGRA pixel buffer `width` x `height` with a white rectangle at native pixel rect `rect` (origin top-left).
private func syntheticBuffer(width: Int, height: Int, whiteRect rect: CGRect) -> CVPixelBuffer {
    var pb: CVPixelBuffer?
    CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &pb)
    let buffer = pb!
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    for y in 0..<height {
        for x in 0..<width {
            let inside = CGFloat(x) >= rect.minX && CGFloat(x) < rect.maxX && CGFloat(y) >= rect.minY && CGFloat(y) < rect.maxY
            let v: UInt8 = inside ? 255 : 0
            let p = base + y * stride + x * 4
            p[0] = v; p[1] = v; p[2] = v; p[3] = 255
        }
    }
    return buffer
}

private func iou(_ a: NormalizedBox, _ b: NormalizedBox) -> Double {
    let ix = max(0, min(a.x + a.width, b.x + b.width) - max(a.x, b.x))
    let iy = max(0, min(a.y + a.height, b.y + b.height) - max(a.y, b.y))
    let inter = ix * iy
    return inter / (a.width * a.height + b.width * b.height - inter)
}

private func pixelBuffer(from image: CGImage) -> CVPixelBuffer {
    var pb: CVPixelBuffer?
    CVPixelBufferCreate(nil, image.width, image.height, kCVPixelFormatType_32BGRA, nil, &pb)
    let buffer = pb!
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: image.width, height: image.height,
                        bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return buffer
}

private func fixturePhotos() -> [URL] {
    guard let dir = Bundle.module.url(forResource: "Fixtures", withExtension: nil),
          let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
    return files.filter { ["jpg", "jpeg"].contains($0.pathExtension.lowercased()) }.sorted { $0.path < $1.path }
}

// MARK: tests

@Suite struct VisionDetectorTests {
    // Required test 4. Native image 320x160 (landscape) with a white rectangle at native x 40..120, y 20..100,
    // i.e. normalized (0.125, 0.125, 0.25, 0.5). Declared `.right`: the oriented image is 160x320 (portrait).
    @Test func saliencyBoxMapsBackToNativeRectangle() async throws {
        let known = NormalizedBox(x: 0.125, y: 0.125, width: 0.25, height: 0.5)
        let buffer = syntheticBuffer(width: 320, height: 160, whiteRect: CGRect(x: 40, y: 20, width: 80, height: 80))
        let boxes = try VisionDetector.salientBoxes(in: buffer, orientation: .right)
        #expect(!boxes.isEmpty, "Vision found no salient object in the synthetic image")
        let best = boxes.map { VisionBoxMapping.nativeBox(fromVision: $0, orientation: .right) }
            .max { iou($0, known) < iou($1, known) }!
        print("synthetic saliency (.right): mapped native box \(best), IoU with known = \(iou(best, known))")
        #expect(iou(best, known) > 0.5)
        // Same Vision output mapped with the wrong orientation must overlap clearly worse,
        // so the test really depends on the mapping.
        let wrong = VisionBoxMapping.nativeBox(fromVision: boxes[0], orientation: .up)
        #expect(iou(wrong, known) < iou(best, known))
    }

    @Test func defaultTargetsAreTheEightAgreedLabels() {
        #expect(VisionDetector.defaultTargets == ["bottle", "cup", "vase", "bowl", "book", "laptop", "scissors", "clock"])
        #expect(VisionDetector().name == "Apple Vision (saliency + classify)")
    }

    // Required test 5. Skips while Fixtures/ has no photos.
    @Test(.enabled(if: !fixturePhotos().isEmpty, "Fixtures/ has no photos yet: Amadeus adds <label>_<anything>.jpg files"))
    func detectsLabelInEachFixturePhoto() async throws {
        for url in fixturePhotos() {
            let label = url.deletingPathExtension().lastPathComponent.split(separator: "_").first.map(String.init) ?? ""
            let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            // CGImageSource returns the stored (native) pixels; the EXIF orientation says how to turn them upright.
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let raw = (props?[kCGImagePropertyOrientation] as? UInt32) ?? 1
            let orientation: ImageOrientation = { switch raw { case 3: .down; case 6: .right; case 8: .left; default: .up } }()
            let detections = try await VisionDetector().detect(in: pixelBuffer(from: image), orientation: orientation)
            #expect(detections.contains { $0.label == label }, "\(url.lastPathComponent): expected '\(label)', got \(detections.map(\.label))")
        }
    }
}
