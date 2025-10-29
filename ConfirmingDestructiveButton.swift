//
//  ConfirmingDestructiveButton.swift
//  Projector
//
//  Created by Branko Neskov on 28/10/2025.
//
import SwiftUI

/// A destructive button that always asks for confirmation before running `onConfirm`.
struct ConfirmingDestructiveButton<Label: View>: View {
    let title: String            // e.g. "Delete Client"
    let message: String          // e.g. "Deleting is undoable. Are you sure?"
    let confirmText: String      // e.g. "Delete"
    let onConfirm: () -> Void
    @ViewBuilder var label: () -> Label

    @State private var showAlert = false

    var body: some View {
        Button(role: .destructive) { showAlert = true } label: { label() }
            .alert(title, isPresented: $showAlert) {
                Button(confirmText, role: .destructive) { onConfirm() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(message)
            }
    }
}

extension ConfirmingDestructiveButton where Label == Text {
    /// Convenience init when you want a simple text label (common in Menus).
    init(_ labelText: String,
         title: String = "Delete",
         message: String = "Deleting is undoable. Are you sure?",
         confirmText: String = "Delete",
         onConfirm: @escaping () -> Void) {
        self.title = title
        self.message = message
        self.confirmText = confirmText
        self.onConfirm = onConfirm
        self.label = { Text(labelText) }
    }
}
extension ConfirmingDestructiveButton {
    init(title: String,
         onConfirm: @escaping () -> Void,
         @ViewBuilder label: @escaping () -> Label) {
        self.title = title
        self.message = "Deleting is undoable. Are you sure?"
        self.confirmText = "Delete"
        self.onConfirm = onConfirm
        self.label = label
    }
}

