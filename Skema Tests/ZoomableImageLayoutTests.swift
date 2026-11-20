//
//  ZoomableImageLayoutTests.swift
//  Skema Tests
//
//  The reference viewer fits the photo between the top bar and the thumbnail strip (Sketch R13b),
//  so the strip never covers the photo, whatever the photo's shape.
//

import Testing
import UIKit
@testable import Skema_Photo

@MainActor
@Suite("Reference viewer: photo stays clear of the bars and thumbnails")
struct ZoomableImageLayoutTests {
    func image(width: CGFloat, height: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// A real scene window (UIWindow(frame:) is deprecated and has no scene).
    func makeWindow() -> UIWindow {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first!
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        return window
    }

    func layOut(_ photo: UIImage, insets: UIEdgeInsets) -> CGRect {
        let scrollView = ZoomableImageView.ZoomableScrollView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        scrollView.fitInsets = insets
        scrollView.setImage(photo)
        scrollView.layoutIfNeeded()
        return scrollView.imageView.frame
    }

    @Test("Portrait, landscape, square and very tall photos all fit inside the insets", arguments: [
        CGSize(width: 3, height: 4),
        CGSize(width: 4, height: 3),
        CGSize(width: 1, height: 1),
        CGSize(width: 9, height: 19.5)
    ])
    func fitsInsideInsets(shape: CGSize) {
        let insets = UIEdgeInsets(top: 124, left: 0, bottom: 144, right: 0)

        let frame = layOut(image(width: shape.width * 100, height: shape.height * 100), insets: insets)

        #expect(frame.minY >= insets.top - 0.5)
        #expect(frame.maxY <= 874 - insets.bottom + 0.5)
        #expect(frame.minX >= -0.5)
        #expect(frame.maxX <= 402.5)
    }

    @Test("The photo is centred in the space between the insets")
    func centredBetweenInsets() {
        let insets = UIEdgeInsets(top: 124, left: 0, bottom: 144, right: 0)

        let frame = layOut(image(width: 400, height: 300), insets: insets)

        let available = CGRect(x: 0, y: 124, width: 402, height: 874 - 124 - 144)
        #expect(abs(frame.midY - available.midY) < 0.5)
        #expect(abs(frame.width - 402) < 0.5)
    }

    @Test("Insets are measured from the screen, even when the page sits below the status bar")
    func offsetPage() {
        let window = makeWindow()
        // The paging view places each page 62pt down but keeps it full height, as on device.
        let scrollView = ZoomableImageView.ZoomableScrollView(frame: CGRect(x: 0, y: 62, width: 402, height: 874))
        window.addSubview(scrollView)
        window.isHidden = false
        scrollView.fitInsets = UIEdgeInsets(top: 124, left: 0, bottom: 144, right: 0)
        scrollView.setImage(image(width: 300, height: 400))
        scrollView.layoutIfNeeded()

        let onScreen = scrollView.convert(scrollView.imageView.frame, to: window)

        #expect(onScreen.minY >= 124 - 0.5)
        #expect(onScreen.maxY <= 874 - 144 + 0.5)
        window.isHidden = true
    }

    @Test("A page swiped off to the side gets the same tall-photo fit as the visible one")
    func offscreenPage() {
        let window = makeWindow()
        let scrollView = ZoomableImageView.ZoomableScrollView(frame: CGRect(x: 402, y: 62, width: 402, height: 874))
        window.addSubview(scrollView)
        window.isHidden = false
        scrollView.fitInsets = UIEdgeInsets(top: 124, left: 0, bottom: 144, right: 0)
        scrollView.setImage(image(width: 900, height: 1950))
        scrollView.layoutIfNeeded()

        let onScreen = scrollView.convert(scrollView.imageView.frame, to: window)

        #expect(onScreen.minY >= 124 - 0.5)
        #expect(onScreen.maxY <= 874 - 144 + 0.5)
        window.isHidden = true
    }

    @Test("With no insets it still fills the whole view, as before")
    func noInsets() {
        let frame = layOut(image(width: 300, height: 400), insets: .zero)

        #expect(abs(frame.width - 402) < 0.5)
        #expect(abs(frame.midY - 437) < 0.5)
    }
}
