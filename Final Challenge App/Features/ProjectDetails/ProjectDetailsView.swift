import SwiftUI

/// Setup name, client, project and notes (Sketch R07 · A10-11, A10-13).
import SwiftUI

/// Setup name, client, project and notes (Sketch R07 · A10-11, A10-13).
struct ProjectDetailsView: View {
    @Bindable var setup: Setup
    var isPresentedModally: Bool = false
    var onDismissToSetups: (() -> Void)? = nil
    @State private var viewModel: ProjectDetailsViewModel
    /// Last Save result; changing it plays the haptic.
    @State private var lastOutcome: ProjectDetailsViewModel.SaveOutcome?
    @State private var saveCount = 0

    @Environment(\.dismiss) private var dismiss
    @Environment(\.setupSavedAction) private var setupSavedAction

    init(setup: Setup,
         isPresentedModally: Bool = false,
         onDismissToSetups: (() -> Void)? = nil,
         viewModel: ProjectDetailsViewModel = ProjectDetailsViewModel()) {
        self.setup = setup
        self.isPresentedModally = isPresentedModally
        self.onDismissToSetups = onDismissToSetups
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        Form {
            Section(
                header: Text("Setup"),
                footer: viewModel.showsNameRequired
                    ? Text("Add a name to save this setup.").foregroundStyle(.red)
                    : nil
            ) {
                HStack {
                    Text("Name")
                    Spacer()
                    TextField("Required", text: $setup.setupName)
                        .multilineTextAlignment(.trailing)
                }
            }
            
            Section(header: Text("Organization - Optional")) {
                HStack {
                    Text("Client")
                    Spacer()
                    TextField("None", text: $setup.client)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Project")
                    Spacer()
                    TextField("None", text: $setup.project)
                        .multilineTextAlignment(.trailing)
                }
            }
            
            Section(
                header: Text("Notes"),
                footer: Text("Camera settings sync with each camera in equipment. You can add reference photos from the shoot later in References.")
            ) {
                TextEditor(text: $setup.notes)
                    .frame(minHeight: 100)
            }
        }
        .navigationTitle("Project Details")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isPresentedModally)
        .toolbar {
            if isPresentedModally {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", systemImage: "checkmark") {
                    let outcome = viewModel.saveTapped(for: setup)
                    lastOutcome = outcome
                    saveCount += 1
                    guard outcome == .saved else { return }
                    setupSavedAction?()
                    if let onDismissToSetups {
                        onDismissToSetups()
                    } else {
                        dismiss()
                    }
                }
                .fontWeight(.semibold)
            }
        }
        .onChange(of: setup.setupName) { _, newName in
            viewModel.nameChanged(newName)
        }
        .sensoryFeedback(trigger: saveCount) { _, _ in
            lastOutcome == .saved ? .success : .error
        }
        .alert("Save Failed", isPresented: $viewModel.isSaveFailedAlertPresented) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your setup could not be saved. Please try again.")
        }
    }
}

#Preview {
    ProjectDetailsView(
        setup: Setup(),
    )
}
