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
    
    func saveNode(undoManager: UndoManager?, completion: () -> Void) {
        if let id = editingNodeId, let index = reviewViewModel.nodes.firstIndex(where: { $0.id == id }) {
            let node = reviewViewModel.nodes[index]
            node.category = category
            node.name = name
            node.role = role
            node.power = power
            node.colorTemp = colorTemp
            node.lens = lens
            node.iso = iso
            node.aperture = aperture
            node.shutterSpeed = shutterSpeed
            node.whiteBalance = whiteBalance
            node.height = height
            node.tilt = tilt
            node.horizontalAim = horizontalAim
            node.distance = distance
            node.accessories = accessories
            node.notes = notes
            
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
}
