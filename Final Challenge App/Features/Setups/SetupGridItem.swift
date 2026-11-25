//
//  SetupGridItem.swift
//  Final Challenge App
//
//  One setup in the 2-column Setups grid: square artwork, then the name and the client (By Month) or the project
//  (By Client) (Sketch UT Review A-S02 / A-S03, no card; copy audit 24 Nov).
//

import SwiftUI

struct SetupGridItem: View {
    let setup: Setup
    /// The client or the project, depending on the grouping (`SetupsViewModel.cardSubtitle`).
    /// Empty leaves the line blank.
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SetupArtwork(setup: setup)

            VStack(alignment: .leading, spacing: 1) {
                Text(setup.setupName.isEmpty ? "Untitled Setup" : setup.setupName)
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.textPrimary)
                    .lineLimit(1)
                // Always one line tall, so cards in a row are the same height when one has no client or project.
                Text(subtitle.isEmpty ? " " : subtitle)
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineLimit(1)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// The square cover photo, or the setup's initials when there is none.
private struct SetupArtwork: View {
    let setup: Setup

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                CoverImageView(reference: setup.coverImage, pointSize: 200) {
                    Text(setup.initials)
                        .font(.largeTitle)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(uiColor: .systemGray5))
                }
            }
            .clipShape(.rect(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(DesignTokens.diagramSubjectBorder.opacity(0.5), lineWidth: 0.5)
            )
            .accessibilityHidden(true)
    }
}

/// Cover photo, or the setup's initials when there is none, at list size (Recently Deleted, Sketch R17).
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
    LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())], spacing: 18) {
        SetupGridItem(setup: Setup(setupName: "Perfume / low key"), subtitle: "Maison Noir")
        SetupGridItem(setup: Setup(setupName: "Skincare / soft daylight"), subtitle: "")
    }
    .padding()
}
