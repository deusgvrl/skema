import SwiftUI

/// Saved setups, by month or by client (Sketch R01, R01b, R01f, R01q, R01v, R01z · A10-13).
struct SetupsView: View {
    @State private var viewModel = SetupsViewModel()
    @State private var isShowingLiDARScan = false
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
            .navigationDestination(isPresented: $isShowingLiDARScan) {
                LiDARScanView(onDismissToSetups: {
                    isShowingLiDARScan = false
                })
            }
            .onAppear {
                viewModel.fetchSetups()
            }
        }
        .sheet(isPresented: $viewModel.isShowingScanGuide) {
            viewModel.scanGuideDismissed()
        } content: {
            ScanGuideSheet(
                onStartScanning: { viewModel.startScanningTapped() },
                onDontShowAgain: { viewModel.dontShowAgainTapped() }
            )
            .presentationDetents([.medium, .large])
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
                    ForEach(Array(viewModel.sections.enumerated()), id: \.element.id) { index, section in
                        sectionView(section, isFirst: index == 0)
                    }
                }
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }

    private func sectionView(_ section: SetupSection, isFirst: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .font(.title2.bold())
                    .foregroundStyle(DesignTokens.textPrimary)
                if let caption = section.caption {
                    Text(caption)
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.textSecondary)
                }
            }
            .padding(.horizontal)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            switch viewModel.grouping {
            case .recent:
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
            case .byClient:
                VStack(spacing: 8) {
                    ForEach(section.setups) { setup in
                        NavigationLink(value: setup) {
                            SetupRowView(setup: setup)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { deleteButton(for: setup) }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func deleteButton(for setup: Setup) -> some View {
        Button(role: .destructive) {
            withAnimation { viewModel.deleteSetup(setup) }
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
                    .frame(width: 30, height: 40)
                    .frame(width: 80, height: 80)
                    .glassEffect(.regular, in: .circle)
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
            Picker("Group By", selection: Bindable(viewModel).grouping) {
                Text("Recent").tag(SetupsGrouping.recent)
                Text("By Client").tag(SetupsGrouping.byClient)
            }
            .pickerStyle(.inline)
        } label: {
            Label("Group By", systemImage: "line.3.horizontal.decrease")
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if viewModel.lastDeleted != nil {
                deletedToast
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
        .contextMenu {
            Button("LiDAR tap scan (test)") { isShowingLiDARScan = true }
        }
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
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation { viewModel.lastDeleted = nil }
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
