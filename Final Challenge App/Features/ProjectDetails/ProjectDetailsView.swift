import SwiftUI

/// Setup name, client, project and notes (Sketch R07 · A10-11, A10-13).
import SwiftUI

/// Setup name, client, project and notes (Sketch R07 · A10-11, A10-13).
struct ProjectDetailsView: View {
    @Bindable var setup: Setup
    var isPresentedModally: Bool = false
    var onDismissToSetups: (() -> Void)? = nil
    
    @Environment(\.dismiss) private var dismiss
    
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
                Button("Done", systemImage: "checkmark") {
                    // ✅ Save context once when user finishes
                    StorageController.shared.save()
                    
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
    )
}
