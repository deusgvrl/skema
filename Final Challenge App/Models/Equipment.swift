import SwiftUI
import SwiftData
import Foundation
import CoreGraphics

/// One item in a setup: light, modifier, reflector or camera.
@Model
final class Equipment {
    @Attribute(.unique) var id: UUID
    var category: EquipmentCategory
    var accessoryTypeRaw: String?   // stored, nil for old rows

    @Transient
    var accessoryType: AccessoryType {
       get { accessoryTypeRaw.flatMap(AccessoryType.init(rawValue:)) ?? .reflector }
       set { accessoryTypeRaw = newValue.rawValue }
    }
    
    var label: String
    var name: String
    var role: String

    var positionX: Double
    var positionY: Double

    // Computed property to convert CGPoint in views
    @Transient
    var position: CGPoint {
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

    init(
        id: UUID = UUID(),
        category: EquipmentCategory = .light,
        accessoryType: AccessoryType = .reflector,
        label: String = "",
        name: String = "",
        role: String = "",
        position: CGPoint = .zero,
        power: String = "",
        colorTemp: String = "",
        lens: String = "",
        iso: String = "",
        aperture: String = "",
        shutterSpeed: String = "",
        whiteBalance: String = "",
        height: String = "",
        tilt: String = "",
        horizontalAim: String = "",
        distance: String = "",
        rotationAngle: Double = 0.0,
        accessories: String = "",
        notes: String = ""
    ) {
        self.id = id
        self.category = category
        self.accessoryTypeRaw = accessoryType.rawValue        self.label = label
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

extension Equipment {
    static let pointsPerMeter: Double = 100.0

    /// Resolves image asset name for this equipment instance based on state and selection
    func imageName(isSelected: Bool) -> String {
        category.imageName(isSelected: isSelected, accessoryType: accessoryType)
    }

    /// Resolves PDF icon asset name for this equipment instance
    var pdfImageName: String {
        category.pdfImageName(accessoryType: accessoryType)
    }

    /// Updates `distance` string as a clean number (e.g. "2.50") from (positionX, positionY)
    func syncDistanceFromPosition() {
        let deltaX = positionX
        let deltaY = positionY
        let distanceInPoints = sqrt(deltaX * deltaX + deltaY * deltaY)
        let distanceInMeters = distanceInPoints / Self.pointsPerMeter
        self.distance = String(format: "%.2f", distanceInMeters)
    }

    /// Updates `horizontalAim` string as a clean number (e.g. "45") from `rotationAngle`
    func syncHorizontalAimFromRotation() {
        let displayAngle = (360 - Int(rotationAngle)) % 360
        self.horizontalAim = "\(displayAngle)"
    }

    /// Updates `rotationAngle` from a typed numeric `horizontalAim` string (handles both '.' and ',')
    func syncRotationFromHorizontalAim() {
        let normalized = horizontalAim.replacingOccurrences(of: ",", with: ".")
        let cleaned = normalized.replacingOccurrences(of: "[^0-9.-]", with: "", options: .regularExpression)
        if let displayAngle = Double(cleaned) {
            let rawAngle = (360.0 - displayAngle).truncatingRemainder(dividingBy: 360.0)
            self.rotationAngle = rawAngle < 0 ? rawAngle + 360.0 : rawAngle
        }
    }

    /// Scales (positionX, positionY) along vector from a typed numeric `distance` string (handles both '.' and ',')
    func syncPositionFromDistance() {
        let normalized = distance.replacingOccurrences(of: ",", with: ".")
        let cleaned = normalized.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
        guard let targetMeters = Double(cleaned), targetMeters >= 0 else { return }

        if targetMeters == 0 {
            positionX = 0
            positionY = 0
            self.distance = "0.00"
            return
        }

        let targetPoints = targetMeters * Self.pointsPerMeter
        let currentPoints = sqrt(positionX * positionX + positionY * positionY)

        if currentPoints > 0 {
            let scaleFactor = targetPoints / currentPoints
            positionX *= scaleFactor
            positionY *= scaleFactor
        } else {
            positionX = 0
            positionY = -targetPoints
        }
        self.distance = String(format: "%.2f", targetMeters)
    }

    func clone() -> Equipment {
        Equipment(
            id: self.id,
            category: self.category,
            accessoryType: self.accessoryType,
            label: self.label,
            name: self.name,
            role: self.role,
            position: self.position,
            power: self.power,
            colorTemp: self.colorTemp,
            lens: self.lens,
            iso: self.iso,
            aperture: self.aperture,
            shutterSpeed: self.shutterSpeed,
            whiteBalance: self.whiteBalance,
            height: self.height,
            tilt: self.tilt,
            horizontalAim: self.horizontalAim,
            distance: self.distance,
            rotationAngle: self.rotationAngle,
            accessories: self.accessories,
            notes: self.notes
        )
    }

    func restoreValues(from snapshot: Equipment) {
        self.category = snapshot.category
        self.accessoryType = snapshot.accessoryType
        self.label = snapshot.label
        self.name = snapshot.name
        self.role = snapshot.role
        self.position = snapshot.position
        self.rotationAngle = snapshot.rotationAngle
        self.power = snapshot.power
        self.colorTemp = snapshot.colorTemp
        self.lens = snapshot.lens
        self.iso = snapshot.iso
        self.aperture = snapshot.aperture
        self.shutterSpeed = snapshot.shutterSpeed
        self.whiteBalance = snapshot.whiteBalance
        self.height = snapshot.height
        self.tilt = snapshot.tilt
        self.horizontalAim = snapshot.horizontalAim
        self.distance = snapshot.distance
        self.accessories = snapshot.accessories
        self.notes = snapshot.notes
    }

    /// Rotate every node pointing to subject (0,0)
    func pointToSubject() {
        let deltaX = -positionX
        let deltaY = -positionY

        // Guard against division by zero if node is right on the subject center
        guard hypot(deltaX, deltaY) > 0.001 else { return }

        // In screen coordinates (+Y is down), adding 90° aligns front pointer with target vector
        var targetAngle = (atan2(deltaY, deltaX) * 180.0 / .pi) + 90.0

        // Normalize angle to [0, 360) range
        targetAngle = targetAngle.truncatingRemainder(dividingBy: 360.0)
        if targetAngle < 0 { targetAngle += 360.0 }

        self.rotationAngle = targetAngle
        self.syncHorizontalAimFromRotation()
    }
}
