import SwiftUI

/// Scan guide, camera permission, live scan, processing, leave alert (Sketch R02–R04x · A10-4, A10-5).
struct ScanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: ScanViewModel
    @State private var reviewViewModel: ReviewViewModel? = nil
    var onDismissToSetups: (() -> Void)?

    /// "Add Equipment Manually", when the camera is off or there is no LiDAR.
    var onAddManually: (() -> Void)?

    init(
        viewModel: ScanViewModel = ScanViewModel(),
        onDismissToSetups: (() -> Void)? = nil,
        onAddManually: (() -> Void)? = nil
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onDismissToSetups = onDismissToSetups
        self.onAddManually = onAddManually
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            if viewModel.screen == .scanning, let session = viewModel.arSession {
                GeometryReader { geometry in
                    RoomScanView(session: session, scene: viewModel.pointCloud.scene)
                        .ignoresSafeArea()
                        .onTapGesture { tap in
                            viewModel.setSubject(atScreen: tap, screenSize: geometry.size)
                        }
                        .accessibilityLabel("Camera view")
                        .accessibilityHint("Tap the product to set it as the subject")
                        .accessibilityAddTraits(.isButton)
                }
                .ignoresSafeArea()
                ScanOverlayView(viewModel: viewModel)
                    .ignoresSafeArea()
                }
            content
                .padding(.horizontal, 24)
        }
        .overlay(alignment: .top) {
            if viewModel.screen == .scanning {
                ScanChips(viewModel: viewModel)
                    .padding(.top, 8)
            }
        }
        .overlay(alignment: .bottom) {
            if showsFinishScan {
                finishScanButton
            }
        }
        .environment(\.colorScheme, .dark)
        .fullScreenCover(item: $reviewViewModel) { vm in
            NavigationStack {
                ReviewView(
                    isFromLoadingScreen: true,
                    viewModel: vm, 
                    onDismissToSetups: {
                        reviewViewModel = nil // Dismisses cover
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
        .task {
            await viewModel.start()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await viewModel.appBecameActive() }
        }
    }
    private var showsFinishScan: Bool {
            #if targetEnvironment(simulator)
            true
            #else
            viewModel.screen == .scanning
            #endif
    }

    private var finishScanButton: some View {
            Button {
                viewModel.finishTapped()
                reviewViewModel = ReviewViewModel(setup: viewModel.draftSetup)
            } label: {
                HStack(spacing: 10) {
                    Text("Finish Scan")
                    Image(systemName: "checkmark")
                        .accessibilityHidden(true)
                }
                .font(.title3)
                .padding(.horizontal, 24)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.extraLarge)
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
            cameraDenied
        case .lidarUnsupported:
            lidarUnsupported
        case .failed(let message):
            ContentUnavailableView("Scan Stopped", systemImage: "exclamationmark.triangle", description: Text(message))
        }
    }

    private var cameraDenied: some View {
        VStack(spacing: 32) {
            unavailable(
                "Camera Access Is Off",
                systemImage: "video.slash",
                message: """
                    Skema Photo needs the camera to scan your set. \
                    Turn it on in Settings, or add your equipment by hand.
                    """
            )

            VStack(spacing: 16) {
                Button {
                    if let settings = URL(string: UIApplication.openSettingsURLString) {
                        openURL(settings)
                    }
                } label: {
                    Text("Open Settings")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.extraLarge)

                Button("Add Equipment Manually") {
                    onAddManually?()
                }
                .fontWeight(.semibold)
            }
        }
    }

    private var lidarUnsupported: some View {
        VStack(spacing: 32) {
            unavailable(
                "LiDAR Not Available",
                systemImage: "iphone.slash",
                message: """
                    Scanning needs an iPhone with LiDAR, such as an iPhone Pro. \
                    You can still add your equipment by hand.
                    """
            )

            Button {
                onAddManually?()
            } label: {
                Text("Add Equipment Manually")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.extraLarge)
        }
    }

    private func unavailable(
        _ title: LocalizedStringKey,
        systemImage: String,
        message: LocalizedStringKey
    ) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview("Camera access is off") {
    NavigationStack {
        ScanView(viewModel: ScanViewModel(
            makeScan: { ScanSession(supportsLiDAR: { true }) },
            camera: FixedCameraPermission(status: .denied)
        ))
    }
}

#Preview("No LiDAR") {
    NavigationStack {
        ScanView(viewModel: ScanViewModel(
            makeScan: { ScanSession(supportsLiDAR: { false }) },
            camera: FixedCameraPermission(status: .authorized)
        ))
    }
}
