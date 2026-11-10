import SwiftUI

/// Scan guide, camera permission, live scan, processing, leave alert (Sketch R02–R04x · A10-4, A10-5).
struct ScanView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ScanViewModel()
    @State private var showLoadingScreen: Bool = false
    var onDismissToSetups: (() -> Void)? = nil

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
                ReviewView(
                    isFromLoadingScreen: true,
                    viewModel: ReviewViewModel(setup: viewModel.draftSetup),
                    onDismissToSetups: {
                        showLoadingScreen = false
                        onDismissToSetups?()
                    }
                )
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel", systemImage: "chevron.left") {
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    ScanView()
}
