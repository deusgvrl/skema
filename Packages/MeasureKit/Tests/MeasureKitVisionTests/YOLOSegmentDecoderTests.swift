import Testing
@testable import MeasureKitVision
import MeasureKit

@Suite struct YOLOSegmentDecoderTests {
    // Required test 1. Row layout (Verified model facts): x1, y1, x2, y2, conf, class index, 32 coefficients.
    @Test func rowsDecodesFieldsAndDropsLowConfidence() throws {
        func row(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float, _ conf: Float, _ cls: Float, coefStart: Float) -> [Float] {
            [x1, y1, x2, y2, conf, cls] + (0..<32).map { coefStart + Float($0) }
        }
        let buffer = row(10, 20, 110, 220, 0.9, 5, coefStart: 0)
                   + row(1, 2, 3, 4, 0.2, 7, coefStart: 100)       // below threshold
                   + row(300, 310, 400, 500, 0.35, 0, coefStart: 200) // exactly at threshold: kept (>=)
        let rows = YOLOSegmentDecoder.rows(output: buffer, count: 3, minConfidence: 0.35)
        try #require(rows.count == 2)
        #expect(rows[0] == YOLORow(x1: 10, y1: 20, x2: 110, y2: 220, confidence: 0.9, classIndex: 5,
                                   coefficients: (0..<32).map { Float($0) }))
        #expect(rows[1].classIndex == 0)
        #expect(rows[1].x2 == 400 && rows[1].y2 == 500)
        #expect(rows[1].coefficients.first == 200 && rows[1].coefficients.last == 231)
    }

    // Required test 2. protoSize 4, inputSize 16, two prototypes, layout [C, H, W].
    // proto 0 is +5 everywhere; proto 1 is +5 in columns 0-1 and -10 in columns 2-3.
    // With coefficients [1, 1] the logit is 10 in columns 0-1 (sigmoid ~1) and -5 in columns 2-3 (sigmoid ~0).
    // Box (4, 4)-(12, 12) in input pixels is (1, 1)-(3, 3) in proto pixels, so only column 1, rows 1-2 stay on.
    // Column 0 and rows 0 and 3 have a high sigmoid but lie outside the box.
    @Test func maskIsSigmoidThresholdedAndZeroOutsideBox() {
        let proto0 = [Float](repeating: 5, count: 16)
        let proto1 = (0..<16).map { $0 % 4 < 2 ? Float(5) : Float(-10) }
        let row = YOLORow(x1: 4, y1: 4, x2: 12, y2: 12, confidence: 0.9, classIndex: 0, coefficients: [1, 1])
        let mask = YOLOSegmentDecoder.mask(for: row, protos: proto0 + proto1, protoSize: 4, inputSize: 16)
        #expect(mask.width == 4 && mask.height == 4)
        #expect(mask.pixels == [0, 0, 0, 0,
                                0, 1, 0, 0,
                                0, 1, 0, 0,
                                0, 0, 0, 0])
    }

    // Required test 3. Format copied from the real model's metadata (yolo26s-seg.mlpackage, `names`):
    // a Python dict string, keys are class indices, names may contain spaces.
    @Test func classNamesParsesUltralyticsMetadata() {
        let names = YOLOSegmentDecoder.classNames(fromMetadata:
            "{0: 'person', 1: 'bicycle', 9: 'traffic light', 10: 'fire hydrant', 67: 'cell phone', 79: 'toothbrush'}")
        #expect(names.count == 6)
        #expect(names[0] == "person")
        #expect(names[9] == "traffic light")
        #expect(names[67] == "cell phone")
        #expect(names[79] == "toothbrush")
    }

    @Test func classNamesHandlesDoubleQuotesAndGarbage() {
        #expect(YOLOSegmentDecoder.classNames(fromMetadata: "{0: \"man's hat\", 1: 'cup'}") == [0: "man's hat", 1: "cup"])
        #expect(YOLOSegmentDecoder.classNames(fromMetadata: "not a dict").isEmpty)
    }
}
