import SwiftUI

/// Share sheet and the templated A4 PDF (Sketch R15, R15q · A10-13).
struct ExportView: View {
    @State private var viewModel = ExportViewModel()

    var body: some View {
        Text("Export")
    }
}

#Preview {
    ExportView()
}
