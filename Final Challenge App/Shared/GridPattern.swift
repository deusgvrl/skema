//
//  GridPattern.swift
//  Final Challenge App
//
//  Created by Satriya Handha Wibowo on 17/11/26.
//

import SwiftUI

struct GridPattern: Shape {
    var step: CGFloat = 50
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for x in stride(from: 0, through: rect.width, by: step) {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
        }
        for y in stride(from: 0, through: rect.height, by: step) {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
        }
        return path
    }
}


struct GridConfig {
    let stepInPoints: CGFloat // Grid tile width in canvas model points
    let labelText: String     // Scale badge text (e.g. "25 cm", "50 cm", "1 m")
    
    /// Calculates the optimal grid subdivision step based on the active zoom factor
    static func config(for scale: CGFloat) -> GridConfig {
        // Target model distance that maps to roughly 50–70 screen pixels
        let targetMeters = 0.5 / scale
        
        if targetMeters <= 0.08 {
            // Very Deep Zoom (scale >= 6.25x) -> 5 cm per tile
            return GridConfig(stepInPoints: 5, labelText: "5 cm")
        } else if targetMeters <= 0.18 {
            // Zoomed In High (2.78x <= scale < 6.25x) -> 10 cm per tile
            return GridConfig(stepInPoints: 10, labelText: "10 cm")
        } else if targetMeters <= 0.35 {
            // Zoomed In Medium (1.43x <= scale < 2.78x) -> 25 cm per tile
            return GridConfig(stepInPoints: 25, labelText: "25 cm")
        } else if targetMeters <= 0.75 {
            // Standard View (0.67x <= scale < 1.43x) -> 50 cm per tile
            return GridConfig(stepInPoints: 50, labelText: "50 cm")
        } else if targetMeters <= 1.5 {
            // Zoomed Out (0.33x <= scale < 0.67x) -> 1 meter per tile
            return GridConfig(stepInPoints: 100, labelText: "1 m")
        } else {
            // Far Zoomed Out (scale < 0.33x) -> 2 meters per tile
            return GridConfig(stepInPoints: 200, labelText: "2 m")
        }
    }
}
