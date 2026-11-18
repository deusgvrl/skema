import SwiftUI

/// Saved setups, by month or by client (Sketch R01, R01b · A10-13).
struct SetupsView: View {
    @State private var viewModel = SetupsViewModel()
    @State private var searchText = ""
    @State private var isShowingLiDARScan = false
    @ScaledMetric(relativeTo: .title2) private var newSetupButtonSize: CGFloat = 48
    /// How long the "Setup deleted" toast stays before it goes away on its own.
    private let undoToastSeconds = 5
    /// How long the "Setup saved" toast stays.
    private let savedToastSeconds = 3

    var body: some View {
        @Bindable var viewModel = viewModel
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Group setups", selection: $viewModel.grouping) {
                Text("Recent").tag(SetupsGrouping.recent)
                Text("By Client").tag(SetupsGrouping.byClient)
                }
                .pickerStyle(.segmented)
                .controlSize(.large)
                .glassEffect(.regular)
                .padding(.horizontal)
                .padding(.bottom, 8)

                if viewModel.showsEmptyState {
                    emptyState
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 120)
                    if viewModel.hasRecentlyDeleted {
                        List { recentlyDeletedRow }
                            .listStyle(.insetGrouped)
                            .scrollDisabled(true)
                            .frame(height: 100)
                    }
                } else {
                    List {
                        switch viewModel.grouping {
                        case .recent:
                            ForEach(viewModel.recentSections) { section in
                                Section(header: Text(section.title)) {
                                    ForEach(section.setups) { setup in
                                        setupRow(setup)
                                    }
                                }
                            }
                        case .byClient:
                            ForEach(viewModel.clientGroups) { group in
                                Section(header: Text(group.title)) {
                                    ForEach(group.sections) { section in
                                        // Drafts have no month, so their label is empty and not shown.
                                        if !section.title.isEmpty {
                                            Text(section.title)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        ForEach(section.setups) { setup in
                                            setupRow(setup)
                                        }
                                    }
                                }
                            }
                        }
                        if viewModel.hasRecentlyDeleted {
                            recentlyDeletedRow
                        }
                    }
                    .listStyle(.insetGrouped)
                    .navigationDestination(for: Setup.self) { selectedSetup in
                        
                        SetupDetailView(setup: selectedSetup)
                    }
                }
                Spacer(minLength: 0)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Setups")
                .toolbarTitleDisplayMode(.inlineLarge)
                .searchable(
                    text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search setups and equipment"
                )
                .overlay(alignment: .bottomTrailing) {
                    newSetupButton
            }
                .overlay(alignment: .bottom) {
                    if viewModel.lastDeleted != nil {
                        undoToast
                    } else if viewModel.showsSavedToast {
                        ToastBar(message: "Setup saved")
                            // Sits above the + button so the two never overlap.
                            .padding(.bottom, newSetupButtonSize + 32)
                    }
                }
                .task(id: viewModel.showsSavedToast) {
                    guard viewModel.showsSavedToast else { return }
                    try? await Task.sleep(for: .seconds(savedToastSeconds))
                    viewModel.dismissSavedToast()
                }
                .task(id: viewModel.lastDeleted?.id) {
                    guard viewModel.lastDeleted != nil else { return }
                    try? await Task.sleep(for: .seconds(undoToastSeconds))
                    viewModel.dismissUndo()
                }
                .alert(
                    "Delete This Setup?",
                    isPresented: Binding(
                        get: { viewModel.setupPendingDelete != nil },
                        set: { isPresented in if !isPresented { viewModel.cancelDelete() } }
                    ),
                    presenting: viewModel.setupPendingDelete
                ) { _ in
                    Button("Delete", role: .destructive) { viewModel.confirmDelete() }
                    Button("Cancel", role: .cancel) { viewModel.cancelDelete() }
                } message: { setup in
                    Text(viewModel.deleteMessage(for: setup))
                }
            .onAppear {
                viewModel.fetchSetups()
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
            .presentationDetents([.medium, .large])
        }
        
    }
    private func setupRow(_ setup: Setup) -> some View {
        NavigationLink(value: setup) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(setup.setupName) • \(setup.nodes.count) equipment")
                    .font(.headline)

                let subtitle = [setup.client, setup.project].filter { !$0.isEmpty }.joined(separator: " › ")
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                viewModel.deleteTapped(setup)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var recentlyDeletedRow: some View {
        NavigationLink {
            RecentlyDeletedView()
        } label: {
            Label("Recently Deleted", systemImage: "trash")
        }
    }

    private var undoToast: some View {
        ToastBar(message: "Setup deleted", actionTitle: "Undo") { viewModel.undoDelete() }
            // Sits above the + button so the two never overlap.
            .padding(.bottom, newSetupButtonSize + 32)
    }

    private var emptyState: some View {
            ContentUnavailableView {
                Label {
                    Text("No Setups Yet")
                        .font(.title2.bold())
                } icon: {
                    Image("empty_state_icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .foregroundStyle(.secondary)
                        .frame(width: 80, height: 80)
                        .background(Color(.tertiarySystemFill), in: .circle)

                }
            } description: {
                Text("""
                    Scan your first lighting setup. The diagram, \
                    equipment and references are saved here, so you can rebuild it next time.
                    """)
                .font(.subheadline)
            }
        }
    private var newSetupButton: some View {
            Button {
                viewModel.newSetupTapped()
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: newSetupButtonSize, height: newSetupButtonSize)
                    .background(Color.accentColor, in: .circle)
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

            }
            .accessibilityLabel("New Setup")
            .contextMenu {
                Button("LiDAR tap scan (test)") { isShowingLiDARScan = true }
            }
            .padding(16)
    }
}

enum SetupsGrouping {
    case recent
    case byClient
}

#Preview {
    SetupsView()
}
