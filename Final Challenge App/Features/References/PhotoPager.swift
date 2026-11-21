//
//  PhotoPager.swift
//  Skema Photo
//
//  Created by Satriya Handha Wibowo on 21/11/26.
//


import SwiftUI
import UIKit

struct PhotoPager: UIViewControllerRepresentable {
    let images: [UIImage]
    @Binding var selection: Int
    var fitInsets: UIEdgeInsets = .zero
    var contentKey: [UUID] = []
    var onSingleTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pvc = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [.interPageSpacing: 20]
        )
        pvc.dataSource = context.coordinator
        pvc.delegate = context.coordinator
        pvc.view.backgroundColor = .clear
        pvc.view.subviews
            .compactMap { $0 as? UIScrollView }
            .forEach {
                $0.topEdgeEffect.isHidden = true
                $0.bottomEdgeEffect.isHidden = true
            }

        context.coordinator.lastCount = images.count
        context.coordinator.lastKey = contentKey
        if !images.isEmpty {
            let start = min(max(selection, 0), images.count - 1)
            pvc.setViewControllers([context.coordinator.page(at: start)],
                                   direction: .forward, animated: false)
        }
        return pvc
    }

    func updateUIViewController(_ pvc: UIPageViewController, context: Context) {
        let c = context.coordinator
        c.parent = self
        guard !images.isEmpty else { return }

        for vc in pvc.viewControllers ?? [] {
            (vc as? ZoomablePhotoVC)?.fitInsets = fitInsets
        }

        let target = min(max(selection, 0), images.count - 1)
        let contentChanged = c.lastCount != images.count || c.lastKey != contentKey
        c.lastCount = images.count
        c.lastKey = contentKey

        guard let currentVC = pvc.viewControllers?.first as? ZoomablePhotoVC,
              target != currentVC.index || contentChanged else { return }

        let distance = target - currentVC.index
        pvc.setViewControllers([c.page(at: target)],
                               direction: distance >= 0 ? .forward : .reverse,
                               animated: !contentChanged && abs(distance) == 1)
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PhotoPager
        var lastCount = 0
        var lastKey: [UUID] = []

        init(_ parent: PhotoPager) { self.parent = parent }

        func page(at index: Int) -> ZoomablePhotoVC {
            ZoomablePhotoVC(image: parent.images[index],
                            index: index,
                            fitInsets: parent.fitInsets) { [weak self] in
                self?.parent.onSingleTap()
            }
        }

        func pageViewController(_ pvc: UIPageViewController,
                                viewControllerBefore vc: UIViewController) -> UIViewController? {
            guard let i = (vc as? ZoomablePhotoVC)?.index, i > 0,
                  i - 1 < parent.images.count else { return nil }
            return page(at: i - 1)
        }

        func pageViewController(_ pvc: UIPageViewController,
                                viewControllerAfter vc: UIViewController) -> UIViewController? {
            guard let i = (vc as? ZoomablePhotoVC)?.index,
                  i + 1 < parent.images.count else { return nil }
            return page(at: i + 1)
        }

        func pageViewController(_ pvc: UIPageViewController, didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            guard completed,
                  let i = (pvc.viewControllers?.first as? ZoomablePhotoVC)?.index else { return }
            parent.selection = i
        }
    }
}

final class ZoomablePhotoVC: UIViewController, UIScrollViewDelegate {
    let index: Int
    var fitInsets: UIEdgeInsets {
        didSet { view.setNeedsLayout() }
    }

    private let image: UIImage
    private let onSingleTap: () -> Void
    private let scrollView = UIScrollView()
    private let contentView = UIView()      // the view that gets zoomed
    private let imageView = UIImageView()   // aspect-fit inside the inset area

    init(image: UIImage, index: Int, fitInsets: UIEdgeInsets, onSingleTap: @escaping () -> Void) {
        self.image = image
        self.index = index
        self.fitInsets = fitInsets
        self.onSingleTap = onSingleTap
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.topEdgeEffect.isHidden = true
        scrollView.bottomEdgeEffect.isHidden = true
        view.addSubview(scrollView)

        scrollView.addSubview(contentView)
        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        contentView.addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(singleTapped))
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(doubleTap)
        scrollView.addGestureRecognizer(singleTap)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if scrollView.zoomScale == 1 {
            contentView.frame = scrollView.bounds
            scrollView.contentSize = scrollView.bounds.size
        }
        // fitInsets keep the photo between the top bar and the thumbnail strip at 1x;
        // zooming scales the whole contentView, so the photo can still fill the screen.
        imageView.frame = contentView.bounds.inset(by: fitInsets)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { contentView }

    @objc private func singleTapped() { onSingleTap() }

    @objc private func doubleTapped(_ g: UITapGestureRecognizer) {
        if scrollView.zoomScale > 1 {
            scrollView.setZoomScale(1, animated: true)
        } else {
            let p = g.location(in: contentView)
            let scale: CGFloat = 2.5
            let size = CGSize(width: scrollView.bounds.width / scale,
                              height: scrollView.bounds.height / scale)
            scrollView.zoom(to: CGRect(x: p.x - size.width / 2, y: p.y - size.height / 2,
                                       width: size.width, height: size.height),
                            animated: true)
        }
    }
}
