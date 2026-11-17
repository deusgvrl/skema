//
//  SetupRowView.swift
//  Final Challenge App
//
//  Pill row for the "By Client" grouping (Sketch R01b / Light · R01b).
//  The client is the section header, so the row shows the project instead.
//

import SwiftUI

struct SetupRowView: View {
    let setup: Setup

    private var lightsCount: Int {
        setup.nodes.filter { $0.category == .light }.count
    }

    var body: some View {
        HStack(spacing: 12) {
            SetupThumbnail(setup: setup)

            VStack(alignment: .leading, spacing: 2) {
                Text(setup.setupName)
                    .font(.headline)
                    .foregroundStyle(DesignTokens.textPrimary)
                    .lineLimit(1)
                if !setup.project.isEmpty {
                    Text(setup.project)
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .lineLimit(1)
                }
                Text("\(lightsCount) lights · \(setup.createdAt.formatted(.dateTime.day().month(.abbreviated)))")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DesignTokens.textSecondary)
        }
        .padding(12)
        .glassControl(cornerRadius: 24)
    }
}

/// Cover photo, or the setup's initials when there is none (Sketch R01b, R17).
struct SetupThumbnail: View {
    let setup: Setup

    var body: some View {
        CoverImageView(reference: setup.coverImage, pointSize: 60) {
            Text(setup.initials)
                .font(.title3)
                .foregroundStyle(DesignTokens.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemGray5))
        }
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)
    }
}

#Preview {
    SetupRowView(setup: Setup(setupName: "Skincare / soft daylight", client: "Aesop", project: "November catalog"))
        .padding()
}
