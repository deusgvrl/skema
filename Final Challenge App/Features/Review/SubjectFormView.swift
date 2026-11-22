//
//  SubjectFormView.swift
//  Final Challenge App
//
//  Created by Satriya Handha Wibowo on 13/11/26.
//

import SwiftUI

struct SubjectFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: ReviewViewModel
    let undoManager: UndoManager?

    @State private var initialSubjectHeight: String = ""
    @State private var heightText: String = ""
    var isReadOnly: Bool = false

    @Binding var selectedDetent: PresentationDetent

    init(
        viewModel: ReviewViewModel,
        undoManager: UndoManager?,
        isReadOnly: Bool = false,
        selectedDetent: Binding<PresentationDetent> = .constant(.height(76))
    ) {
        self.viewModel = viewModel
        self.undoManager = undoManager
        self.isReadOnly = isReadOnly
        self._selectedDetent = selectedDetent
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(
                    header: FormSectionHeader("Position"),
                    footer: Text(isReadOnly ? "Viewing subject details in read-only mode." : """
                        Set the distance from the floor to the bottom of your subject \
                        (e.g., tabletop height, posing stool, or floor).
                        """)
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.textSecondary)
                ) {
                    HStack {
                        Text("Height from floor")
                        Spacer()
                        TextField("e.g. 0.0", text: $heightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(DesignTokens.textPrimary)
                            .disabled(isReadOnly)
                        Text("m")
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                }
                .listRowBackground(DesignTokens.formRowBackground)
            }
            .foregroundStyle(DesignTokens.textPrimary)
            .background(selectedDetent == .large ? DesignTokens.sheetBackground : Color.clear)
            .scrollContentBackground(.hidden)
            .disabled(isReadOnly)
            .navigationTitle("Subject Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                subjectToolbar
            }
            .onAppear {
                initialSubjectHeight = viewModel.draftSetup.subjectHeight
                heightText = viewModel.draftSetup.subjectHeight
            }
        }
    }

    @ToolbarContentBuilder
    private var subjectToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(isReadOnly ? "Close" : "Cancel", systemImage: "xmark") {
                dismiss()
            }
        }

        if !isReadOnly {
            ToolbarItem(placement: .confirmationAction) {
                if selectedDetent == .large || selectedDetent == .medium {
                    Button("Done", systemImage: "checkmark") {
                        let normalizedHeight = sanitizeDecimalInput(heightText)
                        viewModel.updateSubjectHeight(
                            oldValue: initialSubjectHeight,
                            newValue: normalizedHeight,
                            undoManager: undoManager
                        )
                        dismiss()
                    }
                    .buttonStyle(.glassProminent)
                    .tint(DesignTokens.accentPrimary)
                } else {
                    Button("Edit Details", systemImage: "pencil.and.list.clipboard") {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            selectedDetent = .large
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .tint(DesignTokens.accentPrimary)
                }
            }
        }
    }

    /// Replaces commas with standard dots (e.g. "1,3" -> "1.3") for valid Double parsing.
    private func sanitizeDecimalInput(_ input: String) -> String {
        input.replacingOccurrences(of: ",", with: ".")
    }
}

#Preview {
    SubjectFormView(viewModel: ReviewViewModel(), undoManager: nil, isReadOnly: true)
}
