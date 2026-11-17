//
//  FormSectionHeader.swift
//  Final Challenge App
//

import SwiftUI

/// Small grey section header over grouped rows (Sketch R06 "Equipment", "Light Settings").
struct FormSectionHeader: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(DesignTokens.textSecondary)
            .textCase(nil)
    }
}
