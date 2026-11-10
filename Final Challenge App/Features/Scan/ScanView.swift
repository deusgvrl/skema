import SwiftUI

/// Scan guide, camera permission, live scan, processing, leave alert (Sketch R02–R04x · A10-4, A10-5).
struct ScanView: View {
    @State private var viewModel = ScanViewModel()
    @State private var showLoadingScreen: Bool = false

    var body: some View {
        VStack {
            Spacer()
            Button("Done Scan", systemImage: "checkmark") {
                showLoadingScreen = true
            }
            .padding(.bottom, 64)
        }
        .fullScreenCover(isPresented: $showLoadingScreen) {
            NavigationStack {
                LoadingPageView(setup: viewModel.draftSetup)
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", systemImage: "xmark") {
                    
                }
            }
        }
    }
}

#Preview {
    ScanView()
}
