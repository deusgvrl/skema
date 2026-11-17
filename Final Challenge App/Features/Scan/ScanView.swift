import SwiftUI

/// Scan guide, camera permission, live scan, processing, leave alert (Sketch R02–R04x · A10-4, A10-5).
struct ScanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    /// The system appearance, read before this view forces dark for the camera screens.
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var viewModel: ScanViewModel
    @State private var reviewViewModel: ReviewViewModel?
    @State private var showsLeaveAlert = false
    var onDismissToSetups: (() -> Void)?

    init(
            viewModel: ScanViewModel = ScanViewModel(),
            onDismissToSetups: (() -> Void)? = nil
        ) {
            _viewModel = State(initialValue: viewModel)
            self.onDismissToSetups = onDismissToSetups
        }

    var body: some View {
        ZStack {
            background
            if viewModel.screen == .scanning, let session = viewModel.arSession {
                GeometryReader { geometry in
                    RoomScanView(session: session)
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
                    VStack(spacing: 16) {
                        if viewModel.screen == .scanning, let guidance = viewModel.guidance {
                            ScanGuidanceView(guidance: guidance)
                                .transition(.opacity)
                        }
                        if showsFinishScan {
                            finishScanButton
                        }
                    }
                    .animation(.default, value: viewModel.guidance)
                }
        .environment(\.colorScheme, usesCameraAppearance ? .dark : systemColorScheme)
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
                        Button("Close", systemImage: "xmark") {
                            if viewModel.asksBeforeLeaving {
                                showsLeaveAlert = true
                            } else {
                                leave()
                            }
                        }
                    }
                }

                .alert("Cancel This Scan?", isPresented: $showsLeaveAlert) {
                    Button("Continue", role: .cancel) {}
                    Button("Cancel Scan", role: .destructive) {
                        leave()
                    }
                } message: {
                    Text("Everything detected so far will be lost.")
                }
        .toolbarColorScheme(usesCameraAppearance ? .dark : nil, for: .navigationBar)
        .task {
            await viewModel.start()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await viewModel.appBecameActive() }
        }
    }

    private var usesCameraAppearance: Bool {
        viewModel.screen.usesCameraAppearance
    }

    @ViewBuilder
    private var background: some View {
        if usesCameraAppearance {
            Color.black
                .ignoresSafeArea()
        } else {
            ZStack {
                DesignTokens.pageBackground
                DesignTokens.scrimGradient
            }
            .ignoresSafeArea()
        }
    }

    private func leave() {
        viewModel.closeTapped()
        dismiss()
    }

    private func addEquipmentManually() {
           viewModel.insertDraftSetup()
           reviewViewModel = ReviewViewModel(
               setup: viewModel.draftSetup, storageController: viewModel.storageController
           )
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
                reviewViewModel = ReviewViewModel(setup: viewModel.draftSetup, storageController: viewModel.storageController)
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
            ScanMessageView(
                title: "Scan Stopped",
                systemImage: "exclamationmark.triangle",
                message: Text(verbatim: message)
            )
        }
    }

    private var cameraDenied: some View {
        ScanMessageView(
            title: "Camera Access Is Off",
            systemImage: "video.slash",
            message: Text("""
                Lighting Memory needs the camera to scan your set. \
                Turn it on in Settings, or add your equipment by hand.
                """)
        ) {
            ScanPrimaryButton(title: "Open Settings") {
                if let settings = URL(string: UIApplication.openSettingsURLString) {
                    openURL(settings)
                }
            }

            Button("Add Equipment Manually") {
                addEquipmentManually()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(DesignTokens.accentText)
        }
    }

    private var lidarUnsupported: some View {
        ScanMessageView(
            title: "LiDAR Not Available",
            systemImage: "iphone.slash",
            message: Text("""
                Scanning needs an iPhone with LiDAR, such as an iPhone Pro. \
                You can still add your equipment by hand.
                """)
        ) {
            ScanPrimaryButton(title: "Add Equipment Manually") {
                addEquipmentManually()
            }
        }
    }
}

/// A full-screen message instead of the camera: glass icon circle, title, body, actions (Sketch R02c).
private struct ScanMessageView<Actions: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    let message: Text
    @ViewBuilder let actions: () -> Actions

    @ScaledMetric(relativeTo: .largeTitle) private var iconCircleSize: CGFloat = 80

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: systemImage)
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(DesignTokens.textPrimary)
                .frame(width: iconCircleSize, height: iconCircleSize)
                .glassEffect(.regular.tint(DesignTokens.glassControlFill), in: .circle)
                .accessibilityHidden(true)

            Text(title)
                .font(.title2.bold())
                .foregroundStyle(DesignTokens.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 8)

            message
                .font(.subheadline)
                .foregroundStyle(DesignTokens.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.top, 12)

            VStack(spacing: 14) {
                actions()
            }
            .padding(.top, 62)
        }
    }
}

extension ScanMessageView where Actions == EmptyView {
    init(title: LocalizedStringKey, systemImage: String, message: Text) {
        self.init(title: title, systemImage: systemImage, message: message) { EmptyView() }
    }
}

/// Red capsule with a white label (Sketch R02c "Open Settings").
private struct ScanPrimaryButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(DesignTokens.accentPrimary, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
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
