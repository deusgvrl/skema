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
    let nodes: [Equipment]
    
    private var summaryText: String {
        guard !nodes.isEmpty else { return "No equipment detected yet" }
        
        var parts: [String] = []
        
        // Count lights
        let lightCount = nodes.filter { $0.category == .light }.count
        if lightCount > 0 {
            parts.append("\(lightCount) \(lightCount == 1 ? "light" : "lights")")
        }
        
        // Count cameras
        let cameraCount = nodes.filter { $0.category == .camera }.count
        if cameraCount > 0 {
            parts.append("\(cameraCount) \(cameraCount == 1 ? "camera" : "cameras")")
        }
        
        // Count bounces
        let bounceCount = nodes.filter {
            $0.name.localizedCaseInsensitiveContains("bounce") ||
            $0.role.localizedCaseInsensitiveContains("bounce")
        }.count
        if bounceCount > 0 {
            parts.append("\(bounceCount) \(bounceCount == 1 ? "bounce" : "bounces")")
        }
        
        // Check for backdrop
        let hasBackdrop = nodes.contains {
            $0.name.localizedCaseInsensitiveContains("backdrop") ||
            $0.role.localizedCaseInsensitiveContains("backdrop")
        }
        if hasBackdrop {
            parts.append("backdrop found")
        }
        
        if parts.isEmpty {
            return "\(nodes.count) \(nodes.count == 1 ? "item" : "items") found"
        }
        
        return parts.joined(separator: " · ")
    }
    
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
            
            let secondsLeft = max(1, Int((1.0 - progress) * 20))
            
            VStack(spacing: 12) {
                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(.blue)
                    .padding(.horizontal, 32)
                
                Text("Measuring distances... About \(secondsLeft) seconds left")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                
                Text(summaryText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 40)
        }
        .background(Color(uiColor: .systemBackground))
    }
}

#Preview {
    ReviewLoadingView(
        progress: 0.75,
        isScanComplete: false,
        nodes: []
    )
}
