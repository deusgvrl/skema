//
//  EquipmentFormView.swift
//  Final Challenge App
//
//  Created by Satriya Handha Wibowo on 11/11/26.
//

import SwiftUI

struct EquipmentFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: ReviewViewModel
    let editingNodeId: UUID?
    let undoManager: UndoManager?
    var isReadOnly: Bool = false
    
    @State private var category: EquipmentCategory = .camera
    
    @State private var name: String = ""
    @State private var role: String = ""
    
    // Light properties
    @State private var power: String = ""
    @State private var colorTemp: String = ""
    
    // Camera properties
    @State private var lens: String = ""
    @State private var iso: String = ""
    @State private var aperture: String = ""
    @State private var shutterSpeed: String = ""
    @State private var whiteBalance: String = ""
    
    // Shared properties
    @State private var height: String = ""
    @State private var tilt: String = ""
    @State private var horizontalAim: String = ""
    @State private var distance: String = ""
    
    // Text areas
    @State private var accessories: String = ""
    @State private var notes: String = ""
    
    var isEditing: Bool { editingNodeId != nil }
    @State private var isDeleteAlert: Bool = false
    
    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // MARK: 1. Equipment Section
                Section(header: Text("Equipment")) {
                    Picker("Category", selection: $category) {
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
                        TextField("Required", text: $name)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    if category != .accessory {
                        HStack {
                            Text("Role / label")
                            Spacer()
                            TextField(category == .light ? "e.g. Accent light" : "e.g. Second camera", text: $role)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                
                // MARK: 2. Category-Specific Settings
                if category == .light {
                    Section(header: Text("Light Settings")) {
                        HStack { Text("Power"); Spacer(); TextField("-", text: $power).multilineTextAlignment(.trailing) }
                        HStack { Text("Color temperature"); Spacer(); TextField("- K", text: $colorTemp).multilineTextAlignment(.trailing) }
                    }
                }
                
                if category == .camera {
                    Section(header: Text("Lens")) {
                        HStack { Text("Lens"); Spacer(); TextField("-", text: $lens).multilineTextAlignment(.trailing) }
                    }
                    
                    Section(header: Text("Camera Settings")) {
                        HStack { Text("ISO"); Spacer(); TextField("-", text: $iso).multilineTextAlignment(.trailing) }
                        HStack { Text("Aperture"); Spacer(); TextField("-", text: $aperture).multilineTextAlignment(.trailing) }
                        HStack { Text("Shutter speed"); Spacer(); TextField("-", text: $shutterSpeed).multilineTextAlignment(.trailing) }
                        HStack { Text("White balance"); Spacer(); TextField("- K", text: $whiteBalance).multilineTextAlignment(.trailing) }
                    }
                }
                
                // MARK: 3. Position & Direction (Not shown for Accessories)
                if category != .accessory {
                    Section(
                        header: Text("Position & Direction"),
                        footer: Text(isReadOnly ? "Viewing equipment details from read-only mode." : "It's placed next to the subject for now. You can drag it to the right spot on the diagram, or change these values anytime later.")
                    ) {
                        HStack { Text("Height"); Spacer(); TextField("- cm", text: $height).multilineTextAlignment(.trailing) }
                        HStack { Text("Tilt"); Spacer(); TextField("- °", text: $tilt).multilineTextAlignment(.trailing) }
                        
                        // Horizontal aim is only for lights
                        if category == .light {
                            HStack { Text("Horizontal aim"); Spacer(); TextField("- °", text: $horizontalAim).multilineTextAlignment(.trailing) }
                        }
                        
                        HStack { Text("Distance to subject"); Spacer(); TextField("- m", text: $distance).multilineTextAlignment(.trailing) }
                    }
                }
                
                // MARK: 4. Bottom Text Area
                if category == .accessory {
                    Section(header: Text("Notes")) {
                        TextField("Add notes", text: $notes, axis: .vertical)
                            .lineLimit(4...8)
                    }
                } else {
                    Section(header: Text("Accessories")) {
                        TextField("Add accessories", text: $accessories, axis: .vertical)
                            .lineLimit(4...8)
                    }
                }
                
                // Delete Button
                if isEditing && !isReadOnly {
                    Button(role: .destructive, action: {
                        isDeleteAlert = true
                    }) {
                        Text("Delete Equipment")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .disabled(isReadOnly)
            .navigationTitle(isEditing ? (role.isEmpty ? "Equipment Details" : role) : "Add Equipment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isReadOnly ? "Close" : "Cancel", systemImage: isReadOnly ? "xmark" : "xmark") {
                        dismiss()
                    }
                }
                
                if !isReadOnly {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", systemImage: "checkmark") {
                            saveNode()
                        }
                        .disabled(!isFormValid)
                    }
                }
            }
            .onAppear(perform: loadData)
            .alert("Delete Equipment", isPresented: $isDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    let oldNodes = viewModel.nodes
                    if let id = editingNodeId {
                        viewModel.nodes.removeAll { $0.id == id }
                    }
                    viewModel.applyStateChange(oldNodes: oldNodes, undoManager: undoManager)
                    dismiss()
                }
            } message: {
                Text("Are you sure you want to remove this equipment?")
            }
        }
    }
    
    private func loadData() {
        if let id = editingNodeId, let node = viewModel.nodes.first(where: { $0.id == id }) {
            category = node.category
            name = node.name
            role = node.role
            power = node.power
            colorTemp = node.colorTemp
            lens = node.lens
            iso = node.iso
            aperture = node.aperture
            shutterSpeed = node.shutterSpeed
            whiteBalance = node.whiteBalance
            height = node.height
            tilt = node.tilt
            horizontalAim = node.horizontalAim
            distance = node.distance
            accessories = node.accessories
            notes = node.notes
        }
    }
    
    private func saveNode() {
        guard !isReadOnly else { return }
        let oldNodes = viewModel.nodes
        
        if let id = editingNodeId, let index = viewModel.nodes.firstIndex(where: { $0.id == id }) {
            viewModel.nodes[index].category = category
            viewModel.nodes[index].name = name
            viewModel.nodes[index].role = role
            viewModel.nodes[index].power = power
            viewModel.nodes[index].colorTemp = colorTemp
            viewModel.nodes[index].lens = lens
            viewModel.nodes[index].iso = iso
            viewModel.nodes[index].aperture = aperture
            viewModel.nodes[index].shutterSpeed = shutterSpeed
            viewModel.nodes[index].whiteBalance = whiteBalance
            viewModel.nodes[index].height = height
            viewModel.nodes[index].tilt = tilt
            viewModel.nodes[index].horizontalAim = horizontalAim
            viewModel.nodes[index].distance = distance
            viewModel.nodes[index].accessories = accessories
            viewModel.nodes[index].notes = notes
        } else {
            let newNode = Equipment(
                category: category,
                label: "E\(viewModel.nodes.count + 1)",
                name: name,
                role: role,
                position: CGPoint(x: 0, y: -100),
                power: power,
                colorTemp: colorTemp,
                lens: lens,
                iso: iso,
                aperture: aperture,
                shutterSpeed: shutterSpeed,
                whiteBalance: whiteBalance,
                height: height,
                tilt: tilt,
                horizontalAim: horizontalAim,
                distance: distance,
                accessories: accessories,
                notes: notes
            )
            viewModel.nodes.append(newNode)
        }
        
        viewModel.applyStateChange(oldNodes: oldNodes, undoManager: undoManager)
        dismiss()
    }
}


#Preview {
    EquipmentFormView(viewModel: ReviewViewModel(), editingNodeId: nil, undoManager: nil)
}
