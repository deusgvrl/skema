//
//  ReferenceImage.swift
//  Final Challenge App
//
//  Created by Satriya Handha Wibowo on 10/11/26.
//

import SwiftUI
import SwiftData
import Foundation

@Model
final class ReferenceImage {
    @Attribute(.unique) var id: UUID
    
    // .externalStorage tells SwiftData to store this heavy data on the file system
    // instead of bloating the SQLite database, preventing UI lag.
    @Attribute(.externalStorage) var imageData: Data
    
    // Relationship back to parent
    var setup: Setup?
    
    init(id: UUID = UUID(), imageData: Data) {
        self.id = id
        self.imageData = imageData
    }
}
