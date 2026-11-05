import Testing
import CoreML
import CoreVideo
import CoreGraphics
import ImageIO
import Foundation
import MeasureKit
@testable import MeasureKitVision

/// The real 40 MB model, compiled once per test run (`MLModel.compileModel(at:)`) and shared by the tests below.
private enum RealModel {
    static let url: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()               // MeasureKitVisionTests
        .appendingPathComponent("../../../LidarMeasure/Models/yolo26s-seg.mlpackage").standardized
    static let model: MLModel = {
        let compiled = try! MLModel.compileModel(at: url)
        return try! MLModel(contentsOf: compiled)
    }()
}

private struct Reference: Decodable {
    struct Det: Decodable { let cls: String; let conf: Double; let xyxy_px: [Double] }
    let image_size: [Double]
    let detections: [Det]
    /// Reference boxes as normalized boxes in the UPRIGHT (oriented) image.
    var boxes: [(label: String, box: NormalizedBox)] {
        detections.map { d in
            (d.cls, NormalizedBox(x: d.xyxy_px[0] / image_size[0], y: d.xyxy_px[1] / image_size[1],
                                  width: (d.xyxy_px[2] - d.xyxy_px[0]) / image_size[0],
                                  height: (d.xyxy_px[3] - d.xyxy_px[1]) / image_size[1]))
        }
    }
}

private func loadReference() throws -> Reference {
    let url = try #require(Bundle.module.url(forResource: "bus_reference", withExtension: "json", subdirectory: "YOLOFixtures"))
    return try JSONDecoder().decode(Reference.self, from: Data(contentsOf: url))
}

private func iou(_ a: NormalizedBox, _ b: NormalizedBox) -> Double {
    let ix = max(0, min(a.x + a.width, b.x + b.width) - max(a.x, b.x))
    let iy = max(0, min(a.y + a.height, b.y + b.height) - max(a.y, b.y))
    let inter = ix * iy
    return inter / (a.width * a.height + b.width * b.height - inter)
}

/// bus.jpg as an upright BGRA buffer (810 x 1080).
private func busUpright() throws -> CVPixelBuffer {
    let url = try #require(Bundle.module.url(forResource: "bus", withExtension: "jpg", subdirectory: "YOLOFixtures"))
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let buffer = makeBuffer(width: image.width, height: image.height)
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: image.width, height: image.height,
                        bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return buffer
}

private func makeBuffer(width: Int, height: Int) -> CVPixelBuffer {
    var pb: CVPixelBuffer?
    CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &pb)
    return pb!
}

/// The upright buffer rotated 90 degrees counter-clockwise: the encoded data of a phone held in portrait
/// (Apple, CGImagePropertyOrientation.right: "The encoded image data is rotated 90 degrees counter-clockwise
/// from the image's intended display orientation."). Upright pixel (ox, oy) of a W-wide image lands at (oy, W - 1 - ox).
private func rotatedForRight(_ upright: CVPixelBuffer) -> CVPixelBuffer {
    let w = CVPixelBufferGetWidth(upright), h = CVPixelBufferGetHeight(upright)
    let out = makeBuffer(width: h, height: w)
    CVPixelBufferLockBaseAddress(upright, .readOnly); CVPixelBufferLockBaseAddress(out, [])
    defer { CVPixelBufferUnlockBaseAddress(upright, .readOnly); CVPixelBufferUnlockBaseAddress(out, []) }
    let src = CVPixelBufferGetBaseAddress(upright)!, dst = CVPixelBufferGetBaseAddress(out)!
    let sBytes = CVPixelBufferGetBytesPerRow(upright), dBytes = CVPixelBufferGetBytesPerRow(out)
    for oy in 0..<h {
        for ox in 0..<w {
            (dst + (w - 1 - ox) * dBytes + oy * 4).copyMemory(from: src + oy * sBytes + ox * 4, byteCount: 4)
        }
    }
    return out
}

