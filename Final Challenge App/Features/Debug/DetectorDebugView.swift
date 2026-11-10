#if DEBUG
import ARKit
import SceneKit
import SwiftUI

/// Debug-only screen for testing the equipment detector on a real iPhone (A10-60).
/// Full screen: the live camera (about 60 pictures a second) with the masks on top. The masks update once per
/// detection. Camera and masks both fill the screen from the centre, so the 4:3 picture is cut at the sides.
struct DetectorDebugView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: DetectorDebugViewModel?
    @State private var failure: String?

    var body: some View {
        ZStack {
            Color.black
            if let session = viewModel?.scanSession?.session as? ARSession {
                CameraPreview(session: session)
            }
            if let image = viewModel?.image {
                Color.clear
                    .overlay { Image(decorative: image, scale: 1).resizable().scaledToFill() }
                    .clipped()
                    .allowsHitTesting(false)
            }
            if viewModel == nil, failure == nil {
                ProgressView("Loading the model…").tint(.white).foregroundStyle(.white)
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 4) {
                if let viewModel { stats(viewModel) }
                if let failure { Text(failure).foregroundStyle(.red) }
                Spacer()
                Button("Close") { dismiss() }.buttonStyle(.borderedProminent)
            }
            .font(.caption.monospaced())
            .foregroundStyle(.white)
            .padding()
        }
        .statusBarHidden()
        .task { await start() }
    }

    private func stats(_ viewModel: DetectorDebugViewModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.lastMilliseconds.map { String(format: "%.0f ms per detection", $0) } ?? "– ms")
            Text("\(viewModel.detectionsPerSecond) detections per second")
            Text("Heat: \(viewModel.thermalText)")
            if let error = viewModel.errorText { Text(error).foregroundStyle(.red) }
            ForEach(viewModel.captions.indices, id: \.self) { Text(viewModel.captions[$0]) }
        }
        .padding(8)
        .background(.black.opacity(0.5), in: .rect(cornerRadius: 8))
    }

    private func start() async {
        do {
            let model = try await DetectorDebugViewModel.live()
            viewModel = model
            try await model.runLive()
        } catch {
            failure = "Could not start: \(error)"
        }
    }
}

/// The live camera of the scan's `ARSession`, filling the view (ARKit's world tracking uses the 1x wide camera).
private struct CameraPreview: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.session = session
        view.scene = SCNScene()
        view.automaticallyUpdatesLighting = false
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

extension DetectorDebugViewModel {
    /// Loads the bundled detector off the main actor, with a scan session at 10 frames per second.
    /// Change `frameInterval` here to try another rate (0.1 s = at most 10 frames a second to the detector).
    static func live() async throws -> DetectorDebugViewModel {
        let detector = try await Task.detached { try EquipmentDetector() }.value
        return DetectorDebugViewModel(detector: detector, render: { await DebugOverlayRenderer.render($0, $1) },
                                      scanSession: ScanSession(frameInterval: 0.1))
    }

    /// Runs the scan session until the screen closes.
    func runLive() async throws {
        guard let session = scanSession else { return }
        let frames = session.frames()
        try session.start()
        await run(frames: frames)
        session.stop()
    }
}
#endif
