import SceneKit
import SwiftUI

/// The LiDAR-only tap scan screen, to compare with the automatic `ScanView`: no object detection. Tap the subject,
/// then each light and camera; each tap collects that item's column of LiDAR points (nothing is drawn but the
/// tags). Finish Scan opens the same
/// lighting diagram, where everything can still be edited.
struct LiDARScanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: LiDARScanViewModel
    @State private var showReview = false
    var onDismissToSetups: (() -> Void)?

    init(viewModel: LiDARScanViewModel = LiDARScanViewModel(), onDismissToSetups: (() -> Void)? = nil) {
        _viewModel = State(initialValue: viewModel)
        self.onDismissToSetups = onDismissToSetups
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if viewModel.screen == .scanning, let session = viewModel.arSession {
                GeometryReader { geometry in
                    RoomScanView(session: session, scene: SCNScene())
                        .ignoresSafeArea()
                        .onTapGesture { tap in
                            viewModel.tap(atScreen: tap, screenSize: geometry.size)
                        }
                        .accessibilityLabel("Camera view")
                        .accessibilityHint("Tap the subject, a light or a camera")
                        .accessibilityAddTraits(.isButton)
                }
                .ignoresSafeArea()
                LiDARScanOverlayView(viewModel: viewModel)
                    .ignoresSafeArea()
            }
            content.padding(.horizontal, 24)
        }
        .overlay(alignment: .top) {
            if viewModel.screen == .scanning {
                topBar
            }
        }
        .overlay(alignment: .bottom) {
            if viewModel.screen == .scanning {
                bottomControls
            }
        }
        .environment(\.colorScheme, .dark)
        .fullScreenCover(isPresented: $showReview) {
            NavigationStack {
                ReviewView(
                    isFromLoadingScreen: true,
                    viewModel: ReviewViewModel(setup: viewModel.draftSetup),
                    onDismissToSetups: {
                        viewModel.closeTapped()
                        showReview = false
                        onDismissToSetups?()
                    }
                )
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel", systemImage: "chevron.left") {
                    viewModel.closeTapped()
                    dismiss()
                }
            }
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await viewModel.start() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await viewModel.appBecameActive() }
        }
    }

    private var topBar: some View {
        VStack(spacing: 8) {
            Text(chipText)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .glassEffect(.regular, in: .capsule)
            if let message = viewModel.message {
                Text(message)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.6), in: .capsule)
            }
        }
        .padding(.top, 8)
    }

    private var chipText: String {
        let cameras = viewModel.items.filter { $0.kind == .camera }.count
        let lights = viewModel.items.filter { $0.kind == .light }.count
        return "Subject \(viewModel.subject == nil ? "–" : "✓") • Camera \(cameras) • Studio Lighting \(lights)"
    }

    private var bottomControls: some View {
        VStack(spacing: 12) {
            Picker("Tap sets", selection: $viewModel.kind) {
                Text("Subject").tag(LiDARTapKind.subject)
                Text("Light").tag(LiDARTapKind.light)
                Text("Camera").tag(LiDARTapKind.camera)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)

            Button {
                viewModel.finishTapped()
                showReview = true
            } label: {
                HStack(spacing: 10) {
                    Text("Finish Scan")
                    Image(systemName: "checkmark").accessibilityHidden(true)
                }
                .font(.title3)
                .padding(.horizontal, 24)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.extraLarge)
            .disabled(!viewModel.canFinish)
        }
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.screen {
        case .starting:
            ProgressView()
        case .scanning:
            EmptyView()
        case .cameraDenied:
            ContentUnavailableView("Camera Access Is Off", systemImage: "video.slash",
                                   description: Text("Turn the camera on in Settings to scan."))
        case .lidarUnsupported:
            ContentUnavailableView("LiDAR Not Available", systemImage: "iphone.slash",
                                   description: Text("Scanning needs an iPhone with LiDAR."))
        case .failed(let message):
            ContentUnavailableView("Scan Stopped", systemImage: "exclamationmark.triangle", description: Text(message))
        }
    }
}

/// The tags, pinned to each tapped point: "Subject ✓" and, for each item, its name with the live distance and height.
private struct LiDARScanOverlayView: View {
    let viewModel: LiDARScanViewModel

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(viewModel.items) { item in
                    if let point = viewModel.tagPosition(of: item.anchor, in: geometry.size) {
                        tag(viewModel.tagText(for: item), status: viewModel.statusText(for: item),
                            isSaved: viewModel.isSaved(item)).position(point)
                    }
                }
                if let subject = viewModel.subject,
                   let point = viewModel.tagPosition(of: subject, in: geometry.size) {
                    tag("Subject ✓", status: viewModel.subjectStatusText, isSaved: viewModel.subjectIsSaved)
                        .position(point)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func tag(_ text: String, status: String, isSaved: Bool) -> some View {
        VStack(spacing: 2) {
            Text(text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
            Text(status)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isSaved ? Color.green : Color.orange)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.55), in: .rect(cornerRadius: 12))
        .fixedSize()
    }
}
