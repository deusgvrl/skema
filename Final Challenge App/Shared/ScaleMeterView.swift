//
//  ScaleMeterView.swift
//  Final Challenge App
//
//  Created by Satriya Handha Wibowo on 17/11/26.
//

import SwiftUI

struct ScaleMeterView: View {
    let labelText: String
    let barWidth: CGFloat

    var body: some View {
        VStack(spacing: 3) {
            Text(labelText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DesignTokens.textSecondary)

            HStack(spacing: 0) {
                Rectangle().frame(width: 1.5, height: 8).foregroundStyle(DesignTokens.textSecondary)
                Rectangle().frame(height: 1.5).foregroundStyle(DesignTokens.textSecondary)
                Rectangle().frame(width: 1.5, height: 8).foregroundStyle(DesignTokens.textSecondary)
            }
            .frame(width: max(20, barWidth))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

#Preview {
    ScaleMeterView(labelText: "50 cm", barWidth: 50.0)
        .padding()
}
