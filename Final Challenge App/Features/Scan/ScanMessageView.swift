//
//  ScanMessageView.swift
//  Final Challenge App
//
//  The scan's full-screen messages (camera off, no LiDAR, scan stopped), moved from the automatic scan's ScanView
//  when object detection was removed (19 Nov 2026).
//

import SwiftUI

/// A full-screen message instead of the camera: glass icon circle, title, body, actions (Sketch R02c).
struct ScanMessageView<Actions: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    let message: Text
    @ViewBuilder let actions: () -> Actions

    @ScaledMetric(relativeTo: .largeTitle) private var iconCircleSize: CGFloat = 80

    var body: some View {
        // Scrolls only when large Dynamic Type no longer fits on screen.
        ViewThatFits(in: .vertical) {
            content
            ScrollView {
                content
                    .padding(.vertical, 24)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            Image(systemName: systemImage)
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(DesignTokens.textPrimary)
                .frame(width: iconCircleSize, height: iconCircleSize)
                .glassEffect(.regular.tint(DesignTokens.glassControlFill), in: .circle)
                .accessibilityHidden(true)

            Text(title)
                .font(.title2.bold())
                .foregroundStyle(DesignTokens.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 8)

            message
                .font(.subheadline)
                .foregroundStyle(DesignTokens.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.top, 12)

            VStack(spacing: 14) {
                actions()
            }
            .padding(.top, 62)
        }
    }
}

extension ScanMessageView where Actions == EmptyView {
    init(title: LocalizedStringKey, systemImage: String, message: Text) {
        self.init(title: title, systemImage: systemImage, message: message) { EmptyView() }
    }
}

/// Red capsule with a white label (Sketch R02c "Open Settings").
struct ScanPrimaryButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(DesignTokens.accentPrimary, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}
