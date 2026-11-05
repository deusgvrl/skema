import SwiftUI

/// Saved setups, by month or by client (Sketch R01, R01b · A10-13).
struct SetupsView: View {
    @State private var viewModel = SetupsViewModel()

    var body: some View {
        Text("Setups")
    }
}

#Preview {
    SetupsView()
}
