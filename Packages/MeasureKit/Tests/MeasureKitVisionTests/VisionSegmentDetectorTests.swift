import Testing
import CoreVideo
import CoreGraphics
import ImageIO
import Foundation
@testable import MeasureKitVision

/// Dark, softly shaded background with bright, shaded ellipses inscribed in `rects` (native pixels, top-left origin).
/// Plain flat rectangles gave Vision no instances (checked 4 Nov 2026), so the shapes are shaded like objects.
private func twoShapes(width: Int, height: Int, rects: [CGRect]) -> CVPixelBuffer {
    var pb: CVPixelBuffer?
    CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &pb)
    let buffer = pb!
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
                        bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    // CGContext origin is bottom-left; flip so we can think top-left.
    ctx.translateBy(x: 0, y: CGFloat(height)); ctx.scaleBy(x: 1, y: -1)
    let space = CGColorSpaceCreateDeviceRGB()
    let bg = CGGradient(colorsSpace: space, colors: [CGColor(red: 0.05, green: 0.08, blue: 0.1, alpha: 1),
                                                      CGColor(red: 0.15, green: 0.12, blue: 0.1, alpha: 1)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: .zero, end: CGPoint(x: width, y: height), options: [])
    let fg = CGGradient(colorsSpace: space, colors: [CGColor(red: 1, green: 0.9, blue: 0.5, alpha: 1),
                                                      CGColor(red: 0.8, green: 0.3, blue: 0.2, alpha: 1)] as CFArray, locations: [0, 1])!
    for r in rects {
        ctx.saveGState()
        ctx.addEllipse(in: r); ctx.clip()
        ctx.drawRadialGradient(fg, startCenter: CGPoint(x: r.midX - r.width * 0.2, y: r.midY - r.height * 0.2), startRadius: 0,
                               endCenter: CGPoint(x: r.midX, y: r.midY), endRadius: max(r.width, r.height) * 0.6, options: [.drawsAfterEndLocation])
        ctx.restoreGState()
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

@Suite struct VisionSegmentDetectorTests {
    @Test func nameAndDefaults() {
        #expect(VisionSegmentDetector().name == "Apple Vision (foreground instances + classify)")
        #expect(VisionSegmentDetector().maxObjects == 6)
    }

    // Required test 3. Native 320x160 with two white rectangles, declared `.right` (oriented image 160x320).
    // Apple: VNGenerateForegroundInstanceMaskRequest "generates an instance mask of noticable objects to
    // separate from the background"; instanceMask: "A 0 represents the background, and all other values
    // represent the indices of the instances."; generateMask(forInstances:) "Creates a low-resolution mask".
    // The docs do not say which frame the mask buffer is in; this test measures it.
    @Test func syntheticShapesGiveInstancesThatMatchKnownRectangles() throws {
        let knownPx = [CGRect(x: 30, y: 20, width: 70, height: 50), CGRect(x: 200, y: 90, width: 80, height: 50)]
        let known = knownPx.map { NormalizedBox(x: $0.minX / 320, y: $0.minY / 160, width: $0.width / 320, height: $0.height / 160) }
        let buffer = twoShapes(width: 320, height: 160, rects: knownPx)
        let oriented = try VisionSegmentDetector.instanceMasks(in: buffer, orientation: .right)
        guard !oriented.isEmpty else {
            Issue.record("SKIP-WORTHY: Vision found no foreground instances on synthetic rectangles")
            return
        }
        print("synthetic instances (.right): \(oriented.count), mask sizes \(oriented.map { "\($0.width)x\($0.height)" })")
        for mask in oriented {
            let native = MaskMapping.nativeMask(mask, orientation: .right)
            let box = try #require(MaskMapping.bounds(of: native))
            let best = known.map { iou(box, $0) }.max()!
            let wrong = MaskMapping.bounds(of: MaskMapping.nativeMask(mask, orientation: .up)).map { b in known.map { iou(b, $0) }.max()! } ?? 0
            print("  native box \(box): best IoU \(best); IoU if mapped as .up: \(wrong)")
            #expect(best > 0.5)
            #expect(wrong < best)
        }
    }

    // Required test 4. Skips while Fixtures/ has no photos.
    @Test(.enabled(if: !fixturePhotos().isEmpty, "Fixtures/ has no photos yet: Amadeus adds <label>_<anything>.jpg files"))
    func segmentDetectorFindsLabelInEachFixturePhoto() async throws {
        for url in fixturePhotos() {
            let label = url.deletingPathExtension().lastPathComponent.split(separator: "_").first.map(String.init) ?? ""
            let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let raw = (props?[kCGImagePropertyOrientation] as? UInt32) ?? 1
            let orientation: ImageOrientation = { switch raw { case 3: .down; case 6: .right; case 8: .left; default: .up } }()
            let detections = try await VisionSegmentDetector().detect(in: pixelBuffer(from: image), orientation: orientation)
            #expect(detections.contains { $0.label == label }, "\(url.lastPathComponent): expected '\(label)', got \(detections.map(\.label))")
            for d in detections { #expect(d.mask != nil && d.box == MaskMapping.bounds(of: d.mask!)) }
        }
    }
}
