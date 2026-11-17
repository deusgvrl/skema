import SwiftUI
import SwiftData
import Foundation

extension Setup {
    /// The earliest reference photo, the same one the setup's detail screen shows first.
    var coverImage: ReferenceImage? {
        referenceImages.min { $0.createdAt < $1.createdAt }
    }
}

/// A saved lighting setup. Fields are added with A10-13.
@Model
final class Setup {
    @Attribute(.unique) var id: UUID
    var setupName: String
    var client: String
    var project: String
    var notes: String
    var subjectHeight: String = ""
    var createdAt: Date = Date()
    var deletedAt: Date?

    // 1-to-Many Relationship: Deleting a setup deletes its equipment
    @Relationship(deleteRule: .cascade, inverse: \Equipment.setup)
    var nodes: [Equipment] = []
    
    // 1-to-Many Relationship: Deleting a setup deletes its reference photos
    @Relationship(deleteRule: .cascade, inverse: \ReferenceImage.setup)
    var referenceImages: [ReferenceImage] = []
    
    init(id: UUID = UUID(), setupName: String = "", client: String = "", project: String = "", notes: String = "", subjectHeight: String = "") {
        self.id = id
        self.setupName = setupName
        self.client = client
        self.project = project
        self.notes = notes
        self.subjectHeight = subjectHeight
    }
}

extension Setup {
    /// Rotates all equipment around the subject (0, 0) so that the first camera sits at 6 o'clock.
    /// All other equipment follows with relative positions and distances preserved.
    /// Called once upon scan completion to establish the initial camera baseline.
    func alignFirstCameraToSixOClock() {
        guard let firstCamera = nodes.first(where: { $0.category == .camera }) else { return }
        
        let x1 = firstCamera.positionX
        let y1 = firstCamera.positionY
        guard abs(x1) > 0.001 || abs(y1) > 0.001 else { return }
        
        // In screen coordinates (+Y is down), 6 o'clock is +pi/2 radians (90 degrees)
        let currentAngle = atan2(y1, x1)
        let deltaAngle = (Double.pi / 2.0) - currentAngle
        
        let cosDelta = cos(deltaAngle)
        let sinDelta = sin(deltaAngle)
        
        for node in nodes {
            let oldX = node.positionX
            let oldY = node.positionY
            
            // 2D rotation matrix around (0, 0)
            let newX = oldX * cosDelta - oldY * sinDelta
            let newY = oldX * sinDelta + oldY * cosDelta
            
            node.positionX = newX
            node.positionY = newY
            
            node.syncDistanceFromPosition()
        }
    }
}
