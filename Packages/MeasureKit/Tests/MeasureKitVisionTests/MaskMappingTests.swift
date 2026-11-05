import Testing
import CoreGraphics
@testable import MeasureKitVision

// Oriented 3x2 mask with only the top-left pixel set:
//   1 0 0
//   0 0 0
private let corner = InstanceMask(width: 3, height: 2, pixels: [1, 0, 0, 0, 0, 0])

@Suite struct MaskMappingTests {
    // Required test 1. Same orientation meaning as VisionBoxMapping:
    // .right: nx = oy, ny = W - 1 - ox (native is H x W). Top-left (0,0) -> native bottom-left.
    @Test func upIsIdentity() {
        #expect(MaskMapping.nativeMask(corner, orientation: .up) == corner)
    }

    @Test func rightMapsCornerToBottomLeft() {
        let m = MaskMapping.nativeMask(corner, orientation: .right)
        #expect(m == InstanceMask(width: 2, height: 3, pixels: [0, 0, 0, 0, 1, 0]))
    }

    @Test func leftMapsCornerToTopRight() {
        let m = MaskMapping.nativeMask(corner, orientation: .left)
        #expect(m == InstanceMask(width: 2, height: 3, pixels: [0, 1, 0, 0, 0, 0]))
    }

    @Test func downMapsCornerToBottomRight() {
        let m = MaskMapping.nativeMask(corner, orientation: .down)
        #expect(m == InstanceMask(width: 3, height: 2, pixels: [0, 0, 0, 0, 0, 1]))
    }

    // The same rectangle mapped as a mask and as a Vision box must agree.
    @Test(arguments: [ImageOrientation.up, .right, .left, .down])
    func maskBoundsAgreeWithBoxMapping(orientation: ImageOrientation) throws {
        // Oriented 8x4; set pixels x 1..<3, y 0..<2 (top-left origin).
        var px = [UInt8](repeating: 0, count: 32)
        for y in 0..<2 { for x in 1..<3 { px[y * 8 + x] = 1 } }
        let mask = InstanceMask(width: 8, height: 4, pixels: px)
        // Same rectangle as a Vision rect (bottom-left origin): x 1/8, w 2/8, h 2/4, y = 1 - 0 - 0.5.
        let vision = CGRect(x: 1.0 / 8, y: 0.5, width: 2.0 / 8, height: 0.5)
        let expected = VisionBoxMapping.nativeBox(fromVision: vision, orientation: orientation)
        let got = try #require(MaskMapping.bounds(of: MaskMapping.nativeMask(mask, orientation: orientation)))
        #expect(abs(got.x - expected.x) < 1e-9 && abs(got.y - expected.y) < 1e-9)
        #expect(abs(got.width - expected.width) < 1e-9 && abs(got.height - expected.height) < 1e-9)
    }

    // Required test 2.
    @Test func emptyMaskHasNoBounds() {
        #expect(MaskMapping.bounds(of: InstanceMask(width: 4, height: 4, pixels: [UInt8](repeating: 0, count: 16))) == nil)
    }

    @Test func lShapeHasTightBounds() throws {
        // 5x4:  . . . . .
        //       . 1 . . .
        //       . 1 . . .
        //       . 1 1 1 .
        var px = [UInt8](repeating: 0, count: 20)
        for i in [6, 11, 16, 17, 18] { px[i] = 1 }
        let b = try #require(MaskMapping.bounds(of: InstanceMask(width: 5, height: 4, pixels: px)))
        #expect(b == NormalizedBox(x: 1.0 / 5, y: 1.0 / 4, width: 3.0 / 5, height: 3.0 / 4))
    }
}
