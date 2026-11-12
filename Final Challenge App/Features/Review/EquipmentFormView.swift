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
    
    init(viewModel: ReviewViewModel, editingNodeId: UUID?, undoManager: UndoManager?, isReadOnly: Bool = false) {
        self.undoManager = undoManager
        self.isReadOnly = isReadOnly
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
                Section(header: Text("Equipment")) {
                    Picker("Category", selection: $formViewModel.category) {
                        ForEach(EquipmentCategory.allCases) { cat in
                            Text(cat.rawValue).tag(cat)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.blue)
                    .disabled(isReadOnly)
                    
                    HStack {
                        Text("Name")
                        Spacer()
                        TextField("Required", text: $formViewModel.name)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    if formViewModel.category != .accessory {
                        HStack {
                            Text("Role / label")
                            Spacer()
                            TextField(formViewModel.category == .light ? "e.g. Accent light" : "e.g. Second camera", text: $formViewModel.role)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                
                // MARK: 2. Category-Specific Settings
                if formViewModel.category == .light {
                    Section(header: Text("Light Settings")) {
                        HStack {
                            Text("Power")
                            Spacer()
                            TextField("-", text: $formViewModel.power)
                                .multilineTextAlignment(.trailing)
                        }
                        HStack {
                            Text("Color temperature")
                            Spacer()
                            TextField("-", text: $formViewModel.colorTemp)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.numberPad)
                            Text("K")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                if formViewModel.category == .camera {
                    Section(header: Text("Lens")) {
                        HStack {
                            Text("Lens")
                            Spacer()
                            TextField("-", text: $formViewModel.lens)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    
                    Section(header: Text("Camera Settings")) {
                        HStack {
                            Text("ISO")
                            Spacer()
                            TextField("-", text: $formViewModel.iso)
                                .multilineTextAlignment(.trailing)
                        }
                        HStack {
                            Text("Aperture")
                            Spacer()
                            TextField("-", text: $formViewModel.aperture)
                                .multilineTextAlignment(.trailing)
                        }
                        HStack {
                            Text("Shutter speed")
                            Spacer()
                            TextField("-", text: $formViewModel.shutterSpeed)
                                .multilineTextAlignment(.trailing)
                        }
                        HStack {
                            Text("White balance")
                            Spacer()
                            TextField("-", text: $formViewModel.whiteBalance)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.numberPad)
                            Text("K")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // MARK: 3. Position & Direction
                if formViewModel.category != .accessory {
                    Section(
                        header: Text("Position & Direction"),
                        footer: Text(isReadOnly ? "Viewing equipment details from read-only mode." : "It's placed next to the subject for now. You can drag it to the right spot on the diagram, or change these values anytime later.")
                    ) {
                        HStack {
                            Text("Height")
                            Spacer()
                            TextField("-", text: $formViewModel.height)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.decimalPad)
                            Text("m")
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Tilt")
                            Spacer()
                            TextField("-", text: $formViewModel.tilt)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.numberPad)
                            Text("°")
                                .foregroundStyle(.secondary)
                        }
                        
                        if formViewModel.category == .light {
                            HStack {
                                Text("Horizontal aim")
                                Spacer()
                                TextField("-", text: $formViewModel.horizontalAim)
                                    .multilineTextAlignment(.trailing)
                                    .keyboardType(.numberPad)
                                Text("°")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        HStack {
                            Text("Distance to subject")
                            Spacer()
                            TextField("-", text: $formViewModel.distance)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.decimalPad)
                            Text("m")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // MARK: 4. Bottom Text Area
                if formViewModel.category == .accessory {
                    Section(header: Text("Notes")) {
                        TextField("Add notes", text: $formViewModel.notes, axis: .vertical)
                            .lineLimit(4...8)
                    }
                } else {
                    Section(header: Text("Accessories")) {
                        TextField("Add accessories", text: $formViewModel.accessories, axis: .vertical)
                            .lineLimit(4...8)
                    }
                }
                
                // Delete Button
                if formViewModel.isEditing && !isReadOnly {
                    Button(role: .destructive, action: {
                        isDeleteAlert = true
                    }) {
                        Text("Delete Equipment")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .disabled(isReadOnly)
            .navigationTitle(formViewModel.isEditing ? (formViewModel.role.isEmpty ? "Equipment Details" : formViewModel.role) : "Add Equipment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isReadOnly ? "Close" : "Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }
                
                if !isReadOnly {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", systemImage: "checkmark") {
                            formViewModel.saveNode(undoManager: undoManager) {
                                dismiss()
                            }
                        }
                        .disabled(!formViewModel.isFormValid)
                    }
                }
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
    }
}

#Preview {
    EquipmentFormView(viewModel: ReviewViewModel(), editingNodeId: nil, undoManager: nil)
}
