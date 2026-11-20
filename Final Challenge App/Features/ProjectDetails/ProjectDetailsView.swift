import SwiftUI

/// Setup name, client, project and notes (Sketch R07, R07e, R07f · A10-11, A10-13, A10-93, A10-97).
/// Pushed from Review after a scan (back chevron), or presented from a saved setup to edit (Cancel).
struct ProjectDetailsView: View {
    var setup: Setup
    var isPresentedModally: Bool = false
    var onDismissToSetups: (() -> Void)?
    @State private var viewModel: ProjectDetailsViewModel
    
    // Draft state variables to prevent mutating SwiftData model until user taps Save
    @State private var draftSetupName: String = ""
    @State private var draftClient: String = ""
    @State private var draftProject: String = ""
    @State private var draftNotes: String = ""

    /// Last Save result; changing it plays the haptic.
    @State private var lastOutcome: ProjectDetailsViewModel.SaveOutcome?
    @State private var saveCount = 0

    @Environment(\.dismiss) private var dismiss
    @Environment(\.setupSavedAction) private var setupSavedAction

    private var isFormValid: Bool {
        !draftSetupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

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
            Section {
                DetailsRow("Name") {
                    TextField(
                        "Name",
                        text: $draftSetupName,
                        prompt: Text("Required")
                            .foregroundStyle(viewModel.showsNameRequired ? DesignTokens.accentText : DesignTokens.textSecondary)
                    )
                }
            } header: {
                FormSectionHeader("Setup")
            } footer: {
                // R07e
                if viewModel.showsNameRequired || (!isFormValid && draftSetupName.isEmpty) {
                    Text("Add a name to save this setup.")
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.accentText)
                }
            }
            .listRowBackground(DesignTokens.formRowBackground)

            Section(header: FormSectionHeader("Organization · Optional")) {
                DetailsRow("Client") {
                    TextField("Client", text: $draftClient, prompt: Text("None"))
                }
                DetailsRow("Project") {
                    TextField("Project", text: $draftProject, prompt: Text("None"))
                }
            }
            .listRowBackground(DesignTokens.formRowBackground)

            Section {
                TextField("Notes", text: $draftNotes, prompt: Text("Add notes"), axis: .vertical)
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
                .disabled(!isFormValid)
            }
        }
        .onAppear {
            // Populate draft state from setup model
            draftSetupName = setup.setupName
            draftClient = setup.client
            draftProject = setup.project
            draftNotes = setup.notes
        }
        .onChange(of: draftSetupName) { _, newName in
            viewModel.nameChanged(newName)
        }
        .sensoryFeedback(trigger: saveCount) { _, _ in
            lastOutcome == .saved ? .success : .error
        }
        // R07f
        .alert("Couldn’t Save Setup", isPresented: $viewModel.isSaveFailedAlertPresented) {
            Button("Cancel", role: .cancel) { }
            Button("Try Again") {
                save()
            }
            .keyboardShortcut(.defaultAction)
        } message: {
            Text("Something went wrong while saving. Try again. Your details are still here.")
        }
    }

    private func save() {
        guard isFormValid else { return }

        // Commit draft changes to actual setup model only when Save is pressed
        setup.setupName = draftSetupName
        setup.client = draftClient
        setup.project = draftProject
        setup.notes = draftNotes

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
