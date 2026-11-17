import SwiftUI

/// Setup name, client, project and notes (Sketch R07, R07e, R07f · A10-11, A10-13).
/// Pushed from Review after a scan (back chevron), or presented from a saved setup to edit (X).
struct ProjectDetailsView: View {
    let setup: Setup
    var isPresentedModally: Bool = false
    var onDismissToSetups: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ProjectDetailsViewModel
    @State private var didSave = false
    @State private var showsSaveFailure = false

    init(setup: Setup, isPresentedModally: Bool = false, onDismissToSetups: (() -> Void)? = nil) {
        self.setup = setup
        self.isPresentedModally = isPresentedModally
        self.onDismissToSetups = onDismissToSetups
        _viewModel = State(initialValue: ProjectDetailsViewModel(setup: setup))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        Form {
            Section {
                DetailsRow("Name") {
                    TextField(
                        "Name",
                        text: $viewModel.name,
                        prompt: Text("Required")
                            .foregroundStyle(viewModel.showsNameError ? DesignTokens.accentText : DesignTokens.textSecondary)
                    )
                }
            } header: {
                FormSectionHeader("Setup")
            } footer: {
                if viewModel.showsNameError {
                    Text("Add a name to save this setup.")
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.accentText)
                }
            }
            .listRowBackground(DesignTokens.formRowBackground)

            Section(header: FormSectionHeader("Organization · Optional")) {
                DetailsRow("Client") {
                    TextField("Client", text: $viewModel.client, prompt: Text("None"))
                }
                DetailsRow("Project") {
                    TextField("Project", text: $viewModel.project, prompt: Text("None"))
                }
            }
            .listRowBackground(DesignTokens.formRowBackground)

            Section {
                TextField("Notes", text: $viewModel.notes, prompt: Text("Add notes"), axis: .vertical)
                    .lineLimit(4...10)
                    .foregroundStyle(DesignTokens.textPrimary)
            } header: {
                FormSectionHeader("Notes")
            } footer: {
                Text("""
                    Camera settings live with each camera in Equipment. \
                    You can add reference photos from the shoot later in References.
                    """)
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            .listRowBackground(DesignTokens.formRowBackground)
        }
        .scrollContentBackground(.hidden)
        .background(DesignTokens.pageBackground.ignoresSafeArea())
        .navigationTitle("Project Details")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isPresentedModally)
        .toolbar {
            if isPresentedModally {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save", systemImage: "checkmark") {
                    save()
                }
                .buttonStyle(.glassProminent)
                .tint(DesignTokens.accentPrimary)
                .disabled(!viewModel.canSave)
            }
        }
        // R07f
        .alert("Couldn’t Save Setup", isPresented: $showsSaveFailure) {
            Button("Cancel", role: .cancel) { }
            Button("Try Again") {
                save()
            }
            .keyboardShortcut(.defaultAction)
        } message: {
            Text(viewModel.saveFailure ?? "")
        }
        .onDisappear {
            // Back to the diagram keeps what was typed; Cancel on the modal does not.
            if !isPresentedModally && !didSave {
                viewModel.applyWithoutSaving()
            }
        }
    }

    private func save() {
        guard viewModel.save() else {
            showsSaveFailure = true
            return
        }
        didSave = true
        if let onDismissToSetups {
            onDismissToSetups()
        } else {
            dismiss()
        }
    }
}

/// "Name ……… value" row: label left, grey editable value right (Sketch R07).
private struct DetailsRow<Field: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let field: () -> Field

    init(_ title: LocalizedStringKey, @ViewBuilder field: @escaping () -> Field) {
        self.title = title
        self.field = field
    }

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
                .foregroundStyle(DesignTokens.textPrimary)
            field()
                .multilineTextAlignment(.trailing)
                .foregroundStyle(DesignTokens.textSecondary)
        }
    }
}

#Preview {
    NavigationStack {
        ProjectDetailsView(setup: Setup(setupName: "Skincare / soft daylight", client: "Aesop"))
    }
}
