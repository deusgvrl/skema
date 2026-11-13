//
//  ScanGuidanceView.swift
//  Final Challenge App
//
//  Created by Muhammad Dzakki Abdullah on 13/11/26.
//

import SwiftUI

struct ScanGuidanceView: View {
    let guidance: ScanGuidance

    var body: some View {
        Text(guidance.message)
            .font(.headline)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, 24)
            .onChange(of: guidance, initial: true) {
                AccessibilityNotification.Announcement(guidance.message).post()
            }
    }
}

#Preview("Move slower") {
    ZStack {
        Color.gray.ignoresSafeArea()
        ScanGuidanceView(guidance: .moveSlower)
    }
    .environment(\.colorScheme, .dark)
}
