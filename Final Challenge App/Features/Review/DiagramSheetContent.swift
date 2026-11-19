//
//  DiagramSheetContent.swift
//  Final Challenge App
//
//  Represents what the unified bottom sheet is showing: an equipment node or the subject.
//

import Foundation

enum DiagramSheetContent: Equatable {
    case equipment(UUID)
    case subject

    var equipmentId: UUID? {
        switch self {
        case .equipment(let id): return id
        case .subject: return nil
        }
    }

    var isSubject: Bool {
        switch self {
        case .subject: return true
        case .equipment: return false
        }
    }
}
