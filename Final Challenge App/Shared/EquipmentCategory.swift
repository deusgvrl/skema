//
//  EquipmentCategory.swift
//  Skema Photo
//
//  Created by Satriya Handha Wibowo on 26/11/26.
//

import Foundation


enum EquipmentCategory: String, Codable, CaseIterable, Identifiable {
    case camera = "Camera"
    case light = "Light"
    case accessory = "Accessories"

    var id: String { self.rawValue }

    /// The name the app shows. The saved value stays `rawValue`, so "Accessories" still loads.
    var title: String {
        switch self {
        case .camera: "Camera"
        case .light: "Light"
        case .accessory: "Accessory"
        }
    }
}

extension EquipmentCategory {

    /// Resolves the exact image asset name based on selection state and accessory type
    func imageName(isSelected: Bool, accessoryType: AccessoryType = .reflector) -> String {
        switch self {
        case .camera:
            return isSelected ? "icon_camera_selected" : "icon_camera_viewonly"
        case .light:
            return isSelected ? "icon_light_selected" : "icon_light_viewonly"
        case .accessory:
            switch accessoryType {
            case .backdrop:
                return isSelected ? "icon_backdrop_selected" : "icon_backdrop_viewonly"
            case .reflector:
                return isSelected ? "icon_reflector_selected" : "icon_reflector_viewonly"
            case .diffuser:
                return isSelected ? "icon_diffuser_selected" : "icon_diffuser_viewonly"
            }
        }
    }

    /// The black icon drawn in the PDF's diagram.
    func pdfImageName(accessoryType: AccessoryType = .reflector) -> String {
        switch self {
        case .camera:
            return "icon_camera_pdf"
        case .light:
            return "icon_light_pdf"
        case .accessory:
            switch accessoryType {
            case .backdrop:
                return "icon_backdrop_pdf"
            case .reflector:
                return "icon_reflector_pdf"
            case .diffuser:
                return "icon_diffuser_pdf"
            }
        }
    }

    /// Controls specific width/height dimensions for each category
    var iconSize: CGSize {
        switch self {
        case .camera:
            return CGSize(width: 80, height: 80)
        case .light:
            return CGSize(width: 80, height: 80)
        case .accessory:
            return CGSize(width: 80, height: 80)
        }
    }
}

