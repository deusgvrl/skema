import Testing
@testable import MeasureKitVision
import MeasureKit

/// A10-60 test case 10: masks are built the Ultralytics way (ultralytics/utils/ops.py, `process_mask` with
/// upsample=True): logits at proto size → bilinear resize to the input size → on where the logit > 0 → crop to the box.
@Suite struct MaskUpsampleTests {
    // One prototype whose value at proto pixel (px, py) is px - py, coefficient 1.
    // Bilinear resize (align_corners = false, as PyTorch's F.interpolate): an output pixel x reads proto
    // position (x + 0.5) / 4 - 0.5, so away from the border the logit at output (x, y) is (x - y) / 4.
    // It is on when x > y. So row 320 starts at x = 321 and row 321 starts at x = 322: 1-pixel steps.
    // The old way (threshold at 160 x 160, then each proto pixel covers 4 x 4) starts rows 320–323 all at x = 324.
    private let slanted: [Float] = (0..<160 * 160).map { Float($0 % 160 - $0 / 160) }

    private func firstOn(_ mask: InstanceMask, row y: Int) -> Int? {
        (0..<mask.width).first { mask.pixels[y * mask.width + $0] == 1 }
    }

    @Test func maskIsInputSizeWithOnePixelStepsOnASlantedEdge() {
        let row = YOLORow(x1: 0, y1: 0, x2: 640, y2: 640, confidence: 0.9, classIndex: 0, coefficients: [1])
        let mask = YOLOSegmentDecoder.upsampledMask(for: row, protos: slanted, protoSize: 160, inputSize: 640)
        #expect(mask.width == 640 && mask.height == 640)
        #expect(firstOn(mask, row: 320) == 321)
        #expect(firstOn(mask, row: 321) == 322)
        #expect(firstOn(mask, row: 322) == 323)
    }

    // The box crop uses x1 <= x < x2 and y1 <= y < y2 in 640-pixel coordinates (Ultralytics `crop_mask`).
    @Test func maskIsCutToTheBoxAtInputResolution() {
        let allOn = [Float](repeating: 1, count: 160 * 160)
        let row = YOLORow(x1: 100, y1: 50, x2: 200, y2: 60, confidence: 0.9, classIndex: 0, coefficients: [1])
        let mask = YOLOSegmentDecoder.upsampledMask(for: row, protos: allOn, protoSize: 160, inputSize: 640)
        let onPixels = mask.pixels.enumerated().filter { $0.element == 1 }.map { ($0.offset % 640, $0.offset / 640) }
        #expect(onPixels.count == 100 * 10)
        #expect(onPixels.allSatisfy { (100..<200).contains($0.0) && (50..<60).contains($0.1) })
    }
}
