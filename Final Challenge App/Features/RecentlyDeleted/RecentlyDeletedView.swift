import SwiftUI

/// Setups deleted in the last 30 days, with Recover (A10-95, Sketch R17 / Light · R17).
struct RecentlyDeletedView: View {
    @State private var viewModel = RecentlyDeletedViewModel()
    /// How long the "Setup recovered" toast stays before it goes away on its own.
    private let recoveredToastSeconds = 3

    private var subtitle: String {
        viewModel.setups.count == 1 ? "1 setup" : "\(viewModel.setups.count) setups"
    }

    var body: some View {
        ZStack {
            DesignTokens.pageBackground
                .ignoresSafeArea()

            if viewModel.showsEmptyState {
                ContentUnavailableView(
                    "No Recently Deleted Setups",
                    systemImage: "trash",
                    description: Text("Deleted setups stay here for \(RecentlyDeleted.keepDays) days.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.setups) { setup in
                            row(setup)
                        }
                        Text("Setups stay here for \(RecentlyDeleted.keepDays) days, then they’re permanently deleted.")
                            .font(.footnote)
                            .foregroundStyle(DesignTokens.textSecondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Recently Deleted")
        .navigationSubtitle(subtitle)
        .toolbarTitleDisplayMode(.inline)
        .onAppear { viewModel.load() }
        .overlay(alignment: .bottom) {
            if viewModel.lastRecovered != nil {
                ToastBar(systemImage: "checkmark", message: "Setup recovered")
                    .padding(.bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task(id: viewModel.lastRecovered?.id) {
            guard viewModel.lastRecovered != nil else { return }
            try? await Task.sleep(for: .seconds(recoveredToastSeconds))
            viewModel.dismissRecovered()
        }
    }

    private func row(_ setup: Setup) -> some View {
        let details = [setup.client, setup.project].filter { !$0.isEmpty }.joined(separator: " · ")
        let name = setup.setupName.isEmpty ? "Untitled Setup" : setup.setupName

        return HStack(spacing: 12) {
            SetupThumbnail(setup: setup)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)
                    .foregroundStyle(DesignTokens.textPrimary)
                    .lineLimit(1)
                if !details.isEmpty {
                    Text(details)
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .lineLimit(1)
                }
                Text(viewModel.daysLeftText(for: setup))
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
            }

            Spacer(minLength: 0)

            Button("Recover") {
                withAnimation { viewModel.recover(setup) }
            }
            .font(.subheadline.bold())
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(DesignTokens.accentPrimary)
            .accessibilityLabel("Recover \(name)")
        }
        .padding(12)
        .glassCard(cornerRadius: 24)
    }
}

#Preview {
    NavigationStack { RecentlyDeletedView() }
}
