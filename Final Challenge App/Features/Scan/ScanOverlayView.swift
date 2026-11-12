import MeasureKit
import SwiftUI

/// Draws the scan overlay over the camera (A10-62): masks, "Detecting…" tags with their ring, accepted tags.
/// Full screen, the same size as the camera view, so `ScanOverlay`'s screen points line up with the picture.
/// Taps go through to the camera view and the buttons. Style follows Sketch R03 once it is checked.
struct ScanOverlayView: View {
    let viewModel: ScanViewModel

    var body: some View {
        GeometryReader { geometry in
            if let overlay = viewModel.overlay(in: geometry.size),
               let camera = viewModel.overlayCamera {
                let rect = MaskImage.pictureRect(camera: camera, screenSize: geometry.size)
                ZStack {
                    ForEach(Array(overlay.items.enumerated()), id: \.offset) { _, item in
                        if let mask = item.mask, let color = item.maskColor,
                           let image = MaskImage.image(of: mask, color: color) {
                            Image(decorative: image, scale: 1)
                                .resizable()
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                        }
                    }
                    ForEach(Array(overlay.items.enumerated()), id: \.offset) { _, item in
                        if let point = item.tagPosition {
                            ScanTag(item: item)
                                .position(point)
                        }
                    }
                    if let subject = overlay.subject, let point = subject.tagPosition {
                        ScanTag(item: subject)
                            .position(point)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One tag: "Detecting…" with its progress ring, or an accepted tag such as "Camera 1 ✓".
private struct ScanTag: View {
    let item: OverlayItem

    var body: some View {
        HStack(spacing: 6) {
            if let ring = item.ring {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.3), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: ring)
                        .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 14, height: 14)
            }
            Text(item.tag)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.55), in: .capsule)
        .fixedSize()
    }
}

/// One chip per kind with accepted items ("Camera • 2"), shown at the top of the scan (A10-62).
struct ScanChips: View {
    let viewModel: ScanViewModel

    var body: some View {
        let chips = viewModel.overlay(in: .zero)?.chips ?? []
        HStack(spacing: 8) {
            ForEach(chips, id: \.self) { chip in
                Text(chip)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: .capsule)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
