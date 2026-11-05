import Testing
import CoreGraphics
@testable import MeasureKitVision

private func close(_ a: NormalizedBox, _ b: NormalizedBox) -> Bool {
    abs(a.x - b.x) < 1e-9 && abs(a.y - b.y) < 1e-9 && abs(a.width - b.width) < 1e-9 && abs(a.height - b.height) < 1e-9
}

// Vision rect used in all cases: origin bottom-left of the ORIENTED image.
// x 0.1, y 0.2, w 0.3, h 0.4  ->  top-left oriented box: x 0.1, y 1-0.2-0.4 = 0.4, w 0.3, h 0.4.
private let vision = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)

@Suite struct VisionBoxMappingTests {
    // Apple, ImageIO CGImagePropertyOrientation.up: "The encoded image data matches the image's
    // intended display orientation." -> identity, so only the y flip remains.
    @Test func upOnlyFlipsY() {
        let box = VisionBoxMapping.nativeBox(fromVision: vision, orientation: .up)
        #expect(close(box, NormalizedBox(x: 0.1, y: 0.4, width: 0.3, height: 0.4)))
    }

    // Apple, .right: "The encoded image data is rotated 90° counter-clockwise from the image's
    // intended display orientation ... to present the image in its intended orientation, you must
    // rotate it 90° clockwise." Native (nx, ny) -> oriented (1 - ny, nx), so nx = oy, ny = 1 - ox.
    @Test func rightRotatesBackCounterClockwise() {
        let box = VisionBoxMapping.nativeBox(fromVision: vision, orientation: .right)
        #expect(close(box, NormalizedBox(x: 0.4, y: 0.6, width: 0.4, height: 0.3)))
    }

    // Apple, .left: "rotated 90° clockwise from the image's intended display orientation ...
    // you must rotate 90° counter-clockwise." Native (nx, ny) -> oriented (ny, 1 - nx),
    // so nx = 1 - oy, ny = ox.
    @Test func leftRotatesBackClockwise() {
        let box = VisionBoxMapping.nativeBox(fromVision: vision, orientation: .left)
        #expect(close(box, NormalizedBox(x: 0.2, y: 0.1, width: 0.4, height: 0.3)))
    }

    // Apple, .down: "rotated 180° from the image's intended display orientation."
    // nx = 1 - ox, ny = 1 - oy.
    @Test func downRotates180() {
        let box = VisionBoxMapping.nativeBox(fromVision: vision, orientation: .down)
        #expect(close(box, NormalizedBox(x: 0.6, y: 0.2, width: 0.3, height: 0.4)))
    }
}