@Suite struct YOLOSegmentDetectorTests {
    // Required test 4. Reference boxes are PyTorch output, not measurement ground truth.
    @Test func realModelFindsBusAndPersonsLikePyTorch() async throws {
        let detector = try YOLOSegmentDetector(model: RealModel.model, targetLabels: ["bus", "person"])
        let detections = try await detector.detect(in: try busUpright(), orientation: .up)
        #expect(detections.contains { $0.label == "bus" })
        #expect(detections.filter { $0.label == "person" }.count >= 3)
        for ref in try loadReference().boxes {
            let best = detections.filter { $0.label == ref.label }.map { iou($0.box, ref.box) }.max() ?? 0
            #expect(best > 0.7, "no \(ref.label) with IoU > 0.7 (best \(best))")
        }
        for d in detections {
            let mask = try #require(d.mask)
            let on = mask.pixels.enumerated().filter { $0.element != 0 }.map(\.offset)
            #expect(!on.isEmpty, "\(d.label) mask is empty")
            // Mask frame is the native image; here native == oriented. Mostly inside its own detection box
            // (slightly grown: the box is the mask's bounds, so it must be fully inside by construction;
            // the check that has teeth is the reference box below).
            let ref = try #require(try loadReference().boxes.filter { $0.label == d.label }
                .max { iou($0.box, d.box) < iou($1.box, d.box) })
            let inside = on.filter { i in
                let x = (Double(i % mask.width) + 0.5) / Double(mask.width), y = (Double(i / mask.width) + 0.5) / Double(mask.height)
                return x >= ref.box.x - 0.02 && x <= ref.box.x + ref.box.width + 0.02
                    && y >= ref.box.y - 0.02 && y <= ref.box.y + ref.box.height + 0.02
            }.count
            #expect(Double(inside) / Double(on.count) > 0.9, "\(d.label) mask leaks outside its reference box")
        }
    }

    // Required test 5. The same picture, pixels rotated so the upright view needs `.right`.
    // Expected native box of an upright box (x, y, w, h): (y, 1 - x - w, h, w), the same formula as
    // VisionBoxMapping `.right`, written out here by hand so the test does not call the code under test.
    @Test func rightOrientedBufferGivesTheSameBoxesInNativeCoordinates() async throws {
        let detector = try YOLOSegmentDetector(model: RealModel.model, targetLabels: ["bus", "person"])
        let native = rotatedForRight(try busUpright())
        #expect(CVPixelBufferGetWidth(native) == 1080 && CVPixelBufferGetHeight(native) == 810)
        let detections = try await detector.detect(in: native, orientation: .right)
        for ref in try loadReference().boxes {
            let expected = NormalizedBox(x: ref.box.y, y: 1 - ref.box.x - ref.box.width, width: ref.box.height, height: ref.box.width)
            let best = detections.filter { $0.label == ref.label }.map { iou($0.box, expected) }.max() ?? 0
            #expect(best > 0.7, "no native \(ref.label) with IoU > 0.7 (best \(best))")
        }
        // Each native mask must sit inside the expected NATIVE box of its reference (the mask was rotated too).
        let refs = try loadReference().boxes.map { r in
            (label: r.label, box: NormalizedBox(x: r.box.y, y: 1 - r.box.x - r.box.width, width: r.box.height, height: r.box.width))
        }
        for d in detections {
            let mask = try #require(d.mask)
            let ref = try #require(refs.filter { $0.label == d.label }.max { iou($0.box, d.box) < iou($1.box, d.box) })
            let on = mask.pixels.enumerated().filter { $0.element != 0 }.map(\.offset)
            #expect(!on.isEmpty)
            let inside = on.filter { i in
                let x = (Double(i % mask.width) + 0.5) / Double(mask.width), y = (Double(i / mask.width) + 0.5) / Double(mask.height)
                return x >= ref.box.x - 0.02 && x <= ref.box.x + ref.box.width + 0.02
                    && y >= ref.box.y - 0.02 && y <= ref.box.y + ref.box.height + 0.02
            }.count
            #expect(Double(inside) / Double(on.count) > 0.9, "\(d.label) native mask leaks outside its reference box")
        }
    }

    // Reading model outputs: Float16 and non-contiguous strides must come out as plain row-major Floats.
    @Test func floatsReadsFloat16AndStridedArrays() throws {
        let half = try MLMultiArray(shape: [1, 2, 3], dataType: .float16)
        for i in 0..<6 { half[i] = NSNumber(value: Float(i) * 0.5 - 1) }   // -1 ... 1.5, exact in half precision
        #expect(try YOLOSegmentDetector.floats(from: half) == [-1, -0.5, 0, 0.5, 1, 1.5])

        // 2 x 3 view over a buffer padded to 4 columns per row.
        let storage = UnsafeMutablePointer<Float>.allocate(capacity: 8)
        defer { storage.deallocate() }
        storage.initialize(from: [1, 2, 3, -99, 4, 5, 6, -99], count: 8)
        let strided = try MLMultiArray(dataPointer: storage, shape: [2, 3], dataType: .float32, strides: [4, 1])
        #expect(try YOLOSegmentDetector.floats(from: strided) == [1, 2, 3, 4, 5, 6])
    }

    @Test func nameAndInferenceTimeComeFromTheModel() async throws {
        let detector = try YOLOSegmentDetector(model: RealModel.model)
        #expect(detector.name == "YOLO26s-seg (Core ML)")
        #expect(detector.lastInferenceMilliseconds == 0)
        _ = try await detector.detect(in: try busUpright(), orientation: .up)
        #expect(detector.lastInferenceMilliseconds > 0)
    }
}
