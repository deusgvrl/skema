import SwiftUI
import SwiftData
import Foundation

/// A saved lighting setup. Fields are added with A10-13.
@Model
final class Setup {
    @Attribute(.unique) var id: UUID
    var setupName: String
    var client: String
    var project: String
    var notes: String
    var subjectHeight: String = ""
    
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
