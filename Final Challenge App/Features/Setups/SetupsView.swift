import SwiftUI

/// Saved setups, by month or by client (Sketch R01, R01b, R01f, R01q, R01v, R01z · A10-13).
struct SetupsView: View {
    @State private var viewModel = SetupsViewModel()
    @State private var isShowingRecentlyDeleted = false
    @FocusState private var isSearchFocused: Bool
    @ScaledMetric(relativeTo: .title2) private var bottomControlSize: CGFloat = 48

    var body: some View {
        @Bindable var viewModel = viewModel
        NavigationStack {
            ZStack {
                background
                content
            }
            .safeAreaInset(edge: .bottom) {
                bottomBar
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
        .sheet(isPresented: $viewModel.isShowingScanGuide) {
            viewModel.scanGuideDismissed()
        } content: {
            ScanGuideSheet(
                onStartScanning: { viewModel.startScanningTapped() },
                onDontShowAgain: { viewModel.dontShowAgainTapped() }
            )
            .presentationDetents([.large])
        }
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
            emptyState
        } else if viewModel.showsNoResults {
            ContentUnavailableView.search(text: viewModel.searchText)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    switch viewModel.grouping {
                    case .recent:
                        ForEach(Array(viewModel.recentSections.enumerated()), id: \.element.id) { index, section in
                            recentSection(section, isFirst: index == 0)
                        }
                    case .byClient:
                        ForEach(viewModel.clientGroups) { group in
                            clientGroupView(group)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }

    /// A month (or "Not saved") with its setups as a horizontal row of cards (Sketch R01).
    private func recentSection(_ section: SetupSection, isFirst: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(section.title, caption: isThisMonth(section) ? "This month" : nil)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(section.setups) { setup in
                        NavigationLink(value: setup) {
                            SetupCardView(setup: setup, isProminent: isFirst)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { deleteButton(for: setup) }
                    }
                }
                .padding(.horizontal)
            }
            // Clipping cut the cards' shadow into a grey band across the row.
            .scrollClipDisabled()
        }
    }

    /// A client with its setups as rows, a small month label above each month (Sketch R01b).
    private func clientGroupView(_ group: ClientGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(group.title, caption: nil)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(group.sections) { section in
                    // Drafts have no month, so their label is empty and not shown.
                    if !section.title.isEmpty {
                        Text(section.title)
                            .font(.footnote)
                            .foregroundStyle(DesignTokens.textSecondary)
                            .padding(.top, 4)
                    }
                    ForEach(section.setups) { setup in
                        NavigationLink(value: setup) {
                            SetupRowView(setup: setup)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { deleteButton(for: setup) }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func sectionHeader(_ title: String, caption: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(DesignTokens.textPrimary)
            if let caption {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.textSecondary)
            }
        }
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func isThisMonth(_ section: SetupSection) -> Bool {
        guard let date = section.setups.first?.firstSavedDate else { return false }
        return Calendar.current.isDate(date, equalTo: Date(), toGranularity: .month)
    }

    private func deleteButton(for setup: Setup) -> some View {
        Button(role: .destructive) {
            viewModel.deleteTapped(setup)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private var emptyState: some View {
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

    // MARK: - Bottom bar

    private var bottomBar: some View {
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
            TextField("Search", text: Bindable(viewModel).searchText)
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
        HStack {
            Text("Moved to Recently Deleted")
                .font(.subheadline)
                .foregroundStyle(.white)
            Spacer()
            Button("Undo") {
                withAnimation { viewModel.undoDelete() }
            }
            .font(.subheadline.bold())
            .foregroundStyle(DesignTokens.accentPrimary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: bottomControlSize)
        .background(DesignTokens.toastBackground, in: .capsule)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task(id: viewModel.lastDeleted?.id) {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation { viewModel.dismissUndo() }
        }
    }

    /// "Setup saved" after Project Details (A10-97), in the same chip as the delete toast.
    private var savedToast: some View {
        Text("Setup saved")
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: bottomControlSize, alignment: .leading)
            .background(DesignTokens.toastBackground, in: .capsule)
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
