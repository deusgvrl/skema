//
//  ScanGuideSheet.swift
//  Final Challenge App
//
//  Created by Muhammad Dzakki Abdullah on 08/11/26.
//
//  "Before You Scan" sheet (Sketch R02 / Light · R02).
//

import SwiftUI

struct ScanGuideSheet: View {
    let onStartScanning: () -> Void
    let onDontShowAgain: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ScanGuideStepRow(
                    number: 1,
                    title: "Walk slowly around the set",
                    detail: "Hold your iPhone at chest height and circle the subject once."
                )
                ScanGuideStepRow(
                    number: 2,
                    title: "Scan any camera, light & subject",
                    detail: "Keep modifiers, stands and reflectors fully in frame."
                )
                ScanGuideStepRow(
                    number: 3,
                    title: "Press Finish when it’s done.",
                    detail: "End the scan and process the distances are measured from it."
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .top) {
            header
        }
        .safeAreaInset(edge: .bottom) {
            buttons
        }
        .presentationBackground(DesignTokens.sheetBackground)
    }

    private var header: some View {
        HStack {
            Text("Before You Scan")
                .font(.title3.bold())
                .foregroundStyle(DesignTokens.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button("Close", systemImage: "xmark") {
                dismiss()
            }
            .labelStyle(.iconOnly)
            .font(.body.weight(.medium))
            .foregroundStyle(DesignTokens.textPrimary)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
        }
        .padding(.leading, 24)
        .padding(.trailing, 16)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    private var buttons: some View {
        VStack(spacing: 14) {
            Button(action: onStartScanning) {
                Text("Start Scanning")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(DesignTokens.accentPrimary, in: .capsule)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)

            Button("Don’t Show Again", action: onDontShowAgain)
                .font(.subheadline)
                .foregroundStyle(DesignTokens.accentText)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }
}

private struct ScanGuideStepRow: View {
    let number: Int
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    @ScaledMetric(relativeTo: .headline) private var circleSize: CGFloat = 36

    var body: some View {
        HStack(spacing: 16) {
            Text(number, format: .number)
                .font(.headline)
                .foregroundStyle(DesignTokens.textPrimary)
                .frame(width: circleSize, height: circleSize)
                .glassEffect(.regular.tint(DesignTokens.glassControlFill), in: .circle)
                .accessibilityLabel("Step \(number)")

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(DesignTokens.textPrimary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.textSecondary)
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
