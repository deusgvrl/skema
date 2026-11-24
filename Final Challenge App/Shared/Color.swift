//
//  Color.swift
//  Skema Photo
//
//  Created by Satriya Handha Wibowo on 24/11/26.
//

import SwiftUI

extension Color {
    /// Converts a Kelvin temperature string (e.g. "3200", "5600", "8000")
    /// to match the UI spectrum scale exactly (1000K to 10000K).
    static func kelvinColor(from tempString: String) -> Color {
        let normalized = tempString.replacingOccurrences(of: ",", with: ".")
        let cleaned = normalized.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
        guard let kelvin = Double(cleaned), kelvin > 0 else {
            return kelvinToColor(kelvin: 5600) // Default neutral daylight
        }
        return kelvinToColor(kelvin: kelvin)
    }

    private static func kelvinToColor(kelvin: Double) -> Color {
        let k = min(max(kelvin, 1000.0), 10000.0)
        
        // Exact RGB stops sampled from the 1000K - 10000K spectrum chart
        let stops: [(kelvin: Double, r: Double, g: Double, b: Double)] = [
            (1000,  1.00, 0.35, 0.15), // 1000K: Fiery Red-Orange
            (2000,  1.00, 0.60, 0.21), // 2000K: Rich Amber
            (3000,  1.00, 0.76, 0.45), // 3000K: Warm Gold / Tungsten
            (4000,  1.00, 0.87, 0.67), // 4000K: Soft Warm Cream
            (5000,  1.00, 0.94, 0.87), // 5000K: Natural Off-White
            (6000,  0.93, 0.97, 1.00), // 6000K: Cool Crisp White
            (7000,  0.78, 0.90, 1.00), // 7000K: Soft Ice Blue
            (8000,  0.43, 0.77, 1.00), // 8000K: Sky Blue
            (9000,  0.16, 0.70, 1.00), // 9000K: Electric Cyan-Blue
            (10000, 0.00, 0.64, 1.00)  // 10000K: Deep Cyan-Blue
        ]

        // Find boundary segment and interpolate linearly
        for i in 0..<(stops.count - 1) {
            let lower = stops[i]
            let upper = stops[i + 1]

            if k >= lower.kelvin && k <= upper.kelvin {
                let fraction = (k - lower.kelvin) / (upper.kelvin - lower.kelvin)
                let r = lower.r + fraction * (upper.r - lower.r)
                let g = lower.g + fraction * (upper.g - lower.g)
                let b = lower.b + fraction * (upper.b - lower.b)
                return Color(red: r, green: g, blue: b)
            }
        }

        let last = stops.last!
        return Color(red: last.r, green: last.g, blue: last.b)
    }
}
