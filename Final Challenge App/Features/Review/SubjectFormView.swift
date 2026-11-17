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
                        TextField("0.0", text: $heightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(DesignTokens.textSecondary)
                            .frame(width: 80)
                        Text("m")
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                }
                .listRowBackground(DesignTokens.formRowBackground)
            }
            .foregroundStyle(DesignTokens.textPrimary)
            .scrollContentBackground(.hidden)
            .background(DesignTokens.sheetBackground)
            .disabled(isReadOnly)
            .navigationTitle("Subject Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isReadOnly ? "Close" : "Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }
                
                if !isReadOnly {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", systemImage: "checkmark") {
                            viewModel.updateSubjectHeight(
                                oldValue: initialSubjectHeight,
                                newValue: heightText,
                                undoManager: undoManager
                            )
                            dismiss()
                        }
                        .buttonStyle(.glassProminent)
                        .tint(DesignTokens.accentPrimary)
                    }
                }
            }
            .onAppear {
                initialSubjectHeight = viewModel.draftSetup.subjectHeight
                heightText = viewModel.draftSetup.subjectHeight
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(DesignTokens.sheetBackground)
    }
}

#Preview {
    SubjectFormView(viewModel: ReviewViewModel(), undoManager: nil, isReadOnly: true)
}
