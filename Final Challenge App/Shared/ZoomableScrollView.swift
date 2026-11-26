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
/// pinch-to-zoom, and rubber-banding matching FullScreenImageView.
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
        maxScale: CGFloat = 8.0,
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
        scrollView.scrollsToTop = false
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never

        if #available(iOS 26.0, *) {
            scrollView.topEdgeEffect.isHidden = true
            scrollView.bottomEdgeEffect.isHidden = true
            scrollView.leftEdgeEffect.isHidden = true
            scrollView.rightEdgeEffect.isHidden = true
        }

        let singleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSingleTap(_:))
        )
        singleTap.numberOfTapsRequired = 1

        scrollView.addGestureRecognizer(singleTap)

        scrollView.shouldBlockPan = { [weak coordinator = context.coordinator] gesture in
            coordinator?.shouldBlockPan(gesture) ?? false
        }

        scrollView.onLayout = { [weak coordinator = context.coordinator, weak scrollView] in
            guard let coordinator, let scrollView else { return }
            coordinator.centerContentIfNeeded(in: scrollView)
        }

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
        context.coordinator.centerContentIfNeeded(in: uiView)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var parent: ZoomableScrollView
        let hostingController: UIHostingController<Content>
        weak var scrollView: DiagramUIScrollView?
        var hasCenteredInitialContent = false

        func centerContentIfNeeded(in uiView: UIScrollView) {
            guard !hasCenteredInitialContent, uiView.bounds.width > 0, uiView.bounds.height > 0 else { return }
            hasCenteredInitialContent = true
            let initialX = (parent.canvasSize.width * uiView.zoomScale - uiView.bounds.width) / 2
            let initialY = (parent.canvasSize.height * uiView.zoomScale - uiView.bounds.height) / 2
            uiView.contentOffset = CGPoint(x: initialX, y: initialY)
        }

        func shouldBlockPan(_ gesture: UIGestureRecognizer) -> Bool {
            guard let scrollView else { return false }
            if parent.isReadOnly { return false }
            if gesture.numberOfTouches >= 2 { return false }

            let hostedView = hostingController.view!
            let location = gesture.location(in: hostedView)
            // Screen hit target is 52pt; in canvas coordinates it shrinks by 1 / zoomScale
            let currentScale = max(0.1, scrollView.zoomScale)
            let itemHitRadius: CGFloat = 52.0 / currentScale

            return parent.interactiveCenters.contains {
                hypot(location.x - $0.x, location.y - $0.y) <= itemHitRadius
            }
        }

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

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let scrollView, gestureRecognizer == scrollView.panGestureRecognizer else {
                return true
            }

            if parent.isReadOnly {
                return true
            }

            if gestureRecognizer.numberOfTouches >= 2 {
                return true
            }

            let hostedView = hostingController.view!
            let locationInCanvas = touch.location(in: hostedView)
            let currentScale = max(0.1, scrollView.zoomScale)
            let itemHitRadius: CGFloat = 52.0 / currentScale

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
final class DiagramUIScrollView: UIScrollView {
    /// Callback when bounds change or layout occurs to guarantee initial centering
    var onLayout: (() -> Void)?

    /// Return true if a single-finger pan starting at this point (in the scroll view's
    /// content/hosted view coordinates) should be blocked, e.g. because it hit an item.
    var shouldBlockPan: ((UIGestureRecognizer) -> Bool)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGestureRecognizer, shouldBlockPan?(gestureRecognizer) == true {
            return false
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
}
