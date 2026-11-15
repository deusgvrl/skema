//
//  ZoomableImageView.swift
//  Final Challenge App
//
//  Created by Satriya Handha Wibowo on 14/11/26.
//

import SwiftUI
import UIKit

/// Hardware-accelerated image zoom wrapper using UIKit's UIScrollView.
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    let isSelected: Bool
    @Binding var isControlsHidden: Bool

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = 4.0
        scrollView.minimumZoomScale = 1.0
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.decelerationRate = .fast
        scrollView.backgroundColor = .clear

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.tag = 99
        scrollView.addSubview(imageView)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        // Double Tap to Zoom (1.0x <-> 2.5x)
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        // Single Tap to Toggle Toolbar & Controls
        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleTap(_:)))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)

        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        if let imageView = uiView.viewWithTag(99) as? UIImageView {
            if imageView.image != image {
                imageView.image = image
                uiView.setZoomScale(1.0, animated: false)
            }
        }

        // Reset zoom back to normal scale when swiping to another photo
        if !isSelected && uiView.zoomScale != 1.0 {
            uiView.setZoomScale(1.0, animated: false)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomableImageView

        init(_ parent: ZoomableImageView) {
            self.parent = parent
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            scrollView.viewWithTag(99)
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            if let imageView = scrollView.viewWithTag(99) {
                let boundsSize = scrollView.bounds.size
                var frameToCenter = imageView.frame

                if frameToCenter.size.width < boundsSize.width {
                    frameToCenter.origin.x = (boundsSize.width - frameToCenter.size.width) / 2
                } else {
                    frameToCenter.origin.x = 0
                }

                if frameToCenter.size.height < boundsSize.height {
                    frameToCenter.origin.y = (boundsSize.height - frameToCenter.size.height) / 2
                } else {
                    frameToCenter.origin.y = 0
                }

                imageView.frame = frameToCenter
            }

            // Auto-hide controls when pinching in to zoom; show when pinch returns to 1.0x
            if scrollView.zoomScale > 1.05 && !parent.isControlsHidden {
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.parent.isControlsHidden = true
                    }
                }
            } else if scrollView.zoomScale <= 1.01 && parent.isControlsHidden {
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.parent.isControlsHidden = false
                    }
                }
            }
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            if scale <= 1.01 && parent.isControlsHidden {
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.parent.isControlsHidden = false
                    }
                }
            }
        }

        @objc func handleSingleTap(_ gesture: UITapGestureRecognizer) {
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.parent.isControlsHidden.toggle()
                }
            }
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            if scrollView.zoomScale > 1.01 {
                // Zoom Out -> Restore toolbar and thumbnail strip
                scrollView.setZoomScale(1.0, animated: true)
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        self.parent.isControlsHidden = false
                    }
                }
            } else {
                // Zoom In -> Hide toolbar and thumbnail strip
                let pointInView = gesture.location(in: scrollView.viewWithTag(99))
                let zoomRect = zoomRectForScale(scale: 2.5, center: pointInView, scrollView: scrollView)
                scrollView.zoom(to: zoomRect, animated: true)
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.parent.isControlsHidden = true
                    }
                }
            }
        }

        private func zoomRectForScale(scale: CGFloat, center: CGPoint, scrollView: UIScrollView) -> CGRect {
            var zoomRect = CGRect.zero
            zoomRect.size.height = scrollView.frame.size.height / scale
            zoomRect.size.width  = scrollView.frame.size.width  / scale
            zoomRect.origin.x    = center.x - (zoomRect.size.width  / 2.0)
            zoomRect.origin.y    = center.y - (zoomRect.size.height / 2.0)
            return zoomRect
        }
    }
}
