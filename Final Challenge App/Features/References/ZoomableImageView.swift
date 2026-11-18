//
//  ZoomableImageView.swift
//  Final Challenge App
//
//  Created by Satriya Handha Wibowo on 14/11/26.
//

import SwiftUI
import UIKit

/// Hardware-accelerated zoomable image view using UIKit's UIScrollView.
/// Fits exact aspect-fit image bounds to prevent layout jumps during toolbar toggle passes.
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    let isSelected: Bool
    @Binding var isZoomed: Bool
    @Binding var isControlsHidden: Bool
    /// Space the fitted photo keeps clear of, e.g. the top bar and the thumbnail strip (Sketch R13b).
    /// Zooming still uses the whole view.
    var fitInsets: UIEdgeInsets = .zero

    func makeUIView(context: Context) -> ZoomableScrollView {
        let scrollView = ZoomableScrollView()
        scrollView.isZoomedBinding = { zoomed in
            if self.isZoomed != zoomed {
                self.isZoomed = zoomed
            }
        }
        scrollView.isControlsHiddenBinding = { hidden in
            if self.isControlsHidden != hidden {
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.isControlsHidden = hidden
                }
            }
        }
        scrollView.onSingleTap = {
            withAnimation(.easeInOut(duration: 0.25)) {
                self.isControlsHidden.toggle()
            }
        }
        scrollView.fitInsets = fitInsets
        scrollView.setImage(image)
        return scrollView
    }

    func updateUIView(_ uiView: ZoomableScrollView, context: Context) {
        uiView.fitInsets = fitInsets
        uiView.setImage(image)

        // Reset zoom when swiping away from this image page
        if !isSelected && uiView.zoomScale != 1.0 {
            uiView.resetZoom(animated: false)
        }
    }

    class ZoomableScrollView: UIScrollView, UIScrollViewDelegate {
        let imageView = UIImageView()
        var isZoomedBinding: ((Bool) -> Void)?
        var isControlsHiddenBinding: ((Bool) -> Void)?
        var onSingleTap: (() -> Void)?

        private var lastBoundsSize: CGSize = .zero

        var fitInsets: UIEdgeInsets = .zero {
            didSet {
                guard fitInsets != oldValue else { return }
                lastBoundsSize = .zero
                setNeedsLayout()
            }
        }

        /// Where the unzoomed photo may go, in this view's own coordinates (ignoring zoom scrolling).
        /// `fitInsets` are measured from the screen edges: the paging view may place this page lower
        /// than the screen top (e.g. under the status bar) while keeping it full height.
        private var fitArea: CGRect {
            let ownArea = CGRect(origin: .zero, size: bounds.size)
            var area = ownArea.inset(by: fitInsets)
            if let window {
                // Vertical position only: pages that are swiped off to the side still get the same area.
                let pageTop = convert(CGPoint(x: bounds.minX, y: bounds.minY), to: window).y
                let top = max(0, fitInsets.top - pageTop)
                let bottom = min(bounds.height, window.bounds.height - fitInsets.bottom - pageTop)
                area = CGRect(x: area.minX, y: top, width: area.width, height: bottom - top)
            }
            return area.width > 0 && area.height > 0 ? area : ownArea
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            setup()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setup()
        }

        private func setup() {
            self.delegate = self
            self.maximumZoomScale = 4.0
            self.minimumZoomScale = 1.0
            self.showsHorizontalScrollIndicator = false
            self.showsVerticalScrollIndicator = false
            self.bouncesZoom = true
            self.decelerationRate = .fast
            self.backgroundColor = .clear
            self.contentInsetAdjustmentBehavior = .never
            self.insetsLayoutMarginsFromSafeArea = false

            imageView.contentMode = .scaleAspectFit
            imageView.clipsToBounds = true
            addSubview(imageView)

            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            doubleTap.numberOfTapsRequired = 2
            addGestureRecognizer(doubleTap)

            let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
            singleTap.numberOfTapsRequired = 1
            singleTap.require(toFail: doubleTap)
            addGestureRecognizer(singleTap)
        }

        override func layoutSubviews() {
            super.layoutSubviews()

            // Only recalculate image frame if bounds dimensions actually change (e.g., orientation change)
            if bounds.size != lastBoundsSize && bounds.width > 0 && bounds.height > 0 {
                lastBoundsSize = bounds.size
                updateImageFrame()
            } else {
                centerImage()
            }
        }

        func setImage(_ image: UIImage) {
            if imageView.image != image {
                imageView.image = image
                lastBoundsSize = .zero
                setNeedsLayout()
                layoutIfNeeded()
                resetZoom(animated: false)
            }
        }

        func resetZoom(animated: Bool = false) {
            setZoomScale(1.0, animated: animated)
            updateImageFrame()
        }

        func updateImageFrame() {
            guard let image = imageView.image, bounds.width > 0, bounds.height > 0 else { return }

            let imageSize = image.size
            guard imageSize.width > 0 && imageSize.height > 0 else { return }

            let area = fitArea
            let widthRatio = area.width / imageSize.width
            let heightRatio = area.height / imageSize.height
            let scale = min(widthRatio, heightRatio)

            let fittedWidth = imageSize.width * scale
            let fittedHeight = imageSize.height * scale

            let newFrame = CGRect(x: 0, y: 0, width: fittedWidth, height: fittedHeight)
            imageView.frame = newFrame
            contentSize = newFrame.size
            centerImage()
        }

        func centerImage() {
            guard imageView.image != nil else { return }
            let boundsSize = bounds.size
            let area = fitArea
            var frameToCenter = imageView.frame

            // Unzoomed: centre in the fit area. Zoomed past it: centre in the whole view, then pin to 0.
            if frameToCenter.size.width <= area.width {
                frameToCenter.origin.x = area.minX + (area.width - frameToCenter.size.width) / 2.0
            } else if frameToCenter.size.width < boundsSize.width {
                frameToCenter.origin.x = (boundsSize.width - frameToCenter.size.width) / 2.0
            } else {
                frameToCenter.origin.x = 0
            }

            if frameToCenter.size.height <= area.height {
                frameToCenter.origin.y = area.minY + (area.height - frameToCenter.size.height) / 2.0
            } else if frameToCenter.size.height < boundsSize.height {
                frameToCenter.origin.y = (boundsSize.height - frameToCenter.size.height) / 2.0
            } else {
                frameToCenter.origin.y = 0
            }

            imageView.frame = frameToCenter
        }

        // MARK: - UIScrollViewDelegate

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImage()

            let currentlyZoomed = scrollView.zoomScale > 1.01
            isZoomedBinding?(currentlyZoomed)
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            let currentlyZoomed = scale > 1.01
            isZoomedBinding?(currentlyZoomed)
        }

        @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
            onSingleTap?()
        }

        @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            if zoomScale > 1.01 {
                setZoomScale(1.0, animated: true)
                isZoomedBinding?(false)
                isControlsHiddenBinding?(false)
            } else {
                let pointInView = gesture.location(in: imageView)
                let newZoomScale: CGFloat = 2.5
                let zoomWidth = bounds.size.width / newZoomScale
                let zoomHeight = bounds.size.height / newZoomScale
                let rectToZoomTo = CGRect(
                    x: pointInView.x - (zoomWidth / 2.0),
                    y: pointInView.y - (zoomHeight / 2.0),
                    width: zoomWidth,
                    height: zoomHeight
                )
                zoom(to: rectToZoomTo, animated: true)
                isZoomedBinding?(true)
                isControlsHiddenBinding?(true)
            }
        }
    }
}
