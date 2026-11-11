#if DEBUG
import MeasureKit
import SwiftUI

/// One detection as the debug screen shows it: what the detector thinks it is, how sure it was, the boxes that make up
/// its mask in the native camera image, and which item it was added to (nil when it was ignored).
nonisolated struct MeasureDebugDetection: Sendable {
    let kind: EquipmentKind
    let confidence: Float
    /// The mask as boxes in the native camera image: 0 to 1 in both directions, origin top-left.
    let boxes: [NormalizedBox]
    /// The name of the item the detection joined ("Light 1"), or nil when it was ignored.
    let itemName: String?
    /// How many usable depth points the mask had.
    let usablePoints: Int
}

extension EquipmentKind {
    /// How a detected item is named in the list and on the picture.
    nonisolated var debugName: String {
        switch self {
        case .studioLighting: "Light"
        case .camera: "Camera"
        }
    }
}

/// Draws the detector's masks over the camera picture: a tint on the mask, a thin outline around it and a label at its
/// top left. Yellow is studio lighting, cyan is a camera, grey is a detection that was ignored.
/// It shows the frame the detector last ran on, so it trails a little behind while the phone moves.
struct MeasureDebugDetectionOverlay: View {
    let detections: [MeasureDebugDetection]
    /// How a point of the native camera image lands on the screen, normalised to normalised
    /// (ARKit's display transform).
    let imageToView: CGAffineTransform

    var body: some View {
        Canvas { context, size in
            for detection in detections {
                draw(detection, in: &context, size: size)
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(_ detection: MeasureDebugDetection, in context: inout GraphicsContext, size: CGSize) {
        let colour = Self.colour(of: detection)
        var outline = CGRect.null
        for box in detection.boxes {
            let rect = viewRect(of: box, size: size)
            context.fill(Path(rect), with: .color(colour.opacity(0.35)))
            outline = outline.union(rect)
        }
        guard !outline.isNull else { return }
        context.stroke(Path(outline), with: .color(colour), lineWidth: 2)
        let label = Text(Self.label(of: detection)).font(.caption.bold()).foregroundStyle(colour)
        context.draw(label, at: CGPoint(x: outline.minX + 4, y: outline.minY + 2), anchor: .topLeading)
    }

    private func viewRect(of box: NormalizedBox, size: CGSize) -> CGRect {
        let image = CGRect(x: box.x, y: box.y, width: box.width, height: box.height)
        let view = image.applying(imageToView)
        return CGRect(
            x: view.minX * size.width, y: view.minY * size.height,
            width: view.width * size.width, height: view.height * size.height
        )
    }

    private static func colour(of detection: MeasureDebugDetection) -> Color {
        guard detection.itemName != nil else { return .gray }
        return detection.kind == .camera ? .cyan : .yellow
    }

    private static func label(of detection: MeasureDebugDetection) -> String {
        let percent = Int((detection.confidence * 100).rounded())
        if let name = detection.itemName { return "\(name) · \(percent) %" }
        return "\(detection.kind.debugName) · \(percent) % · ignored: \(detection.usablePoints) depth points"
    }
}
#endif
