//
//  LightBeamConeView.swift
//  Final Challenge App
//
//  Created by Satriya Handha Wibowo on 26/11/26.
//

import SwiftUI

struct LightBeamConeView: View {
    let colorTemp: String

    private var lightColor: Color {
        Color.kelvinColor(from: colorTemp)
    }

    var body: some View {
        ZStack {
            LightBeamShape()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: lightColor.opacity(0.85), location: 0.0),
                            .init(color: lightColor.opacity(0.40), location: 0.4),
                            .init(color: lightColor.opacity(0.10), location: 0.8),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(width: 84, height: 96)
                .blur(radius: 4)

            LightBeamShape()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.9), location: 0.0),
                            .init(color: lightColor.opacity(0.6), location: 0.3),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(width: 48, height: 75)
                .blur(radius: 1.5)
        }
        .offset(y: -55)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct LightBeamShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let originWidth: CGFloat = 16
        let beamWidth: CGFloat = rect.width
        let originInset = (beamWidth - originWidth) / 2

        path.move(to: CGPoint(x: originInset, y: rect.maxY))
        path.addLine(to: CGPoint(x: beamWidth - originInset, y: rect.maxY))
        path.addLine(to: CGPoint(x: beamWidth, y: rect.minY))
        path.addLine(to: CGPoint(x: 0, y: rect.minY))
        path.closeSubpath()

        return path
    }
}
