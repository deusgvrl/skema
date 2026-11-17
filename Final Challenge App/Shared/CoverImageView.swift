//
//  CoverImageView.swift
//  Final Challenge App
//
//  Reference photos are full camera JPEGs, so list thumbnails are downsampled off the
//  main actor with ImageIO and cached, instead of decoding the full bitmap in `body`.
//

import ImageIO
import SwiftUI

/// Decodes `data` straight to a thumbnail whose longest side is at most `maxPixelSize` pixels.
@concurrent
nonisolated func downsampledImage(from data: Data, maxPixelSize: CGFloat) async -> UIImage? {
    let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
    let thumbnailOptions = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
    ] as CFDictionary
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
    return UIImage(cgImage: cgImage)
}

private enum CoverThumbnailCache {
    static let images = NSCache<NSString, UIImage>()
}

/// Shows a reference photo as a downsampled thumbnail, or `placeholder` when there is none.
struct CoverImageView<Placeholder: View>: View {
    let reference: ReferenceImage?
    /// Longest side the image is drawn at, in points.
    let pointSize: CGFloat
    @ViewBuilder let placeholder: () -> Placeholder

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: reference?.id) {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        guard let reference else {
            image = nil
            return
        }
        let maxPixelSize = pointSize * displayScale
        let key = "\(reference.id.uuidString)-\(Int(maxPixelSize))" as NSString
        if let cached = CoverThumbnailCache.images.object(forKey: key) {
            image = cached
            return
        }
        image = nil
        let data = reference.imageData
        guard let thumbnail = await downsampledImage(from: data, maxPixelSize: maxPixelSize) else { return }
        CoverThumbnailCache.images.setObject(thumbnail, forKey: key)
        image = thumbnail
    }
}
