import SwiftUI

/// The "Centres" debug view's name tags: one at each item's top centre, in the item's colour. Full screen like the
/// camera, so `ScanOverlay.screenPoint` lines up with the picture. Taps go through.
struct UsedPointsTagsView: View {
    let viewModel: ScanViewModel

    var body: some View {
        GeometryReader { geometry in
            ForEach(viewModel.usedPoints) { item in
                if let camera = viewModel.camera,
                   let point = ScanOverlay.screenPoint(of: item.topCentre, camera: camera, screenSize: geometry.size) {
                    Text(item.name)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(red: Double(item.color.x), green: Double(item.color.y),
                                          blue: Double(item.color.z)), in: .capsule)
                        .fixedSize()
                        .position(x: point.x, y: point.y - 26)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
