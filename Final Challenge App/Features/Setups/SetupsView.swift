import SwiftUI

/// Saved setups, by month or by client (Sketch R01, R01b, R01f, R01q, R01v, R01z · A10-13).
struct SetupsView: View {
    @State private var viewModel = SetupsViewModel()
    @State private var reviewViewModel: ReviewViewModel?
    @State private var isShowingRecentlyDeleted = false
    @FocusState private var isSearchFocused: Bool
    @ScaledMetric(relativeTo: .title2) private var bottomControlSize: CGFloat = 48

    private let gridColumns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        @Bindable var viewModel = viewModel
        NavigationStack {
            ZStack {
                background
                content
            }
            .safeAreaInset(edge: .bottom) {
                SetupsBottomBarView(
                    viewModel: viewModel,
                    isSearchFocused: $isSearchFocused,
                    bottomControlSize: bottomControlSize
                )
            }
            .navigationTitle("Setups")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    groupMenu
                }
            }
            .navigationDestination(for: Setup.self) { selectedSetup in
                SetupDetailView(setup: selectedSetup)
            }
            .fullScreenCover(item: $reviewViewModel) { reviewModel in
                NavigationStack {
                    ReviewView(
                        isFromLoadingScreen: true,
                        viewModel: reviewModel,
                        onDismissToSetups: {
                            reviewViewModel = nil
                            viewModel.fetchSetups()
                        }
                    )
                }
            }
            .navigationDestination(isPresented: $viewModel.isShowingScan) {
                ScanView(onDismissToSetups: {
                    viewModel.isShowingScan = false
                })
            }
            .navigationDestination(isPresented: $isShowingRecentlyDeleted) {
                RecentlyDeletedView()
            }
            .onAppear {
                viewModel.fetchSetups()
            }
            .onChange(of: isShowingRecentlyDeleted) { _, isShowing in
                if !isShowing { viewModel.fetchSetups() }
            }
            .alert(
                "Delete This Setup?",
                isPresented: Binding(
                    get: { viewModel.setupPendingDelete != nil },
                    set: { isPresented in if !isPresented { viewModel.cancelDelete() } }
                ),
                presenting: viewModel.setupPendingDelete
            ) { _ in
                Button("Delete", role: .destructive) { withAnimation { viewModel.confirmDelete() } }
                Button("Cancel", role: .cancel) { viewModel.cancelDelete() }
            } message: { setup in
                Text(viewModel.deleteMessage(for: setup))
            }
        }
        .environment(\.setupSavedAction) { viewModel.setupSaved() }
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            DesignTokens.pageBackground
            DesignTokens.scrimGradient
        }
        .ignoresSafeArea()
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.showsEmptyState {
            SetupsEmptyStateView()
        } else if viewModel.showsNoResults {
            ContentUnavailableView.search(text: viewModel.searchText)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    switch viewModel.grouping {
                    case .recent:
                        ForEach(viewModel.recentSections) { section in
                            gridSection(title: section.title, setups: section.setups)
                        }
                    case .byClient:
                        // One grid per client, its months in order (Sketch UT Review A-S03).
                        ForEach(viewModel.clientGroups) { group in
                            gridSection(title: group.title, setups: group.sections.flatMap(\.setups))
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }

    /// A heading (a month, "Not saved" or a client) over a 2-column grid of setups (Sketch UT Review A-S02).
    private func gridSection(title: String, setups: [Setup]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(DesignTokens.textPrimary)
                .padding(.horizontal)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 18) {
                ForEach(setups) { setup in
                    if setup.firstSavedDate == nil {
                        Button {
                            reviewViewModel = ReviewViewModel(
                                setup: setup,
                                storageController: viewModel.storageController
                            )
                        } label: {
                            SetupGridItem(setup: setup)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { deleteButton(for: setup) }
                    } else {
                        NavigationLink(value: setup) {
                            SetupGridItem(setup: setup)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { deleteButton(for: setup) }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func deleteButton(for setup: Setup) -> some View {
        Button(role: .destructive) {
            viewModel.deleteTapped(setup)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Toolbar

    private var groupMenu: some View {
        Menu {
            // Every row has an icon, so all titles line up in one column.
            Picker("Group By", selection: Bindable(viewModel).grouping) {
                Label("Recent", systemImage: "clock").tag(SetupsGrouping.recent)
                Label("By Client", systemImage: "person.2").tag(SetupsGrouping.byClient)
            }
            .pickerStyle(.inline)

            Divider()

            // Destructive role is what turns a menu row's title and icon red.
            Button("Recently Deleted", systemImage: "trash", role: .destructive) {
                isShowingRecentlyDeleted = true
            }
        } label: {
            Label("Group By", systemImage: "line.3.horizontal.decrease")
        }
    }
}

// MARK: - Extracted Subviews

private struct SetupsEmptyStateView: View {
    var body: some View {
        ContentUnavailableView {
            Label {
                Text("No Setups Yet")
                    .font(.title2.bold())
                    .foregroundStyle(DesignTokens.textPrimary)
            } icon: {
                LightStandGlyph()
                    .stroke(DesignTokens.textSecondary, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                    .frame(width: 40, height: 52)
            }
        } description: {
            Text("""
                Scan your first lighting setup. The diagram, \
                equipment and references are saved here, so you can rebuild it next time.
                """)
            .font(.subheadline)
            .foregroundStyle(DesignTokens.textSecondary)
        }
    }
}

private struct SetupsBottomBarView: View {
    @Bindable var viewModel: SetupsViewModel
    @FocusState.Binding var isSearchFocused: Bool
    let bottomControlSize: CGFloat

    var body: some View {
        VStack(spacing: 8) {
            if viewModel.lastDeleted != nil {
                deletedToast
            } else if viewModel.showsSavedToast {
                savedToast
            }
            HStack(spacing: 12) {
                searchField
                if isSearchFocused || !viewModel.searchText.isEmpty {
                    cancelSearchButton
                } else {
                    newSetupButton
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .animation(.default, value: viewModel.lastDeleted != nil)
        .animation(.default, value: viewModel.showsSavedToast)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DesignTokens.textSecondary)
                .accessibilityHidden(true)
            TextField("Search", text: $viewModel.searchText)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .foregroundStyle(DesignTokens.textPrimary)
            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DesignTokens.textSecondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: bottomControlSize)
        .glassControl(cornerRadius: bottomControlSize / 2)
    }

    private var cancelSearchButton: some View {
        Button {
            viewModel.searchText = ""
            isSearchFocused = false
        } label: {
            Image(systemName: "xmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(DesignTokens.textPrimary)
                .frame(width: bottomControlSize, height: bottomControlSize)
        }
        .glassControl(cornerRadius: bottomControlSize / 2)
        .accessibilityLabel("Cancel search")
    }

    private var newSetupButton: some View {
        Button {
            viewModel.newSetupTapped()
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: bottomControlSize, height: bottomControlSize)
                .background(DesignTokens.accentPrimary, in: .circle)
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
        }
        .accessibilityLabel("New Setup")
    }

    private var deletedToast: some View {
        ToastBar(systemImage: "trash", message: "Moved to Recently Deleted", actionTitle: "Undo") {
            withAnimation { viewModel.undoDelete() }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task(id: viewModel.lastDeleted?.id) {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation { viewModel.dismissUndo() }
        }
    }

    private var savedToast: some View {
        ToastBar(systemImage: "checkmark", message: "Setup Saved")
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                withAnimation { viewModel.dismissSavedToast() }
            }
    }
}

/// A light head on a stand (Sketch R01z empty-state icon), drawn so it follows the text tokens.
private struct LightStandGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.minY + rect.width * 0.5)
        let radius = rect.width * 0.5
        for index in 0..<8 {
            let angle = (Double(index) + 0.5) * .pi / 4
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()

        let stemTop = CGPoint(x: rect.midX, y: center.y + radius)
        let stemBottom = CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.12)
        path.move(to: stemTop)
        path.addLine(to: stemBottom)
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.15, y: rect.maxY))
        path.addLine(to: stemBottom)
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.15, y: rect.maxY))
        return path
    }
}

#Preview {
    SetupsView()
}

enum SetupsGrouping {
    case recent
    case byClient
}
