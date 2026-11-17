//
//  CoverImageTests.swift
//  Skema Tests
//

import Foundation
import Testing
import UIKit
@testable import Final_Challenge_App

@MainActor
@Suite("Setup cover image")
struct CoverImageTests {
    private func jpegData(width: CGFloat, height: CGFloat) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return image.jpegData(compressionQuality: 0.8)!
    }

    @Test("The cover is the earliest reference photo, not whichever the relationship lists first")
    func coverIsEarliestPhoto() {
        let storage = StorageController(inMemory: true)
        let setup = Setup(setupName: "Candle")
        storage.addSetup(setup)
        let later = ReferenceImage(imageData: Data([1]), createdAt: Date())
        let earlier = ReferenceImage(imageData: Data([2]), createdAt: Date().addingTimeInterval(-3600))
        storage.addReferenceImage(later, to: setup)
        storage.addReferenceImage(earlier, to: setup)

        #expect(setup.coverImage?.id == earlier.id)
    }

    @Test("A setup with no photos has no cover")
    func noPhotosNoCover() {
        #expect(Setup(setupName: "Empty").coverImage == nil)
    }

    @Test("Downsampling keeps the longest side within the requested pixel size")
    func downsamplesLargePhoto() async throws {
        let data = jpegData(width: 2000, height: 1000)

        let thumbnail = try #require(await downsampledImage(from: data, maxPixelSize: 300))

        let longestPixelSide = max(thumbnail.size.width, thumbnail.size.height) * thumbnail.scale
        #expect(longestPixelSide <= 300)
        #expect(longestPixelSide >= 299)
    }

    @Test("Data that isn't an image downsamples to nil")
    func invalidDataIsNil() async {
        #expect(await downsampledImage(from: Data([0, 1, 2]), maxPixelSize: 300) == nil)
    }
}
