//
//  ReviewLoadingView.swift
//  Final Challenge App
//
//  Created by Satriya Handha Wibowo on 13/11/26.
//

import SwiftUI

struct ReviewLoadingView: View {
    let progress: Double
    let isScanComplete: Bool
    var onContinue: () -> Void
    
    var body: some View {
        VStack(spacing: 40) {
            Image("loading_illustration")
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 260)
                .clipShape(RoundedRectangle(cornerRadius: 28))
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .accessibilityLabel("Scan preview illustration")
            
            VStack(spacing: 16) {
                Text("Building Your Diagram...")
                    .font(.title2.weight(.semibold))
                
                Text("We're mapping your lights, cameras and backdrop, and measuring how far each one is from the subject.\n\nKeep the app open while this finishes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Spacer()
            
            if isScanComplete {
                Button {
                    onContinue()
                } label: {
                    Text("Continue to Layout")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                let secondsLeft = max(1, Int((1.0 - progress) * 20))
                
                VStack(spacing: 12) {
                    ProgressView(value: progress, total: 1.0)
                        .progressViewStyle(.linear)
                        .tint(.blue)
                        .padding(.horizontal, 32)
                    
                    Text("Measuring distances... About \(secondsLeft) seconds left")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    
                    Text("4 lights · 1 bounce · 2 cameras · backdrop found")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 40)
            }
        }
        .background(Color(uiColor: .systemBackground))
    }
}

#Preview {
    ReviewLoadingView(progress: 75.0, isScanComplete: false, onContinue: {})
}
