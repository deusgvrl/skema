import SwiftUI

/// Setup name, client, project and notes (Sketch R07 · A10-11, A10-13).
struct ProjectDetailsView: View {
    var setup: Setup
    var isPresentedModally: Bool = false
    var onDismissToSetups: (() -> Void)? = nil
    var viewModel: ProjectDetailsViewModel = ProjectDetailsViewModel()
    
    @Environment(\.dismiss) private var dismiss
    
    // 1. Temporary draft state variables
    @State private var draftSetupName: String = ""
    @State private var draftClient: String = ""
    @State private var draftProject: String = ""
    @State private var draftNotes: String = ""
    
    private var isFormValid: Bool {
        !draftSetupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        Form {
            Section(header: Text("Setup")) {
                HStack {
                    Text("Name")
                    Spacer()
                    TextField("Required", text: $draftSetupName)
                        .multilineTextAlignment(.trailing)
                }
            }
            
            Section(header: Text("Organization - Optional")) {
                HStack {
                    Text("Client")
                    Spacer()
                    TextField("None", text: $draftClient)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Project")
                    Spacer()
                    TextField("None", text: $draftProject)
                        .multilineTextAlignment(.trailing)
                }
            }
            
            Section(
                header: Text("Notes"),
                footer: Text("Camera settings sync with each camera in equipment. You can add reference photos from the shoot later in References.")
            ) {
                TextEditor(text: $draftNotes)
                    .frame(minHeight: 100)
            }
        }
        .navigationTitle("Project Details")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isPresentedModally)
        .onAppear {
            // 2. Initialize draft values from original setup object
            draftSetupName = setup.setupName
            draftClient = setup.client
            draftProject = setup.project
            draftNotes = setup.notes
        }
        .toolbar {
            if isPresentedModally {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        // Dismissing without applying draft leaves the original setup untouched
                        dismiss()
                    }
                }
            }
            
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", systemImage: "checkmark") {
                    // 3. Commit draft changes only when "Done" is pressed
                    setup.setupName = draftSetupName
                    setup.client = draftClient
                    setup.project = draftProject
                    setup.notes = draftNotes
                    
                    viewModel.handleClose()
                    
                    if let onDismissToSetups {
                        onDismissToSetups()
                    } else {
                        dismiss()
                    }
                }
                .fontWeight(.semibold)
                .disabled(!isFormValid)
            }
        }
    }
}
