//
//  LoadingPageView.swift
//  Final Challenge App
//
//  Created by Satriya Handha Wibowo on 09/11/26.
//

import SwiftUI

struct LoadingPageView: View {
    @State private var progress: Double = 0.0
    @State private var isComplete: Bool = false
    @State private var navigateToR04: Bool = false
    
    // @State private var viewModel = SetupViewModel()
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 40) {
                
                Image("loading_illustration")
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .accessibilityLabel("Scan preview illustration")
                    .accessibilityHint("Visual representation of lights, cameras, and subject spatial mapping")
                
                // 2. Text Content
                VStack(spacing: 16) {
                    Text("Building Your Diagram...")
                        .font(.title2.weight(.semibold))
                    
                    Text("We're mapping your lights, cameras and backdrop, and measuring how far each one is from the subject.\n\nKeep the app open while this finishes.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .accessibilityElement(children: .combine)
                
                Spacer()
                
                if isComplete {
                    Button {
                        navigateToR04 = true
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
                    .accessibilityLabel("Continue to Layout")
                    .accessibilityHint("Navigates to the interactive setup layout editor")
                } else {
                    let secondsLeft = max(1, Int((1.0 - progress) * 20))
                    
                    VStack(spacing: 12) {
                        ProgressView(value: progress, total: 1.0)
                            .progressViewStyle(.linear)
                            .tint(.blue)
                            .padding(.horizontal, 32)
                            .accessibilityLabel("Scan processing progress")
                            .accessibilityValue("\(Int(progress * 100)) percent complete")
                        
                        Text("Measuring distances... About \(secondsLeft) seconds left")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        
                        Text("4 lights · 1 bounce · 2 cameras · backdrop found")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 40)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Scan processing status. About \(secondsLeft) seconds left. Detected 4 lights, 1 bounce, 2 cameras, and backdrop.")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") {
                        // Close action
                    }
                    .accessibilityLabel("Cancel scan processing")
                    .accessibilityHint("Dismisses the loading screen and cancels diagram generation")
                }
                
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("Review Setup")
                            .font(.headline)
                            .fontWeight(.bold)
                        Text("Processing scan")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Review Setup header, processing scan")
                }
            }
            .background(Color(uiColor: .systemBackground))
            .onAppear(perform: startLoadingSimulation)
            .fullScreenCover(isPresented: $navigateToR04) {
                NavigationStack {
                    // R04_ReviewSetupView(isFromLoadingScreen: true, viewModel: viewModel)
                }
            }
        }
    }
    
    private func startLoadingSimulation() {
        guard !isComplete else { return }
        
        Task {
            for i in 1...100 {
                try? await Task.sleep(nanoseconds: 40_000_000)
                await MainActor.run {
                    progress = Double(i) / 100.0
                }
            }
            
            await MainActor.run {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    isComplete = true
                }
            }
        }
    }
}

#Preview {
    LoadingPageView()
}
