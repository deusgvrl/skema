import SwiftUI

/// Setups deleted in the last 30 days, with Recover (A10-95).
struct RecentlyDeletedView: View {
    @State private var viewModel = RecentlyDeletedViewModel()
    /// How long the "Setup recovered" toast stays before it goes away on its own.
    private let recoveredToastSeconds = 3

    var body: some View {
        Group {
            if viewModel.showsEmptyState {
                ContentUnavailableView("No recently deleted setups", systemImage: "trash")
            } else {
                List(viewModel.setups) { setup in
                    row(setup)
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Recently Deleted")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.load() }
        .overlay(alignment: .bottom) {
            if viewModel.lastRecovered != nil {
                Text("Setup recovered")
                    .padding()
                    .background(.regularMaterial, in: .capsule)
                    .padding(.bottom)
            }
        }
        .task(id: viewModel.lastRecovered?.id) {
            guard viewModel.lastRecovered != nil else { return }
            try? await Task.sleep(for: .seconds(recoveredToastSeconds))
            viewModel.dismissRecovered()
        }
    }

    private func row(_ setup: Setup) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(setup.setupName.isEmpty ? "Untitled Setup" : setup.setupName)
                    .font(.headline)
                Text(viewModel.daysLeftText(for: setup))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Recover") { viewModel.recover(setup) }
                .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack { RecentlyDeletedView() }
}
