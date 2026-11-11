import SwiftUI

/// Saved setups, by month or by client (Sketch R01, R01b · A10-13).
struct SetupsView: View {
    @State private var viewModel = SetupsViewModel()
    @State private var searchText = ""
    @State private var grouping = SetupsGrouping.recent
    @ScaledMetric(relativeTo: .title2) private var newSetupButtonSize: CGFloat = 48

    var body: some View {
        @Bindable var viewModel = viewModel
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Group setups", selection: $grouping) {
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
                } else {
                    List(viewModel.setups) { setup in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(setup.setupName)
                                .font(.headline)
                            if !setup.client.isEmpty || !setup.project.isEmpty {
                                Text("\(setup.client) • \(setup.project)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
                Spacer(minLength: 0)
            }
            .navigationDestination(isPresented: $viewModel.isShowingScan) {
                ScanView(onDismissToSetups: {
                    viewModel.isShowingScan = false
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
        .onAppear {
            viewModel.fetchSetups()
        }
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
