import SwiftUI

struct EquipmentFormView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var formViewModel: EquipmentFormViewModel

    @Binding var selectedDetent: PresentationDetent

    let viewModel: ReviewViewModel
    let editingNodeId: UUID?
    let undoManager: UndoManager?
    var isReadOnly: Bool = false

    // State management for dirty tracking and confirmation alerts
    @State private var isDeleteAlert: Bool = false
    @State private var isDiscardAlertPresented: Bool = false
    @State private var isDirty: Bool = false
    @State private var isSwitchingNode: Bool = false

    private var editingTitle: String? {
        viewModel.nodes.first { $0.id == editingNodeId }?.displayName
    }

    init(
        viewModel: ReviewViewModel,
        editingNodeId: UUID?,
        undoManager: UndoManager?,
        isReadOnly: Bool = false,
        selectedDetent: Binding<PresentationDetent> = .constant(.height(76))
    ) {
        self.viewModel = viewModel
        self.editingNodeId = editingNodeId
        self.undoManager = undoManager
        self.isReadOnly = isReadOnly
        self._selectedDetent = selectedDetent
        self._formViewModel = State(initialValue: EquipmentFormViewModel(
            editingNodeId: editingNodeId,
            reviewViewModel: viewModel
        ))
    }

    var body: some View {
        @Bindable var formViewModel = formViewModel

        NavigationStack {
            Form {
                equipmentSection
                categorySpecificSettingsSection
                positionAndDirectionSection
                notesAndAccessoriesSection
            }
            .foregroundStyle(DesignTokens.textPrimary)
            .scrollContentBackground(.hidden)
            .background(selectedDetent == .large ? DesignTokens.sheetBackground : Color.clear)
            .navigationTitle(formViewModel.isEditing ? (editingTitle ?? "Equipment Details") : "Add Equipment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isReadOnly ? "Close" : "Cancel", systemImage: "xmark") {
                        if !isReadOnly && isDirty {
                            isDiscardAlertPresented = true
                        } else {
                            dismiss()
                        }
                    }
                }

                if !isReadOnly {
                    ToolbarItem(placement: .confirmationAction) {
                        if !formViewModel.isEditing || selectedDetent == .large || selectedDetent == .medium {
                            // Fullscreen / Expanded Mode: Show Checkmark to Save
                            Button("Done", systemImage: "checkmark") {
                                formViewModel.saveNode(undoManager: undoManager) {
                                    dismiss()
                                }
                            }
                            .buttonStyle(.glassProminent)
                            .tint(DesignTokens.accentPrimary)
                            .disabled(!formViewModel.isFormValid)
                        } else {
                            // Compact / Medium Mode: Show Pencil to Expand Fullscreen
                            Button("Edit Details", systemImage: "pencil") {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    selectedDetent = .large
                                }
                            }
                            .buttonStyle(.glassProminent)
                            .tint(DesignTokens.accentPrimary)
                        }
                    }
                }
            }
        }
        // Track form edits to update dirty status
        .onChange(of: formViewModel.category) { _, _ in if !isSwitchingNode { isDirty = true } }
        .onChange(of: formViewModel.name) { _, _ in if !isSwitchingNode { isDirty = true } }
        .onChange(of: formViewModel.role) { _, _ in if !isSwitchingNode { isDirty = true } }
        .onChange(of: formViewModel.distance) { _, _ in if !isSwitchingNode { isDirty = true } }
        .onChange(of: formViewModel.horizontalAim) { _, _ in if !isSwitchingNode { isDirty = true } }
        .onChange(of: formViewModel.height) { _, _ in if !isSwitchingNode { isDirty = true } }
        .onChange(of: formViewModel.tilt) { _, _ in if !isSwitchingNode { isDirty = true } }
        .onChange(of: formViewModel.colorTemp) { _, _ in if !isSwitchingNode { isDirty = true } }
        .onChange(of: formViewModel.whiteBalance) { _, _ in if !isSwitchingNode { isDirty = true } }
        .onChange(of: formViewModel.power) { _, _ in if !isSwitchingNode { isDirty = true } }
        .onChange(of: formViewModel.accessories) { _, _ in if !isSwitchingNode { isDirty = true } }
        .onChange(of: formViewModel.notes) { _, _ in if !isSwitchingNode { isDirty = true } }
        .onAppear {
            if editingNodeId != nil {
                selectedDetent = .height(76)
            }
        }
        .onChange(of: editingNodeId) { _, newId in
            isSwitchingNode = true
            formViewModel.switchToNode(id: newId)
            isDirty = false
            withAnimation(.easeInOut(duration: 0.25)) {
                selectedDetent = .height(76)
            }
            DispatchQueue.main.async {
                isDirty = false
                isSwitchingNode = false
            }
        }

        // Unsaved changes confirmation alert
        .alert("Discard Unsaved Changes?", isPresented: $isDiscardAlertPresented) {
            Button("Keep Editing", role: .cancel) { }
            Button("Discard", role: .destructive) { dismiss() }
        } message: {
            Text("You have unsaved changes. Are you sure you want to discard them?")
        }

        // Delete confirmation alert
        .alert("Delete Equipment", isPresented: $isDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                formViewModel.deleteNode(undoManager: undoManager) {
                    dismiss()
                }
            }
        } message: {
            Text("Are you sure you want to remove this equipment?")
        }
    }
}

