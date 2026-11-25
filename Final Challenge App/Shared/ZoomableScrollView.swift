//
//  ZoomableScrollView.swift
//  Final Challenge App
//
//  Created by Satriya Handha Wibowo on 25/11/26.
//

import SwiftUI
import UIKit

/// A smooth zooming and panning container backed by UIKit's `UIScrollView`.
/// Replaces manual DragGesture and MagnifyGesture with native momentum, 2-finger pan,
/// pinch-to-zoom, rubber-banding, and double-tap zoom matching FullScreenImageView.
struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    @Binding var zoomScale: CGFloat
    let minScale: CGFloat
    let maxScale: CGFloat
    let canvasSize: CGSize
    let isReadOnly: Bool
    let interactiveCenters: [CGPoint]
    var onEmptyTap: (() -> Void)?
    var onZoomChanged: ((CGFloat) -> Void)?
    var onZoomEnded: (() -> Void)?
    let content: Content

    init(
        zoomScale: Binding<CGFloat>,
        minScale: CGFloat = 0.3,
        maxScale: CGFloat = 4.0,
        canvasSize: CGSize = CGSize(width: 3000, height: 3000),
        isReadOnly: Bool = false,
        interactiveCenters: [CGPoint] = [],
        onEmptyTap: (() -> Void)? = nil,
        onZoomChanged: ((CGFloat) -> Void)? = nil,
        onZoomEnded: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self._zoomScale = zoomScale
        self.minScale = minScale
        self.maxScale = maxScale
        self.canvasSize = canvasSize
        self.isReadOnly = isReadOnly
        self.interactiveCenters = interactiveCenters
        self.onEmptyTap = onEmptyTap
        self.onZoomChanged = onZoomChanged
        self.onZoomEnded = onZoomEnded
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> DiagramUIScrollView {
        let scrollView = DiagramUIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = minScale
        scrollView.maximumZoomScale = maxScale
        scrollView.zoomScale = zoomScale
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bounces = true
        scrollView.bouncesZoom = true
        scrollView.alwaysBounceHorizontal = true
        scrollView.alwaysBounceVertical = true
        scrollView.decelerationRate = .normal
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        scrollView.backgroundColor = .clear

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2

        let singleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSingleTap(_:))
        )
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)

        scrollView.addGestureRecognizer(doubleTap)
        scrollView.addGestureRecognizer(singleTap)
        scrollView.panGestureRecognizer.delegate = context.coordinator

        let hostedView = context.coordinator.hostingController.view!
        hostedView.backgroundColor = .clear
        hostedView.frame = CGRect(origin: .zero, size: canvasSize)
        scrollView.addSubview(hostedView)
        scrollView.contentSize = canvasSize

        context.coordinator.scrollView = scrollView
        return scrollView
    }

    func updateUIView(_ uiView: DiagramUIScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.hostingController.rootView = content

        let hostedView = context.coordinator.hostingController.view!
        if hostedView.frame.size != canvasSize {
            hostedView.frame = CGRect(origin: .zero, size: canvasSize)
            uiView.contentSize = CGSize(
                width: canvasSize.width * uiView.zoomScale,
                height: canvasSize.height * uiView.zoomScale
            )
        }

        // Center on initial layout once geometry is valid
        if !context.coordinator.hasCenteredInitialContent && uiView.bounds.width > 0 {
            context.coordinator.hasCenteredInitialContent = true
            let initialX = (canvasSize.width - uiView.bounds.width) / 2
            let initialY = (canvasSize.height - uiView.bounds.height) / 2
            uiView.contentOffset = CGPoint(x: initialX, y: initialY)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var parent: ZoomableScrollView
        let hostingController: UIHostingController<Content>
        weak var scrollView: DiagramUIScrollView?
        var hasCenteredInitialContent = false

        init(_ parent: ZoomableScrollView) {
            self.parent = parent
            self.hostingController = UIHostingController(rootView: parent.content)
            super.init()
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            hostingController.view
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            let scale = scrollView.zoomScale
            parent.zoomScale = scale
            parent.onZoomChanged?(scale)
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            parent.zoomScale = scale
            parent.onZoomEnded?()
        }

        @objc func handleSingleTap(_ recognizer: UITapGestureRecognizer) {
            parent.onEmptyTap?()
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView else { return }
            let hostedView = hostingController.view!

            if scrollView.zoomScale > (parent.minScale + 0.15) {
                scrollView.setZoomScale(1.0, animated: true)
            } else {
                let targetScale: CGFloat = min(2.5, parent.maxScale)
                let tapLocation = recognizer.location(in: hostedView)
                let width = scrollView.bounds.width / targetScale
                let height = scrollView.bounds.height / targetScale
                let zoomRect = CGRect(
                    x: tapLocation.x - (width / 2),
                    y: tapLocation.y - (height / 2),
                    width: width,
                    height: height
                )
                scrollView.zoom(to: zoomRect, animated: true)
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let scrollView, gestureRecognizer == scrollView.panGestureRecognizer else {
                return true
            }

            if parent.isReadOnly {
                return true
            }

            if touch.numberOfTouches >= 2 {
                return true
            }

            let hostedView = hostingController.view!
            let locationInCanvas = touch.location(in: hostedView)
            let itemHitRadius: CGFloat = 52.0

            for center in parent.interactiveCenters {
                let distance = hypot(locationInCanvas.x - center.x, locationInCanvas.y - center.y)
                if distance <= itemHitRadius {
                    return false
                }
            }

            return true
        }
    }
}

// A specialized UIScrollView subclass for diagram interaction
final class DiagramUIScrollView: UIScrollView {}
