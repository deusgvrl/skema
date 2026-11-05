import XCTest
@testable import MeasureKit

final class DepthPreviewTests: XCTestCase {
    func testStrideSamplesFromZeroAtPixelCentres() {
        let dots = DepthPreview.dots(from: makeFrame(width: 8, height: 8, depth: 2), stride: 4)
        XCTAssertEqual(dots.count, 4)
        XCTAssertEqual(dots[0], PreviewDot(u: 0.5 / 8, v: 0.5 / 8, depth: 2))
        XCTAssertEqual(dots[1], PreviewDot(u: 4.5 / 8, v: 0.5 / 8, depth: 2))
        XCTAssertEqual(dots[2], PreviewDot(u: 0.5 / 8, v: 4.5 / 8, depth: 2))
    }

    func testLowConfidenceAndBadDepthsAreSkipped() {
        var f = makeFrame(width: 8, height: 8, depth: 2)
        var depth = f.depth, conf = f.confidence
        conf[0] = 1                  // (0,0) low confidence
        depth[4] = .nan              // (4,0)
        depth[4 * 8] = 0             // (0,4)
        f = DepthFrame(width: 8, height: 8, depth: depth, confidence: conf)
        let dots = DepthPreview.dots(from: f, stride: 4)
        XCTAssertEqual(dots, [PreviewDot(u: 4.5 / 8, v: 4.5 / 8, depth: 2)])
        XCTAssertEqual(DepthPreview.dots(from: f, stride: 4, minConfidence: 0).count, 2)  // low confidence returns; NaN and 0 stay out
    }

    func testColorPositionIsClamped() {
        XCTAssertEqual(DepthPreview.colorPosition(depth: 0.3), 0)
        XCTAssertEqual(DepthPreview.colorPosition(depth: 4), 1)
        XCTAssertEqual(DepthPreview.colorPosition(depth: 0.1), 0)
        XCTAssertEqual(DepthPreview.colorPosition(depth: 9), 1)
        XCTAssertEqual(DepthPreview.colorPosition(depth: 2, near: 1, far: 3), 0.5, accuracy: 1e-6)
    }
}
