//
//  AccesoryType.swift
//  Skema Photo
//
//  Created by Satriya Handha Wibowo on 26/11/26.
//

import Foundation

/// Specific icon variations available when `category == .accessory`
enum AccessoryType: String, Codable, CaseIterable, Identifiable {
    case reflector = "Reflector"
    case backdrop = "Backdrop"
    case diffuser = "Diffuser"

    var id: String { rawValue }

    var title: String { rawValue }
}

