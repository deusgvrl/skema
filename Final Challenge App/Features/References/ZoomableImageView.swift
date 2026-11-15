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
        scrollView.setImage(image)
        return scrollView
    }

    func updateUIView(_ uiView: ZoomableScrollView, context: Context) {
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

            let widthRatio = bounds.width / imageSize.width
            let heightRatio = bounds.height / imageSize.height
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
            var frameToCenter = imageView.frame

            if frameToCenter.size.width < boundsSize.width {
                frameToCenter.origin.x = (boundsSize.width - frameToCenter.size.width) / 2.0
            } else {
                frameToCenter.origin.x = 0
            }

            if frameToCenter.size.height < boundsSize.height {
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
                let w = bounds.size.width / newZoomScale
                let h = bounds.size.height / newZoomScale
                let x = pointInView.x - (w / 2.0)
                let y = pointInView.y - (h / 2.0)
                let rectToZoomTo = CGRect(x: x, y: y, width: w, height: h)
                zoom(to: rectToZoomTo, animated: true)
                isZoomedBinding?(true)
                isControlsHiddenBinding?(true)
            }
        }
    }
}
