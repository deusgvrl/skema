//
//  EquipmentFormView.swift
//  Final Challenge App
//
//  Created by Satriya Handha Wibowo on 11/11/26.
//

import SwiftUI

struct EquipmentFormView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var formViewModel: EquipmentFormViewModel
    
    let undoManager: UndoManager?
    var isReadOnly: Bool = false
    
    @State private var isDeleteAlert: Bool = false
    @State private var isDiscardAlertPresented: Bool = false
    @State private var isDirty: Bool = false
    /// "L1 Key" for an existing item (Sketch R06a), nil when adding.
    private let editingTitle: String?
    
    init(viewModel: ReviewViewModel, editingNodeId: UUID?, undoManager: UndoManager?, isReadOnly: Bool = false) {
        self.undoManager = undoManager
        self.isReadOnly = isReadOnly
        self.editingTitle = viewModel.nodes.first { $0.id == editingNodeId }?.displayName
        self._formViewModel = State(initialValue: EquipmentFormViewModel(
            editingNodeId: editingNodeId,
            reviewViewModel: viewModel
        ))
    }
    
    var body: some View {
        @Bindable var formViewModel = formViewModel
        
        NavigationStack {
            Form {
                // MARK: 1. Equipment Section
                Section(header: FormSectionHeader("Equipment")) {
                    Picker("Category", selection: $formViewModel.category) {
                        ForEach(EquipmentCategory.allCases) { cat in
                            Text(cat.rawValue).tag(cat)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(DesignTokens.accentText)
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
                            TextField(formViewModel.category == .light ? "e.g. Accent light" : "e.g. Second camera", text: $formViewModel.role)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(DesignTokens.textSecondary)
                            .foregroundStyle(DesignTokens.textSecondary)
                                .disabled(isReadOnly)
                        }
                    }
                }
                .listRowBackground(DesignTokens.formRowBackground)
                
                // MARK: 2. Category-Specific Settings
                if formViewModel.category == .light {
                    Section(header: FormSectionHeader("Light Settings")) {
                        HStack {
                            Text("Power")
                            Spacer()
                            TextField("-", text: $formViewModel.power)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(DesignTokens.textSecondary)
                            .foregroundStyle(DesignTokens.textSecondary)
                                .disabled(isReadOnly)
                        }
                        HStack {
                            Text("Color temperature")
                            Spacer()
                            TextField("-", text: $formViewModel.colorTemp)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(DesignTokens.textSecondary)
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
                            TextField("-", text: $formViewModel.lens)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(DesignTokens.textSecondary)
                            .foregroundStyle(DesignTokens.textSecondary)
                                .disabled(isReadOnly)
                        }
                    }
                    .listRowBackground(DesignTokens.formRowBackground)
                    
                    Section(header: FormSectionHeader("Camera Settings")) {
                        HStack {
                            Text("ISO")
                            Spacer()
                            TextField("-", text: $formViewModel.iso)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(DesignTokens.textSecondary)
                            .foregroundStyle(DesignTokens.textSecondary)
                                .disabled(isReadOnly)
                        }
                        HStack {
                            Text("Aperture")
                            Spacer()
                            TextField("-", text: $formViewModel.aperture)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(DesignTokens.textSecondary)
                            .foregroundStyle(DesignTokens.textSecondary)
                                .disabled(isReadOnly)
                        }
                        HStack {
                            Text("Shutter speed")
                            Spacer()
                            TextField("-", text: $formViewModel.shutterSpeed)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(DesignTokens.textSecondary)
                            .foregroundStyle(DesignTokens.textSecondary)
                                .disabled(isReadOnly)
                        }
                        HStack {
                            Text("White balance")
                            Spacer()
                            TextField("-", text: $formViewModel.whiteBalance)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(DesignTokens.textSecondary)
                            .foregroundStyle(DesignTokens.textSecondary)
                                .keyboardType(.numberPad)
                                .disabled(isReadOnly)
                            Text("K")
                                .foregroundStyle(DesignTokens.textSecondary)
                        }
                    }
                    .listRowBackground(DesignTokens.formRowBackground)
                }
                
                // MARK: 3. Position & Direction
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
                            TextField("-", text: $formViewModel.height)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(DesignTokens.textSecondary)
                            .foregroundStyle(DesignTokens.textSecondary)
                                .keyboardType(.decimalPad)
                                .disabled(isReadOnly)
                            Text("m")
                                .foregroundStyle(DesignTokens.textSecondary)
                        }
                        HStack {
                            Text("Tilt")
                            Spacer()
                            TextField("-", text: $formViewModel.tilt)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(DesignTokens.textSecondary)
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
                                TextField("-", text: $formViewModel.horizontalAim)
                                    .multilineTextAlignment(.trailing)
                                .foregroundStyle(DesignTokens.textSecondary)
                            .foregroundStyle(DesignTokens.textSecondary)
                                    .keyboardType(.numberPad)
                                    .disabled(isReadOnly)
                                Text("°")
                                    .foregroundStyle(DesignTokens.textSecondary)
                            }
                        }
                        
                        HStack {
                            Text("Distance to subject")
                            Spacer()
                            TextField("-", text: $formViewModel.distance)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(DesignTokens.textSecondary)
                            .foregroundStyle(DesignTokens.textSecondary)
                                .keyboardType(.decimalPad)
                                .disabled(isReadOnly)
                            Text("m")
                                .foregroundStyle(DesignTokens.textSecondary)
                        }
                    }
                    .listRowBackground(DesignTokens.formRowBackground)
                }
                
                // MARK: 4. Bottom Text Area
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
                
                // Delete Button: outlined red capsule (Sketch R06)
                if formViewModel.isEditing && !isReadOnly {
                    Button(role: .destructive) {
                        isDeleteAlert = true
                    } label: {
                        Text("Delete Equipment")
                            .foregroundStyle(DesignTokens.accentText)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .overlay(Capsule().strokeBorder(DesignTokens.accentText.opacity(0.6), lineWidth: 1))
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .foregroundStyle(DesignTokens.textPrimary)
            .scrollContentBackground(.hidden)
            .background(DesignTokens.sheetBackground)
            // REMOVED: .disabled(isReadOnly) here so the Form scroll view remains interactive!
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
                        Button("Done", systemImage: "checkmark") {
                            formViewModel.saveNode(undoManager: undoManager) {
                                dismiss()
                            }
                        }
                        .buttonStyle(.glassProminent)
                        .tint(DesignTokens.accentPrimary)
                        .disabled(!formViewModel.isFormValid)
                    }
                }
            }
            .interactiveDismissDisabled(!isReadOnly && isDirty)
            .onChange(of: formViewModel.name) { _, _ in isDirty = true }
            .onChange(of: formViewModel.role) { _, _ in isDirty = true }
            .onChange(of: formViewModel.distance) { _, _ in isDirty = true }
            .onChange(of: formViewModel.horizontalAim) { _, _ in isDirty = true }
            .onChange(of: formViewModel.height) { _, _ in isDirty = true }
            .onChange(of: formViewModel.tilt) { _, _ in isDirty = true }
            .onChange(of: formViewModel.colorTemp) { _, _ in isDirty = true }
            .onChange(of: formViewModel.whiteBalance) { _, _ in isDirty = true }
            .onChange(of: formViewModel.power) { _, _ in isDirty = true }
            .onChange(of: formViewModel.accessories) { _, _ in isDirty = true }
            .onChange(of: formViewModel.notes) { _, _ in isDirty = true }
            
            .alert("Discard Unsaved Changes?", isPresented: $isDiscardAlertPresented) {
                Button("Keep Editing", role: .cancel) { }
                Button("Discard", role: .destructive) { dismiss() }
            } message: {
                Text("You have unsaved changes. Are you sure you want to discard them?")
            }
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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(DesignTokens.sheetBackground)
    }
}
