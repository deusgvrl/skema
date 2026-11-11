import SwiftUI

/// Setup name, client, project and notes (Sketch R07 · A10-11, A10-13).
struct ProjectDetailsView: View {
    @State private var setup: Setup
    var isPresentedModally: Bool = false
    var onSave: (Setup) -> Void
    var onDismissToSetups: (() -> Void)? = nil
    
    @Environment(\.dismiss) private var dismiss
    
    init(
        setup: Setup,
        isPresentedModally: Bool = false,
        onSave: @escaping (Setup) -> Void,
        onDismissToSetups: (() -> Void)? = nil
    ) {
        self._setup = State(initialValue: setup)
        self.isPresentedModally = isPresentedModally
        self.onSave = onSave
        self.onDismissToSetups = onDismissToSetups
    }
    
    private var isFormValid: Bool {
        !setup.setupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        Form {
            Section(header: Text("Setup")) {
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
                Button("Done") {
                    // Pass the edited setup back via the closure
                    onSave(setup)
                    
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

#Preview {
    ProjectDetailsView(
        setup: Setup(),
        onSave: { _ in }
    )
}
