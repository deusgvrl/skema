import SwiftUI

struct EquipmentFormView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var formViewModel: EquipmentFormViewModel

    @Binding var selectedDetent: PresentationDetent

    let viewModel: ReviewViewModel
    let editingNodeId: UUID?
    let undoManager: UndoManager?
    var isReadOnly: Bool = false

    @State private var isDiscardAlertPresented: Bool = false
    @State private var isDirty: Bool = false
    @State private var isSwitchingNode: Bool = false

    private var editingNode: Equipment? {
        viewModel.nodes.first { $0.id == editingNodeId }
    }

    private var editingTitle: String {
        let name = editingNode?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Equipment" : name
    }

    private var editingRole: String {
        editingNode?.role.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if formViewModel.isEditing && selectedDetent == .height(76) {
                        VStack(spacing: 2) {
                            Text(editingTitle)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(DesignTokens.textPrimary)
                                .lineLimit(1)

                            if !editingRole.isEmpty {
                                Text(editingRole)
                                    .font(.subheadline)
                                    .foregroundStyle(DesignTokens.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                    } else {
                        Text(formViewModel.isEditing ? editingTitle : "Add Equipment")
                            .font(.headline)
                            .foregroundStyle(DesignTokens.textPrimary)
                    }
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button(isReadOnly ? "Close" : "Cancel", systemImage: "xmark") {
                        if !isReadOnly && isDirty {
                            isDiscardAlertPresented = true
                        } else {
                            dismiss()
                        }
                    }
                    .confirmationDialog(
                        formViewModel.isEditing
                            ? "Are you sure you want to discard your changes?"
                            : "Are you sure you want to discard this new equipment?",
                        isPresented: $isDiscardAlertPresented,
                        titleVisibility: .visible
                    ) {
                        Button("Discard Changes", role: .destructive) {
                            formViewModel.loadData()
                            isDirty = false
                            dismiss()
                        }
                    }
                }

                if !isReadOnly {
                    ToolbarItem(placement: .confirmationAction) {
                        Group {
                            if !formViewModel.isEditing || selectedDetent == .large || selectedDetent == .medium {
                                Button("Done", systemImage: "checkmark") {
                                    formViewModel.saveNode(undoManager: undoManager) {
                                        dismiss()
                                    }
                                }
                            } else {
                                Button("Edit Details", systemImage: "checkmark") {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        selectedDetent = .large
                                    }
                                }
                            }
                        }
                        .buttonStyle(.glassProminent)
                        .tint(DesignTokens.accentPrimary)
                        .disabled(!formViewModel.isFormValid || (formViewModel.isEditing && !isDirty))
                    }
                }
            }
        }
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
            formViewModel.loadData()
            isDirty = false
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
    }

    private func tiltOptions(current: Int) -> [Int] {
        var steps = Array(stride(from: 90, through: -90, by: -5))
        if !steps.contains(current) {
            steps.append(current)
            steps.sort(by: >)
        }
        return steps
    }
}

private extension EquipmentFormView {
    @ViewBuilder
    var equipmentSection: some View {
        @Bindable var formViewModel = formViewModel

        Section(header: FormSectionHeader("Equipment")) {
            Picker("Category", selection: $formViewModel.category) {
                ForEach(EquipmentCategory.allCases) { cat in
                    Text(cat.title).tag(cat)
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
                    .foregroundStyle(DesignTokens.textPrimary)
                    .disabled(isReadOnly)
            }

            if formViewModel.category != .accessory {
                HStack {
                    Text("Role")
                    Spacer()
                    let rolePrompt = formViewModel.category == .light
                        ? "e.g. Key light"
                        : "e.g. Second camera"
                    TextField(rolePrompt, text: $formViewModel.role)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(DesignTokens.textPrimary)
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
                    TextField("e.g. 1/16", text: $formViewModel.power)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(DesignTokens.textPrimary)
                        .disabled(isReadOnly)
                }
                HStack {
                    Text("Color temperature")
                    Spacer()
                    TextField("e.g. 5600", text: $formViewModel.colorTemp)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(DesignTokens.textPrimary)
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
                    Text("Focal length")
                    Spacer()
                    TextField("e.g. 50", text: $formViewModel.lens)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(DesignTokens.textPrimary)
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
                    TextField("e.g. 100", text: $formViewModel.iso)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(DesignTokens.textPrimary)
                        .keyboardType(.numberPad)
                        .disabled(isReadOnly)
                }
                HStack {
                    Text("Aperture")
                    Spacer()
                    TextField("e.g. f/2.8", text: $formViewModel.aperture)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(DesignTokens.textPrimary)
                        .disabled(isReadOnly)
                }
                HStack {
                    Text("Shutter speed")
                    Spacer()
                    TextField("e.g. 1/200", text: $formViewModel.shutterSpeed)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(DesignTokens.textPrimary)
                        .disabled(isReadOnly)
                }
                HStack {
                    Text("White balance")
                    Spacer()
                    TextField("e.g. 5600", text: $formViewModel.whiteBalance)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(DesignTokens.textPrimary)
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
            Section {
                HStack {
                    Text("Height")
                    Spacer()
                    TextField("e.g. 1.8", text: $formViewModel.height)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(DesignTokens.textPrimary)
                        .keyboardType(.decimalPad)
                        .disabled(isReadOnly)
                    Text("m")
                        .foregroundStyle(DesignTokens.textSecondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Vertical tilt")
                        Spacer()
                        Text("\(Int(formViewModel.tilt) ?? 0)°")
                            .foregroundStyle(DesignTokens.textSecondary)
                    }

                    if !isReadOnly {
                        Picker("Vertical tilt", selection: Binding(
                            get: { Int(formViewModel.tilt) ?? 0 },
                            set: { formViewModel.tilt = String($0) }
                        )) {
                            ForEach(tiltOptions(current: Int(formViewModel.tilt) ?? 0), id: \.self) { degrees in
                                Text("\(degrees)°").tag(degrees)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 120)
                    }
                }

                HStack {
                    Text("Distance to subject")
                        .lineLimit(1)
                        .layoutPriority(1)
                    Spacer()
                    TextField("e.g. 2.0", text: $formViewModel.distance)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(DesignTokens.textPrimary)
                        .keyboardType(.decimalPad)
                        .disabled(isReadOnly)
                    Text("m")
                        .foregroundStyle(DesignTokens.textSecondary)
                }
            } header: {
                FormSectionHeader("Position & Direction")
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
                    .foregroundStyle(DesignTokens.textPrimary)
                    .lineLimit(4...8)
                    .disabled(isReadOnly)
            }
            .listRowBackground(DesignTokens.formRowBackground)
        } else {
            Section(header: FormSectionHeader("Accessories")) {
                TextField("Add accessories", text: $formViewModel.accessories, axis: .vertical)
                    .foregroundStyle(DesignTokens.textPrimary)
                    .lineLimit(4...8)
                    .disabled(isReadOnly)
            }
            .listRowBackground(DesignTokens.formRowBackground)
        }
    }
}
