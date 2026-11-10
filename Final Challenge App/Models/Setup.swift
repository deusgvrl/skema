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
    
    // 1-to-Many Relationship: Deleting a setup deletes its equipment.
    @Relationship(deleteRule: .cascade, inverse: \Equipment.setup)
    var nodes: [Equipment] = []
    
    init(id: UUID = UUID(), setupName: String = "", client: String = "", project: String = "", notes: String = "") {
        self.id = id
        self.setupName = setupName
        self.client = client
        self.project = project
        self.notes = notes
    }
}
