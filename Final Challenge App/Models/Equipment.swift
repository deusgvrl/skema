import SwiftUI
import SwiftData
import Foundation

/// One item in a setup: light, modifier, reflector or camera. Fields are added with A10-7 and A10-11.
@Model
final class Equipment {
    @Attribute(.unique) var id: UUID
    var category: EquipmentCategory
    
    var label: String
    var name: String
    var role: String
    
    var positionX: Double
    var positionY: Double
    
    // Computed property to convert CGPoint in views
    @Transient var position: CGPoint {
        get { CGPoint(x: positionX, y: positionY) }
        set {
            positionX = Double(newValue.x)
            positionY = Double(newValue.y)
        }
    }
    
    // Light-specific
    var power: String
    var colorTemp: String
    
    // Camera-specific
    var lens: String
    var iso: String
    var aperture: String
    var shutterSpeed: String
    var whiteBalance: String
    
    // Shared positioning
    var height: String
    var tilt: String
    var horizontalAim: String
    var distance: String
    var rotationAngle: Double
    
    // Text areas
    var accessories: String
    var notes: String
    
    // Relationship back to parent
    var setup: Setup?
    
    init(id: UUID = UUID(), category: EquipmentCategory = .light, label: String = "", name: String = "", role: String = "", position: CGPoint = .zero, power: String = "", colorTemp: String = "", lens: String = "", iso: String = "", aperture: String = "", shutterSpeed: String = "", whiteBalance: String = "", height: String = "", tilt: String = "", horizontalAim: String = "", distance: String = "", rotationAngle: Double = 0.0, accessories: String = "", notes: String = "") {
        self.id = id
        self.category = category
        self.label = label
        self.name = name
        self.role = role
        self.positionX = Double(position.x)
        self.positionY = Double(position.y)
        self.power = power
        self.colorTemp = colorTemp
        self.lens = lens
        self.iso = iso
        self.aperture = aperture
        self.shutterSpeed = shutterSpeed
        self.whiteBalance = whiteBalance
        self.height = height
        self.tilt = tilt
        self.horizontalAim = horizontalAim
        self.distance = distance
        self.rotationAngle = rotationAngle
        self.accessories = accessories
        self.notes = notes
    }
}

enum EquipmentCategory: String, Codable, CaseIterable, Identifiable {
    case camera = "Camera"
    case light = "Light"
    case accessory = "Accessories"
    
    var id: String { self.rawValue }
}
