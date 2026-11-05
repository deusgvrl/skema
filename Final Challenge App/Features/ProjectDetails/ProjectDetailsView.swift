import SwiftUI

/// Setup name, client, project and notes (Sketch R07 · A10-11, A10-13).
struct ProjectDetailsView: View {
    @State private var viewModel = ProjectDetailsViewModel()

    var body: some View {
        Text("ProjectDetails")
    }
}

#Preview {
    ProjectDetailsView()
}
