import SwiftUI

extension Color {
    private struct KelvinStop {
        let kelvin: Double
        let redComponent: Double
        let greenComponent: Double
        let blueComponent: Double
    }

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
        let clampedKelvin = min(max(kelvin, 1000.0), 10000.0)

        // Exact RGB stops sampled from the 1000K - 10000K spectrum chart
        let stops: [KelvinStop] = [
            KelvinStop(kelvin: 1000, redComponent: 1.00, greenComponent: 0.35, blueComponent: 0.15),
            KelvinStop(kelvin: 2000, redComponent: 1.00, greenComponent: 0.60, blueComponent: 0.21),
            KelvinStop(kelvin: 3000, redComponent: 1.00, greenComponent: 0.76, blueComponent: 0.45),
            KelvinStop(kelvin: 4000, redComponent: 1.00, greenComponent: 0.87, blueComponent: 0.67),
            KelvinStop(kelvin: 5000, redComponent: 1.00, greenComponent: 0.94, blueComponent: 0.87),
            KelvinStop(kelvin: 6000, redComponent: 0.93, greenComponent: 0.97, blueComponent: 1.00),
            KelvinStop(kelvin: 7000, redComponent: 0.78, greenComponent: 0.90, blueComponent: 1.00),
            KelvinStop(kelvin: 8000, redComponent: 0.43, greenComponent: 0.77, blueComponent: 1.00),
            KelvinStop(kelvin: 9000, redComponent: 0.16, greenComponent: 0.70, blueComponent: 1.00),
            KelvinStop(kelvin: 10000, redComponent: 0.00, greenComponent: 0.64, blueComponent: 1.00)
        ]

        // Find boundary segment and interpolate linearly
        for index in 0..<(stops.count - 1) {
            let lowerStop = stops[index]
            let upperStop = stops[index + 1]

            if clampedKelvin >= lowerStop.kelvin && clampedKelvin <= upperStop.kelvin {
                let fraction = (clampedKelvin - lowerStop.kelvin) / (upperStop.kelvin - lowerStop.kelvin)

                let redDelta = upperStop.redComponent - lowerStop.redComponent
                let greenDelta = upperStop.greenComponent - lowerStop.greenComponent
                let blueDelta = upperStop.blueComponent - lowerStop.blueComponent

                let redComponent = lowerStop.redComponent + fraction * redDelta
                let greenComponent = lowerStop.greenComponent + fraction * greenDelta
                let blueComponent = lowerStop.blueComponent + fraction * blueDelta

                return Color(red: redComponent, green: greenComponent, blue: blueComponent)
            }
        }

        guard let lastStop = stops.last else {
            return Color.white
        }
        return Color(red: lastStop.redComponent, green: lastStop.greenComponent, blue: lastStop.blueComponent)
    }
}
