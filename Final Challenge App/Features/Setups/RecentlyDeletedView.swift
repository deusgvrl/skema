import SwiftUI

/// Setups deleted in the last 30 days, with Recover (Sketch R17 / Light · R17).
struct RecentlyDeletedView: View {
    @State private var viewModel = RecentlyDeletedViewModel()

    private var subtitle: String {
        viewModel.deletedSetups.count == 1 ? "1 setup" : "\(viewModel.deletedSetups.count) setups"
    }

    var body: some View {
        ZStack {
            DesignTokens.pageBackground
                .ignoresSafeArea()

            if viewModel.deletedSetups.isEmpty {
                ContentUnavailableView(
                    "No Recently Deleted Setups",
                    systemImage: "trash",
                    description: Text("Deleted setups stay here for 30 days.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.deletedSetups) { setup in
                            row(for: setup)
                        }
                        Text("Setups stay here for 30 days, then they’re permanently deleted.")
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
        .onAppear {
            viewModel.fetch()
        }
    }

    private func row(for setup: Setup) -> some View {
        let details = [setup.client, setup.project].filter { !$0.isEmpty }.joined(separator: " › ")
        let daysLeft = viewModel.daysLeft(for: setup)

        return HStack(spacing: 12) {
            SetupThumbnail(setup: setup)

            VStack(alignment: .leading, spacing: 2) {
                Text(setup.setupName)
                    .font(.headline)
                    .foregroundStyle(DesignTokens.textPrimary)
                    .lineLimit(1)
                if !details.isEmpty {
                    Text(details)
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .lineLimit(1)
                }
                Text(daysLeft == 1 ? "1 day left" : "\(daysLeft) days left")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
            }

            Spacer(minLength: 0)

            Button("Recover") {
                withAnimation { viewModel.restore(setup) }
            }
            .font(.subheadline.bold())
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(DesignTokens.accentPrimary)
            .accessibilityLabel("Recover \(setup.setupName)")
        }
        .padding(12)
        .glassCard(cornerRadius: 24)
    }
}

#Preview {
    NavigationStack {
        RecentlyDeletedView()
    }
}
