//
//  MaskImageTests.swift
//  Skema Tests
//
//  A10-62 cases M1–M6 (written in the A10-62 Jira issue): a detection mask → a tinted, see-through picture,
//  turned upright and laid over the camera picture the same way as the tags.
//  Camera: 1920 x 1440 sideways picture, fx = fy = 1000, centre (960, 720), at the origin looking along -z.
//  Masks are 640 x 640 and cover the whole sideways picture.
//

import CoreGraphics
import MeasureKit
import simd
import Testing
@testable import Final_Challenge_App

private let side = 640

private let maskCamera: CameraModel = {
    var intrinsics = matrix_identity_float3x3
    intrinsics[0][0] = 1000
    intrinsics[1][1] = 1000
    intrinsics[2][0] = 960
    intrinsics[2][1] = 720
    return CameraModel(intrinsics: intrinsics, imageResolution: SIMD2(1920, 1440),
                       cameraToWorld: matrix_identity_float4x4)
}()

/// A 640 x 640 mask with 1s where `isInside(column, row)` is true.
private func mask(_ isInside: (Int, Int) -> Bool) -> InstanceMask {
    var pixels = [UInt8](repeating: 0, count: side * side)
    for row in 0..<side {
        for column in 0..<side where isInside(column, row) {
            pixels[row * side + column] = 1
        }
    }
    return InstanceMask(width: side, height: side, pixels: pixels)
}

/// The RGBA values of one image pixel (straight alpha, as `MaskImage` makes it).
private func rgba(of image: CGImage, column: Int, row: Int) throws -> [UInt8] {
    let data = try #require(image.dataProvider?.data)
    let bytes = try #require(CFDataGetBytePtr(data))
    let start = row * image.bytesPerRow + column * 4
    return (0..<4).map { bytes[start + $0] }
}

@Suite("Mask image: tinted, upright, lined up with the tags")
struct MaskImageTests {
    // MARK: M1, M2

    @Test("Case M1: a 1 is tinted at 50%, a 0 is fully see-through")
    func insideTintedOutsideClear() throws {
        let image = try #require(MaskImage.image(of: mask { column, _ in column < 320 }, color: .white))
        #expect(image.alphaInfo == .last)
        #expect(try rgba(of: image, column: 320, row: 0) == [255, 255, 255, 128])
        #expect(try rgba(of: image, column: 320, row: 639)[3] == 0)
    }

    @Test("Case M2: a pending item's mask is white at 50%, an accepted one's is green at 50%")
    func whiteAndGreen() throws {
        let full = mask { _, _ in true }
        let white = try #require(MaskImage.image(of: full, color: .white))
        let green = try #require(MaskImage.image(of: full, color: .green))
        #expect(try rgba(of: white, column: 0, row: 0) == [255, 255, 255, 128])
        let greenRGB = MaskColor.green.rgb
        #expect(try rgba(of: green, column: 0, row: 0) == [greenRGB.x, greenRGB.y, greenRGB.z, 128])
        #expect(greenRGB.y > greenRGB.x && greenRGB.y > greenRGB.z)
    }

    // MARK: M3–M5

    @Test("Case M3: an item 1 m straight ahead has the middle of its mask under its tag", arguments: [
        CGSize(width: 1440, height: 1920), CGSize(width: 390, height: 844)
    ])
    func middleUnderTag(screen: CGSize) throws {
        let tag = try #require(ScanOverlay.screenPoint(of: SIMD3(0, 0, -1), camera: maskCamera, screenSize: screen))
        let full = mask { _, _ in true }
        let onScreen = MaskImage.screenPoint(ofMaskPixel: side / 2, side / 2, mask: full, camera: maskCamera,
                                             screenSize: screen)
        #expect(hypot(onScreen.x - tag.x, onScreen.y - tag.y) < 3)
        #expect(hypot(tag.x - screen.width / 2, tag.y - screen.height / 2) < 1)
    }

    @Test("Case M4: a mask in the top-left corner of the sideways picture shows at the top-right of the screen")
    func topLeftBecomesTopRight() throws {
        let corner = mask { column, row in column < 10 && row < 10 }
        let image = try #require(MaskImage.image(of: corner, color: .white))
        #expect(image.width == side && image.height == side)
        #expect(try rgba(of: image, column: side - 1, row: 0)[3] == 128)
        #expect(try rgba(of: image, column: 0, row: 0)[3] == 0)

        let screen = CGSize(width: 1440, height: 1920)
        let onScreen = MaskImage.screenPoint(ofMaskPixel: 0, 0, mask: corner, camera: maskCamera, screenSize: screen)
        #expect(onScreen.x > screen.width / 2)
        #expect(onScreen.y < screen.height / 2)
    }

    @Test("Case M5: on an iPhone-shaped screen the mask is scaled and cut like the camera picture")
    func scaledAndCutLikeThePicture() throws {
        let screen = CGSize(width: 390, height: 844)
        let rect = MaskImage.pictureRect(camera: maskCamera, screenSize: screen)
        #expect(abs(rect.height - 844) < 0.01)
        #expect(abs(rect.width - 1440 * 844 / 1920) < 0.01)
        #expect(abs(rect.midX - 195) < 0.01)
        #expect(rect.minX < 0)

        // A spot 20 cm above straight ahead, 1 m away: picture pixel (960, 520).
        let tag = try #require(ScanOverlay.screenPoint(of: SIMD3(0, 0.2, -1), camera: maskCamera, screenSize: screen))
        let full = mask { _, _ in true }
        let onScreen = MaskImage.screenPoint(ofMaskPixel: 960 * side / 1920, 520 * side / 1440, mask: full,
                                             camera: maskCamera, screenSize: screen)
        #expect(hypot(onScreen.x - tag.x, onScreen.y - tag.y) < 3)
    }

    // MARK: M6

    @Test("Case M6: a mask with no 1s gives no image, and no crash")
    func emptyMaskGivesNothing() {
        #expect(MaskImage.image(of: mask { _, _ in false }, color: .green) == nil)
        #expect(MaskImage.image(of: InstanceMask(width: 0, height: 0, pixels: []), color: .white) == nil)
    }
}
