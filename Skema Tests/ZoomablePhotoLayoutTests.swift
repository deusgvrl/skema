//
//  ZoomablePhotoLayoutTests.swift
//  Skema Tests
//
//  The reference viewer fits the photo between the top bar and the thumbnail strip (Sketch R13b),
//  so the strip never covers the photo, whatever the photo's shape.
//

import Testing
import UIKit
import AVFoundation
import SwiftUI
@testable import Skema_Photo

@MainActor
@Suite("Reference viewer: photo stays clear of the bars and thumbnails")
struct ZoomablePhotoLayoutTests {
    static let screen = CGSize(width: 402, height: 874)
    static let insets = UIEdgeInsets(top: 124, left: 0, bottom: 144, right: 0)

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
        window.frame = CGRect(origin: .zero, size: Self.screen)
        return window
    }

    func makePage(_ photo: UIImage, insets: UIEdgeInsets, index: Int = 0) -> ZoomablePhotoVC {
        ZoomablePhotoVC(image: photo, index: index, fitInsets: insets) { }
    }

    /// Where the photo is actually drawn (aspect-fit inside the image view), in window coordinates.
    func drawnFrame(of page: ZoomablePhotoVC, photo: UIImage, in window: UIWindow) -> CGRect {
        let fitted = AVMakeRect(aspectRatio: photo.size, insideRect: page.imageView.frame)
        return page.imageView.superview!.convert(fitted, to: window)
    }

    /// Shows the page full screen in a window and returns where the photo ends up.
    func layOut(_ photo: UIImage, insets: UIEdgeInsets) -> CGRect {
        let page = makePage(photo, insets: insets)
        let window = makeWindow()
        window.rootViewController = page
        window.isHidden = false
        window.layoutIfNeeded()
        page.view.layoutIfNeeded()
        defer { window.isHidden = true }
        return drawnFrame(of: page, photo: photo, in: window)
    }

    @Test("Portrait, landscape, square and very tall photos all fit inside the insets", arguments: [
        CGSize(width: 3, height: 4),
        CGSize(width: 4, height: 3),
        CGSize(width: 1, height: 1),
        CGSize(width: 9, height: 19.5)
    ])
    func fitsInsideInsets(shape: CGSize) {
        let frame = layOut(image(width: shape.width * 100, height: shape.height * 100),
                           insets: Self.insets)

        #expect(frame.minY >= Self.insets.top - 0.5)
        #expect(frame.maxY <= Self.screen.height - Self.insets.bottom + 0.5)
        #expect(frame.minX >= -0.5)
        #expect(frame.maxX <= Self.screen.width + 0.5)
    }

    @Test("The photo is centred in the space between the insets")
    func centredBetweenInsets() {
        let frame = layOut(image(width: 400, height: 300), insets: Self.insets)

        let available = CGRect(x: 0, y: Self.insets.top,
                               width: Self.screen.width,
                               height: Self.screen.height - Self.insets.top - Self.insets.bottom)
        #expect(abs(frame.midY - available.midY) < 0.5)
        #expect(abs(frame.width - Self.screen.width) < 0.5)
    }

    @Test("With no insets it still fills the whole view, as before")
    func noInsets() {
        let frame = layOut(image(width: 300, height: 400), insets: .zero)

        // a 3:4 photo in a 402x874 screen is limited by width
        #expect(abs(frame.width - Self.screen.width) < 0.5)
        #expect(abs(frame.midY - Self.screen.height / 2) < 0.5)
    }

    @Test("Changing the insets re-lays out the photo (e.g. the top bar height is measured late)")
    func insetsUpdateLive() {
        let photo = image(width: 900, height: 1950)   // tall, so insets limit its height
        let page = makePage(photo, insets: .zero)
        let window = makeWindow()
        window.rootViewController = page
        window.isHidden = false
        window.layoutIfNeeded()
        defer { window.isHidden = true }

        page.fitInsets = Self.insets
        page.view.layoutIfNeeded()

        let frame = drawnFrame(of: page, photo: photo, in: window)
        #expect(frame.minY >= Self.insets.top - 0.5)
        #expect(frame.maxY <= Self.screen.height - Self.insets.bottom + 0.5)
    }

    @Test("Inside a UIPageViewController, the way PhotoPager hosts it, the photo still respects the insets")
    func insidePageViewController() {
        let photo = image(width: 900, height: 1950)
        let page = makePage(photo, insets: Self.insets)
        let pvc = UIPageViewController(transitionStyle: .scroll,
                                       navigationOrientation: .horizontal,
                                       options: [.interPageSpacing: 20])
        pvc.setViewControllers([page], direction: .forward, animated: false)

        let window = makeWindow()
        window.rootViewController = pvc
        window.isHidden = false
        window.layoutIfNeeded()
        page.view.layoutIfNeeded()
        defer { window.isHidden = true }

        let frame = drawnFrame(of: page, photo: photo, in: window)
        #expect(frame.minY >= Self.insets.top - 0.5)
        #expect(frame.maxY <= Self.screen.height - Self.insets.bottom + 0.5)
    }
}

@MainActor
@Suite("PhotoPager: paging between photos")
struct PhotoPagerCoordinatorTests {
    func makeCoordinator(count: Int) -> PhotoPager.Coordinator {
        let images = (0..<count).map { _ in
            UIGraphicsImageRenderer(size: CGSize(width: 300, height: 400)).image { context in
                UIColor.systemTeal.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 300, height: 400))
            }
        }
        return PhotoPager(images: images, selection: .constant(0)) { }.makeCoordinator()
    }

    @Test("The first photo has nothing before it, the last has nothing after it")
    func edges() {
        let coordinator = makeCoordinator(count: 3)
        let pvc = UIPageViewController()

        #expect(coordinator.pageViewController(pvc, viewControllerBefore: coordinator.page(at: 0)) == nil)
        #expect(coordinator.pageViewController(pvc, viewControllerAfter: coordinator.page(at: 2)) == nil)
    }

    @Test("Neighbouring pages carry the right index")
    func neighbours() {
        let coordinator = makeCoordinator(count: 3)
        let pvc = UIPageViewController()
        let middle = coordinator.page(at: 1)

        let before = coordinator.pageViewController(pvc, viewControllerBefore: middle) as? ZoomablePhotoVC
        let after = coordinator.pageViewController(pvc, viewControllerAfter: middle) as? ZoomablePhotoVC

        #expect(before?.index == 0)
        #expect(after?.index == 2)
    }

    @Test("A single photo can't be paged in either direction")
    func singlePhoto() {
        let coordinator = makeCoordinator(count: 1)
        let pvc = UIPageViewController()
        let only = coordinator.page(at: 0)

        #expect(coordinator.pageViewController(pvc, viewControllerBefore: only) == nil)
        #expect(coordinator.pageViewController(pvc, viewControllerAfter: only) == nil)
    }
}
