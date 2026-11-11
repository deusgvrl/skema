#if DEBUG
import ARKit
import RealityKit
import SwiftUI

/// Debug screen for measuring on a LiDAR iPhone (A10-41). Not in release builds.
/// Tap the subject, then tap the parts of each item (feet and top of a stand), and read the results in the panel.
struct MeasureDebugView: View {
    @State private var viewModel = MeasureDebugViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .bottom) {
            MeasureARView(arView: viewModel.arView) { viewModel.tapped(at: $0) }
                .ignoresSafeArea()
            MeasureDebugDetectionOverlay(
                detections: viewModel.detector.detections, imageToView: viewModel.detector.imageToView
            )
            .ignoresSafeArea()
            MeasureDebugPanel(viewModel: viewModel) { dismiss() }
        }
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
        .onChange(of: viewModel.radiusCentimetres) { viewModel.radiusChanged() }
        .onChange(of: viewModel.detectorEnabled) { viewModel.detectorToggled() }
        .onChange(of: viewModel.bandOn) { viewModel.bandToggled() }
    }
}

private struct MeasureDebugPanel: View {
    @Bindable var viewModel: MeasureDebugViewModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.statusText).font(.caption)
            Text(viewModel.floorText).font(.footnote.bold())
            Text(viewModel.depthText).font(.caption)
            Text(viewModel.validationText).font(.caption)
            Text(viewModel.detector.statusText).font(.caption)

            Picker("Painting", selection: $viewModel.target) {
                ForEach(MeasureDebugViewModel.Target.allCases, id: \.self) { target in
                    Text(target.rawValue).tag(target)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Button("New item") { viewModel.newItem() }
                Stepper(
                    "Column radius \(Int(viewModel.radiusCentimetres)) cm",
                    value: $viewModel.radiusCentimetres, in: 5...30, step: 5
                )
            }

            HStack {
                Toggle("Detector", isOn: $viewModel.detectorEnabled)
                Toggle("Band 15 cm", isOn: $viewModel.bandOn)
            }

            HStack {
                Button("Reset", role: .destructive) { viewModel.reset() }
                Button("Undo tap") { viewModel.undoLastTap() }
                Spacer()
                Button("Close", action: close)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(viewModel.rows) { row in
                        Text(row.text).font(.caption2.monospacedDigit())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 140)
        }
        .padding()
        .background(.regularMaterial)
    }
}

/// Shows the `ARView` that `ScanSession` runs and reports where the user taps it.
private struct MeasureARView: UIViewRepresentable {
    let arView: ARView
    let onTap: (CGPoint) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    func makeUIView(context: Context) -> ARView {
        let recogniser = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        arView.addGestureRecognizer(recogniser)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.onTap = onTap
    }

    final class Coordinator: NSObject {
        var onTap: (CGPoint) -> Void

        init(onTap: @escaping (CGPoint) -> Void) {
            self.onTap = onTap
        }

        @objc func tapped(_ recogniser: UITapGestureRecognizer) {
            onTap(recogniser.location(in: recogniser.view))
        }
    }
}
#endif
