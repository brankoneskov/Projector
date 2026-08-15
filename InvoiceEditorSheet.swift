//
//  InvoiceEditorSheet.swift
//  Projector
//
import SwiftUI

struct InvoiceEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var date: Date
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var amountText: String
    @State private var invoiceNumber: String
    @State private var note: String
    @State private var showDeleteConfirm = false

    let onSave: (InvoiceEvent) -> Void
    let onDelete: (() -> Void)?
    let original: InvoiceEvent

    init(invoice: InvoiceEvent, onSave: @escaping (InvoiceEvent) -> Void, onDelete: (() -> Void)? = nil) {
        self.original = invoice
        self.onSave = onSave
        self.onDelete = onDelete

        _date          = State(initialValue: invoice.date)
        _hasDueDate    = State(initialValue: invoice.dueDate != nil)
        _dueDate       = State(initialValue: invoice.dueDate ?? Calendar.current.date(byAdding: .day, value: 30, to: invoice.date) ?? invoice.date)
        _amountText    = State(initialValue: invoice.amount == 0 ? "" : String(format: "%.2f", invoice.amount))
        _invoiceNumber = State(initialValue: invoice.invoiceNumber)
        _note          = State(initialValue: invoice.note)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Invoice").font(.title2).bold()
                .padding(.top, 20).padding(.bottom, 16)

            Divider()

            Form {
                DatePicker("Invoice date", selection: $date, displayedComponents: .date)

                HStack {
                    Toggle("Due date", isOn: $hasDueDate)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    if hasDueDate {
                        DatePicker("", selection: $dueDate, displayedComponents: .date)
                            .labelsHidden()
                    }
                }

                TextField("Invoice number", text: $invoiceNumber)

                TextField("Amount (€)", text: $amountText)
                    .multilineTextAlignment(.trailing)

                TextField("Note", text: $note)
            }
            .padding(.vertical, 12)

            Divider()

            HStack {
                if onDelete != nil {
                    Button("Delete", role: .destructive) { showDeleteConfirm = true }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
                    var updated = original
                    updated.date = date
                    updated.dueDate = hasDueDate ? dueDate : nil
                    updated.amount = amount
                    updated.invoiceNumber = invoiceNumber
                    updated.note = note
                    onSave(updated)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 380)
        .alert("Delete Invoice", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                onDelete?()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete this invoice entry. Are you sure?")
        }
    }
}
