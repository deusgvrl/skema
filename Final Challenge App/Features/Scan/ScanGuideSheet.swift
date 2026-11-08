//
//  ScanGuideSheet.swift
//  Final Challenge App
//
//  Created by Muhammad Dzakki Abdullah on 08/11/26.
//

import SwiftUI

struct ScanGuideSheet: View {
    let onStartScanning: () -> Void
    let onDontShowAgain: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ScanGuideStepRow(
                        number: 1,
                        title: "Walk slowly around the set",
                        detail: "Hold your iPhone at chest height and circle the subject once."
                    )
                    ScanGuideStepRow(
                        number: 2,
                        title: "Show every light and stand",
                        detail: "Keep modifiers, stands and reflectors fully in frame."
                    )
                    ScanGuideStepRow(
                        number: 3,
                        title: "Finish at the camera position",
                        detail: "End where the camera stands so distances are measured from it."
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom) {
                buttons
            }
            .navigationTitle("Before You Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) {
                        dismiss()
                    }
                }
            }
        }
    }

    private var buttons: some View {
        VStack(spacing: 16) {
            Button(action: onStartScanning) {
                Text("Start Scanning")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.extraLarge)

            Button("Don’t Show Again", action: onDontShowAgain)
                .font(.subheadline)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }
}

private struct ScanGuideStepRow: View {
    let number: Int
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    @ScaledMetric(relativeTo: .headline) private var circleSize: CGFloat = 32

    var body: some View {
        HStack(spacing: 16) {
            Text(number, format: .number)
                .font(.headline)
                .foregroundStyle(Color(.systemBackground))
                .frame(width: circleSize, height: circleSize)
                .background(Color(.label), in: .circle)
                .accessibilityLabel("Step \(number)")

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Color(.secondaryLabel))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            ScanGuideSheet(onStartScanning: {}, onDontShowAgain: {})
                .presentationDetents([.medium, .large])
        }
}
