import SwiftUI

/// Scan guide, camera permission, live scan, processing, leave alert (Sketch R02–R04x · A10-4, A10-5).
struct ScanView: View {
    @State private var viewModel = ScanViewModel()

    var body: some View {
        Text("Scan")
    }
}

#Preview {
    ScanView()
}
