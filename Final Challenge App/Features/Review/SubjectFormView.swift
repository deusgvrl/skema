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
                    header: Text("Position"),
                    footer: Text(isReadOnly ? "Viewing subject details in read-only mode." : "Set the distance from the floor to the bottom of your subject (e.g., tabletop height, posing stool, or floor).")
                ) {
                    HStack {
                        Text("Height from floor")
                        Spacer()
                        TextField("0.0", text: $heightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("m")
                            .foregroundStyle(.secondary)
                    }
                }
            }
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
    }
}

#Preview {
    SubjectFormView(viewModel: ReviewViewModel(), undoManager: nil, isReadOnly: true)
}
