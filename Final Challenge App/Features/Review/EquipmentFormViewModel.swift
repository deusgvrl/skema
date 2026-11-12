//
//  EquipmentFormViewModel.swift
//  Final Challenge App
//
//  Created by Satriya Handha Wibowo on 11/11/26.
//

import SwiftUI
import Observation

@Observable
final class EquipmentFormViewModel {
    // Form Inputs
    var category: EquipmentCategory = .camera
    var name: String = ""
    var role: String = ""
    
    // Light properties
    var power: String = ""
    var colorTemp: String = ""
    
    // Camera properties
    var lens: String = ""
    var iso: String = ""
    var aperture: String = ""
    var shutterSpeed: String = ""
    var whiteBalance: String = ""
    
    // Position & Direction
    var height: String = ""
    var tilt: String = ""
    var horizontalAim: String = ""
    var distance: String = ""
    
    // Text areas
    var accessories: String = ""
    var notes: String = ""
    
    let editingNodeId: UUID?
    private unowned let reviewViewModel: ReviewViewModel
    
    var isEditing: Bool { editingNodeId != nil }
    
    var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    init(editingNodeId: UUID?, reviewViewModel: ReviewViewModel) {
        self.editingNodeId = editingNodeId
        self.reviewViewModel = reviewViewModel
        loadData()
    }
    
    // MARK: - Data Operations
    
    func loadData() {
        guard let id = editingNodeId,
              let node = reviewViewModel.nodes.first(where: { $0.id == id }) else { return }
        
        category = node.category
        name = node.name
        role = node.role
        power = node.power
        
        // Strip unit suffixes so input fields hold clean numeric strings
        colorTemp = cleanNumericString(node.colorTemp)
        lens = node.lens
        iso = node.iso
        aperture = node.aperture
        shutterSpeed = node.shutterSpeed
        whiteBalance = cleanNumericString(node.whiteBalance)
        height = cleanNumericString(node.height)
        tilt = cleanNumericString(node.tilt)
        horizontalAim = cleanNumericString(node.horizontalAim)
        distance = cleanNumericString(node.distance)
        
        accessories = node.accessories
        notes = node.notes
    }
    
    func saveNode(undoManager: UndoManager?, completion: () -> Void) {
        let sanitizedDistance = cleanNumericString(distance)
        let sanitizedAim = cleanNumericString(horizontalAim)
        
        if let id = editingNodeId, let index = reviewViewModel.nodes.firstIndex(where: { $0.id == id }) {
            let node = reviewViewModel.nodes[index]
            node.category = category
            node.name = name
            node.role = role
            node.power = power
            node.colorTemp = cleanNumericString(colorTemp)
            node.lens = lens
            node.iso = iso
            node.aperture = aperture
            node.shutterSpeed = shutterSpeed
            node.whiteBalance = cleanNumericString(whiteBalance)
            node.height = cleanNumericString(height)
            node.tilt = cleanNumericString(tilt)
            node.horizontalAim = sanitizedAim
            node.distance = sanitizedDistance
            node.accessories = accessories
            node.notes = notes
            
            // Synchronize diagram coordinates & heading rotation angle
            node.syncRotationFromHorizontalAim()
            node.syncPositionFromDistance()
            
            reviewViewModel.updateEquipment(undoManager: undoManager)
        } else {
            let newNode = Equipment(
                category: category,
                label: "E\(reviewViewModel.nodes.count + 1)",
                name: name,
                role: role,
                position: CGPoint(x: 0, y: -100),
                power: power,
                colorTemp: cleanNumericString(colorTemp),
                lens: lens,
                iso: iso,
                aperture: aperture,
                shutterSpeed: shutterSpeed,
                whiteBalance: cleanNumericString(whiteBalance),
                height: cleanNumericString(height),
                tilt: cleanNumericString(tilt),
                horizontalAim: sanitizedAim,
                distance: sanitizedDistance.isEmpty ? "1.00" : sanitizedDistance,
                accessories: accessories,
                notes: notes
            )
            
            newNode.syncRotationFromHorizontalAim()
            newNode.syncPositionFromDistance()
            
            reviewViewModel.addEquipment(newNode, undoManager: undoManager)
        }
        
        completion()
    }
    
    func deleteNode(undoManager: UndoManager?, completion: () -> Void) {
        guard let id = editingNodeId else { return }
        let oldNodes = reviewViewModel.nodes
        reviewViewModel.nodes.removeAll { $0.id == id }
        reviewViewModel.applyStateChange(oldNodes: oldNodes, undoManager: undoManager)
        StorageController.shared.save()
        completion()
    }
    
    // MARK: - Sanitization Helper
    
    /// Sanitizes strings by stripping non-numeric unit characters, keeping pure numeric inputs (e.g. "2.50").
    private func cleanNumericString(_ input: String) -> String {
        let cleaned = input.replacingOccurrences(of: "[^0-9.-]", with: "", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
