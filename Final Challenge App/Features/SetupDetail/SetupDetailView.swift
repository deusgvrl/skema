import SwiftUI

/// One saved setup with Diagram and References tabs (Sketch R08 · A10-13).
struct SetupDetailView: View {
    @State private var viewModel = SetupDetailViewModel()

    var body: some View {
        Text("SetupDetail")
    }
}

#Preview {
    SetupDetailView()
}
