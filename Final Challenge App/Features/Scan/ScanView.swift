import SwiftUI

/// The scan screen (LiDAR only, no object detection), guided step by step (Sketch UT Review T01–T10): point at the
/// floor until it is found (A10-112, no tap), then tap the product, the camera and each light; each tap sets the next
/// thing still missing. One instruction in the middle of the screen says what to do, like Apple's Measure
/// (`ScanInstruction`): the step, a short "done" line, a problem, or what the last tap did; on the first scan (or
/// after ?) it adds a small line saying why. Undo takes back the last tap. Each tapped item gets a box and tag; the
/// floor is not drawn. ✕ asks before throwing the taps away, and Finish Scan opens the lighting diagram, where
/// everything can still be edited. Without camera access or LiDAR it shows a message with "Add Equipment Manually"
/// (Sketch R02–R04x).
struct ScanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    /// The system appearance, read before this view forces dark for the camera screens.
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var viewModel: ScanViewModel
    @State private var reviewViewModel: ReviewViewModel?
    @State private var showsLeaveAlert = false
    /// Apple's coaching screen (`RoomScanView`) is showing: our instruction steps aside.
    @State private var isCoaching = false
    var onDismissToSetups: (() -> Void)?

    init(viewModel: ScanViewModel = ScanViewModel(),
         onDismissToSetups: (() -> Void)? = nil) {
        _viewModel = State(initialValue: viewModel)
        self.onDismissToSetups = onDismissToSetups
    }

    var body: some View {
        ZStack {
            background
            if viewModel.screen == .scanning, let session = viewModel.arSession {
                GeometryReader { geometry in
                    RoomScanView(session: session, outlines: viewModel.outlineBoxes,
                                 onCoachingChange: { coaching in withAnimation { isCoaching = coaching } })
                        .ignoresSafeArea()
                        .onTapGesture { tap in
                            viewModel.tap(atScreen: tap, screenSize: geometry.size)
                        }
                        .accessibilityLabel("Camera view")
                        .accessibilityHint(viewModel.currentStep.title)
                        .accessibilityAddTraits(.isButton)
                }
                .ignoresSafeArea()
                ScanTagsView(viewModel: viewModel)
                    .ignoresSafeArea()
                // Measure's look: one instruction; while Apple's coaching screen shows, it is the only one.
                if !isCoaching {
                    ScanInstructionView(instruction: viewModel.instruction)
                        .animation(.default, value: viewModel.instruction)
                }
            }
            content.padding(.horizontal, 24)
        }
        .overlay(alignment: .bottom) {
            bottomControls
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
                // A popover on the X (like Reminders); tapping outside it keeps scanning.
                .confirmationDialog(
                    "Are you sure you want to cancel this scan? Everything you tapped so far will be lost.",
                    isPresented: $showsLeaveAlert,
                    titleVisibility: .visible
                ) {
                    Button("Cancel Scan", role: .destructive) {
                        leave()
                    }
                }
            }
            if viewModel.screen == .scanning {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Undo", systemImage: "arrow.uturn.backward") {
                        withAnimation { viewModel.undoTapped() }
                    }
                    .disabled(!viewModel.canUndo)
                    .accessibilityHint("Takes back the last tap")
                }
            }
        }
        .toolbarColorScheme(usesCameraAppearance ? .dark : nil, for: .navigationBar)
        .task { await viewModel.start() }
        .task(id: viewModel.completedStep) {
            guard viewModel.completedStep != nil else { return }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            withAnimation { viewModel.clearCompletedStep() }
        }
        .task(id: viewModel.feedback) {
            guard viewModel.feedback != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation { viewModel.clearFeedback() }
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
        reviewViewModel = ReviewViewModel(setup: viewModel.draftSetup, storageController: viewModel.storageController)
    }

    private var bottomControls: some View {
        VStack(spacing: 16) {
            if viewModel.screen == .scanning {
                ScanStatusChips(
                    hasFloor: viewModel.hasFloor,
                    hasSubject: viewModel.subject != nil,
                    hasCamera: viewModel.items.contains { $0.kind == .camera },
                    hasLight: viewModel.items.contains { $0.kind == .light }
                )
            }
            if showsFinishScan {
                ScanFinishButton(isEnabled: viewModel.canFinish) {
                    viewModel.finishTapped()
                    reviewViewModel = ReviewViewModel(setup: viewModel.draftSetup,
                                                      storageController: viewModel.storageController)
                }
            }
        }
        .padding(.bottom, 8)
    }

    /// Finish Scan shows while scanning; in the simulator (no camera) always, to reach the plan.
    private var showsFinishScan: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        viewModel.screen == .scanning
        #endif
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

/// What is drawn over the camera for each tap (Sketch T02–T09): a green box with a tag above it for the subject and
/// each camera and light (the floor has no tag since A10-112). A tag is green once its values are saved; why it is not
/// yet is said by the instruction ("Too far to measure", "Need a closer look").
private struct ScanTagsView: View {
    let viewModel: ScanViewModel

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                if let subject = viewModel.subject {
                    marker(title: "Subject", isSaved: viewModel.subjectIsSaved,
                           box: viewModel.subjectBox(in: size),
                           anchor: viewModel.tagPosition(of: subject, in: size), size: size)
                }
                ForEach(viewModel.items) { item in
                    marker(title: viewModel.shortTitle(for: item),
                           isSaved: viewModel.isSaved(item),
                           box: viewModel.box(for: item, in: size),
                           anchor: viewModel.tagPosition(of: item.anchor, in: size), size: size)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The tag just above the item's box (or at the tapped point while there is no box yet). The box itself is drawn
    /// in 3D in the camera view (A10-106, `ScanOutlines`).
    @ViewBuilder
    private func marker(title: String, isSaved: Bool, box: CGRect?, anchor: CGPoint?, size: CGSize) -> some View {
        if let point = box.map({ CGPoint(x: $0.midX, y: $0.minY - 20) }) ?? anchor {
            ScanTag(title: title, isSaved: isSaved).position(clamped(point, in: size))
        }
    }

    /// Keeps a tag fully on the screen.
    private func clamped(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: min(max(point.x, 60), size.width - 60), y: min(max(point.y, 24), size.height - 24))
    }
}

/// "Light ✓" in black on green once saved; until then just the title on dark glass. Why it is not saved yet is said by
/// the scan's instruction, not on the tag.
struct ScanTag: View {
    let title: String
    let isSaved: Bool

    var body: some View {
        Group {
            if !isSaved {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .glassEffect(.regular.tint(ScanPalette.glassTint), in: .capsule)
            } else {
                Text("\(title) ✓")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(ScanPalette.onGreen)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background(ScanPalette.green, in: .capsule)
            }
        }
        .fixedSize()
    }
}
