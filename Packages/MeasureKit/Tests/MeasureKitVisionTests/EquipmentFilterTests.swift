import Testing
@testable import MeasureKitVision
import MeasureKit

/// A10-60 test cases 3–7 (docs/test-cases/A10-60_equipment-detector.md in the Challenge 5 folder).
/// Boxes are in model input pixels (640 x 640).
@Suite struct EquipmentFilterTests {
    private static let names: [Int: String] = [0: "studio lighting", 1: "studio lighting", 2: "Camera"]
    private static let labels: Set<String> = ["studio lighting", "Camera"]

    private func row(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float, _ conf: Float, _ cls: Int) -> YOLORow {
        YOLORow(x1: x1, y1: y1, x2: x2, y2: y2, confidence: conf, classIndex: cls, coefficients: [])
    }

    private func keep(_ rows: [YOLORow], names: [Int: String] = Self.names,
                      labels: Set<String> = Self.labels) -> [YOLORow] {
        EquipmentFilter.keep(rows, classNames: names, labels: labels, maxAreaFraction: 0.8, iouThreshold: 0.5)
    }

    // Case 3. The cutoff is applied while decoding rows: 29% is dropped, 30% and 31% are kept.
    @Test func cutoffKeepsThirtyPercentAndAbove() {
        func raw(_ conf: Float) -> [Float] { [0, 0, 10, 10, conf, 0] + [Float](repeating: 0, count: 32) }
        let rows = YOLOSegmentDecoder.rows(output: raw(0.29) + raw(0.30) + raw(0.31), count: 3, minConfidence: 0.30)
        #expect(rows.map(\.confidence) == [0.30, 0.31])
    }

    // Case 4. Labels are compared after trimming spaces and ignoring case ("normalize the input").
    // A label that is not in the list is dropped.
    @Test func unknownLabelIsDroppedAndLabelsAreNormalized() {
        let names: [Int: String] = [0: " Studio Lighting", 1: "camera ", 2: "tripod"]
        let kept = keep([row(0, 0, 10, 10, 0.9, 0), row(100, 100, 110, 110, 0.8, 1), row(200, 200, 210, 210, 0.7, 2)],
                        names: names)
        #expect(kept.map(\.classIndex) == [0, 1])
    }

    // Case 5. 640 x 513 covers more than 80% of the frame: dropped. 640 x 512 is exactly 80%: kept.
    // A box that reaches past the frame is clipped first, so (-100, -100)-(740, 740) counts as the whole frame.
    @Test func wholeFrameBoxIsDroppedExactlyEightyPercentIsKept() {
        #expect(keep([row(0, 0, 640, 513, 0.9, 0)]).isEmpty)
        #expect(keep([row(0, 0, 640, 512, 0.9, 0)]).count == 1)
        #expect(keep([row(-100, -100, 740, 740, 0.9, 0)]).isEmpty)
    }

    // Case 6. Classes 0 and 1 are both "studio lighting": the same softbox found by two prompts comes out once,
    // with the higher score. Class 2 ("Camera") on the same spot, like a camera inside a ring light, is kept.
    @Test func overlapsAreRemovedOnlyWithinTheSameLabel() {
        let light = row(100, 100, 300, 300, 0.9, 0)
        let sameLightOtherPrompt = row(100, 100, 300, 300, 0.6, 1)
        let cameraInRing = row(100, 100, 300, 300, 0.5, 2)
        let kept = keep([sameLightOtherPrompt, cameraInRing, light])
        #expect(kept == [light, cameraInRing])
    }

    // Case 7. No cap: 12 separate objects give 12 detections.
    @Test func twelveSeparateObjectsAreAllKept() {
        let rows = (0..<12).map { i in row(Float(i) * 50, 0, Float(i) * 50 + 40, 40, 0.9, i % 3) }
        #expect(keep(rows).count == 12)
    }
}
