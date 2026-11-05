import SwiftUI

/// Top-down lighting diagram after the scan, and editing it (Sketch R04, R09 · A10-10, A10-17).
struct ReviewView: View {
    @State private var viewModel = ReviewViewModel()

    var body: some View {
        Text("Review")
    }
}

#Preview {
    ReviewView()
}