// MARK: - Form Sections
private extension EquipmentFormView {
    @ViewBuilder
    var equipmentSection: some View {
        @Bindable var formViewModel = formViewModel

        Section(header: FormSectionHeader("Equipment")) {
            Picker("Category", selection: $formViewModel.category) {
                ForEach(EquipmentCategory.allCases) { cat in
                    Text(cat.rawValue).tag(cat)
                }
            }
            .pickerStyle(.menu)
            .tint(.primary)
            .disabled(isReadOnly)

            HStack {
                Text("Name")
                Spacer()
                TextField("Required", text: $formViewModel.name)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .disabled(isReadOnly)
            }

            if formViewModel.category != .accessory {
                HStack {
                    Text("Role / label")
                    Spacer()
                    let rolePrompt = formViewModel.category == .light
                        ? "e.g. Accent light"
                        : "e.g. Second camera"
                    TextField(rolePrompt, text: $formViewModel.role)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .disabled(isReadOnly)
                }
            }
        }
        .listRowBackground(DesignTokens.formRowBackground)
    }

    @ViewBuilder
    var categorySpecificSettingsSection: some View {
        @Bindable var formViewModel = formViewModel

        if formViewModel.category == .light {
            Section(header: FormSectionHeader("Light Settings")) {
                HStack {
                    Text("Power")
                    Spacer()
                    TextField("1/16", text: $formViewModel.power)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .disabled(isReadOnly)
                }
                HStack {
                    Text("Color temperature")
                    Spacer()
                    TextField("5600", text: $formViewModel.colorTemp)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .keyboardType(.numberPad)
                        .disabled(isReadOnly)
                    Text("K")
                        .foregroundStyle(DesignTokens.textSecondary)
                }
            }
            .listRowBackground(DesignTokens.formRowBackground)
        }

        if formViewModel.category == .camera {
            Section(header: FormSectionHeader("Lens")) {
                HStack {
                    Text("Lens")
                    Spacer()
                    TextField("50", text: $formViewModel.lens)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .disabled(isReadOnly)
                    Text("mm")
                        .foregroundStyle(DesignTokens.textSecondary)
                }
            }
            .listRowBackground(DesignTokens.formRowBackground)

            Section(header: FormSectionHeader("Camera Settings")) {
                HStack {
                    Text("ISO")
                    Spacer()
                    TextField("100", text: $formViewModel.iso)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .keyboardType(.numberPad)
                        .disabled(isReadOnly)
                }
                HStack {
                    Text("Aperture")
                    Spacer()
                    TextField("f/2.8", text: $formViewModel.aperture)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .disabled(isReadOnly)
                }
                HStack {
                    Text("Shutter speed")
                    Spacer()
                    TextField("1/200", text: $formViewModel.shutterSpeed)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .disabled(isReadOnly)
                }
                HStack {
                    Text("White balance")
                    Spacer()
                    TextField("5600", text: $formViewModel.whiteBalance)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .keyboardType(.numberPad)
                        .disabled(isReadOnly)
                    Text("K")
                        .foregroundStyle(DesignTokens.textSecondary)
                }
            }
            .listRowBackground(DesignTokens.formRowBackground)
        }
    }

    @ViewBuilder
    var positionAndDirectionSection: some View {
        @Bindable var formViewModel = formViewModel

        if formViewModel.category != .accessory {
            Section(
                header: FormSectionHeader("Position & Direction"),
                footer: Text(isReadOnly ? "Viewing equipment details from read-only mode." : """
                    It's placed next to the subject for now. You can drag it to the right spot \
                    on the diagram, or change these values anytime later.
                    """)
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.textSecondary)
            ) {
                HStack {
                    Text("Height")
                    Spacer()
                    TextField("0.0", text: $formViewModel.height)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .keyboardType(.decimalPad)
                        .disabled(isReadOnly)
                    Text("m")
                        .foregroundStyle(DesignTokens.textSecondary)
                }
                HStack {
                    Text("Tilt")
                    Spacer()
                    TextField("0", text: $formViewModel.tilt)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .keyboardType(.numberPad)
                        .disabled(isReadOnly)
                    Text("°")
                        .foregroundStyle(DesignTokens.textSecondary)
                }

                if formViewModel.category == .light {
                    HStack {
                        Text("Horizontal aim")
                        Spacer()
                        TextField("0", text: $formViewModel.horizontalAim)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(DesignTokens.textSecondary)
                            .keyboardType(.numberPad)
                            .disabled(isReadOnly)
                        Text("°")
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                }

                HStack {
                    Text("Distance to subject")
                        .lineLimit(1)
                        .layoutPriority(1)
                    Spacer()
                    TextField("0.0", text: $formViewModel.distance)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .keyboardType(.decimalPad)
                        .disabled(isReadOnly)
                    Text("m")
                        .foregroundStyle(DesignTokens.textSecondary)
                }
            }
            .listRowBackground(DesignTokens.formRowBackground)
        }
    }

    @ViewBuilder
    var notesAndAccessoriesSection: some View {
        @Bindable var formViewModel = formViewModel

        if formViewModel.category == .accessory {
            Section(header: FormSectionHeader("Notes")) {
                TextField("Add notes", text: $formViewModel.notes, axis: .vertical)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineLimit(4...8)
                    .disabled(isReadOnly)
            }
            .listRowBackground(DesignTokens.formRowBackground)
        } else {
            Section(header: FormSectionHeader("Accessories")) {
                TextField("Add accessories", text: $formViewModel.accessories, axis: .vertical)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineLimit(4...8)
                    .disabled(isReadOnly)
            }
            .listRowBackground(DesignTokens.formRowBackground)
        }
    }
}
