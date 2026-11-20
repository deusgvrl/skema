import SwiftUI

/// The scan screen (LiDAR only, no object detection): tap the subject, then pick Light or Camera and tap each item;
/// each tap collects that item's column of LiDAR points (nothing is drawn but the tags). Tips show when the scan goes
/// badly, ✕ asks before throwing the taps away, and Finish Scan opens the lighting diagram, where everything can still
/// be edited. Without camera access or LiDAR it shows a message with "Add Equipment Manually" (Sketch R02–R04x).
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

    init(viewModel: ScanViewModel = ScanViewModel(), onDismissToSetups: (() -> Void)? = nil) {
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
                            viewModel.tap(atScreen: tap, screenSize: geometry.size)
                        }
                        .accessibilityLabel("Camera view")
                        .accessibilityHint("Tap the subject, a light or a camera")
                        .accessibilityAddTraits(.isButton)
                }
                .ignoresSafeArea()
                ScanTagsView(viewModel: viewModel)
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
            bottomControls
                .animation(.default, value: viewModel.guidance)
        }
        .environment(\.colorScheme, usesCameraAppearance ? .dark : systemColorScheme)
        .fullScreenCover(item: $reviewViewModel) { reviewModel in
            NavigationStack {
                ReviewView(
                    isFromLoadingScreen: true,
                    viewModel: reviewModel,
                    onDismissToSetups: {
                        reviewViewModel = nil
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
            Text("Everything you tapped so far will be lost.")
        }
        .toolbarColorScheme(usesCameraAppearance ? .dark : nil, for: .navigationBar)
        .task { await viewModel.start() }
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
        reviewViewModel = ReviewViewModel(setup: viewModel.draftSetup, storageController: viewModel.storageController)
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
            if viewModel.screen == .scanning {
                if let guidance = viewModel.guidance {
                    ScanGuidanceView(guidance: guidance)
                        .transition(.opacity)
                }
                Picker("Tap sets", selection: $viewModel.kind) {
                    Text("Subject").tag(ScanTapKind.subject)
                    Text("Light").tag(ScanTapKind.light)
                    Text("Camera").tag(ScanTapKind.camera)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)
            }
            if showsFinishScan {
                finishScanButton
            }
        }
        .padding(.bottom, 16)
    }

    /// Finish Scan shows while scanning; in the simulator (no camera) always, to reach the plan.
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
            reviewViewModel = ReviewViewModel(setup: viewModel.draftSetup,
                                              storageController: viewModel.storageController)
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

/// The tags, pinned to each tapped point: "Subject ✓" and, for each item, its name with the live distance and height.
private struct ScanTagsView: View {
    let viewModel: ScanViewModel

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
