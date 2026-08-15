//
//  FinanceWindowView.swift
//  Projector
//
import SwiftUI

struct FinanceWindowView: View {
    @EnvironmentObject private var projects: ProjectStore
    @EnvironmentObject private var invoices: InvoiceStore
    @EnvironmentObject private var payments: PaymentStore

    @State private var selectedProjectID: UUID? = nil
    @State private var projectSearchText: String = ""
    @State private var statusFilter: ProjectStatus = .active
    @State private var editingInvoice: InvoiceEvent? = nil
    @State private var selectedInvoiceID: InvoiceEvent.ID? = nil
    @State private var editingPayment: PaymentEvent? = nil
    @State private var selectedPaymentID: PaymentEvent.ID? = nil

    private var projectList: [Project] {
        let sorted = projects.projects
            .filter { p in
                switch statusFilter {
                case .active:    return p.status == .active
                case .completed: return p.status == .completed
                case .inactive, .cancelled: return p.status == .inactive || p.status == .cancelled
                }
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let q = projectSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return sorted }
        return sorted.filter {
            $0.name.localizedCaseInsensitiveContains(q) ||
            $0.client.localizedCaseInsensitiveContains(q)
        }
    }

    private var selectedProject: Project? {
        guard let id = selectedProjectID else { return nil }
        return projects.projects.first(where: { $0.id == id })
    }

    private var invoicesForSelected: [InvoiceEvent] {
        guard let id = selectedProjectID else { return [] }
        return invoices.invoices
            .filter { $0.projectID == id }
            .sorted { $0.date < $1.date }
    }

    private var paymentsForSelected: [PaymentEvent] {
        guard let id = selectedProjectID else { return [] }
        return payments.payments
            .filter { $0.projectID == id }
            .sorted { $0.date < $1.date }
    }

    private var totalInvoiced: Double  { invoicesForSelected.reduce(0) { $0 + $1.amount } }
    private var totalPaid: Double      { paymentsForSelected.reduce(0) { $0 + $1.amount } }
    private var outstanding: Double    { totalInvoiced - totalPaid }

    /// Returns true if the given invoice has been fully covered by payments (FIFO allocation).
    /// Invoices are assumed to be paid oldest-first against total payments received.
    private func isInvoicePaid(_ invoice: InvoiceEvent) -> Bool {
        let sortedInvoices = invoicesForSelected.sorted { $0.date < $1.date }
        let totalPaid = paymentsForSelected.reduce(0) { $0 + $1.amount }
        var runningTotal = 0.0
        for inv in sortedInvoices {
            runningTotal += inv.amount
            if inv.id == invoice.id {
                return totalPaid >= runningTotal
            }
        }
        return false
    }

    /// Overdue invoices: have a due date in the past AND have not been fully paid
    private var overdueInvoices: [InvoiceEvent] {
        return invoicesForSelected.filter { $0.isOverdue && !isInvoicePaid($0) }
    }

    var body: some View {
        HStack(spacing: 0) {

            // ── Left: project list ────────────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                Text("Projects")
                    .font(.headline)
                    .padding(.top, 10).padding(.horizontal, 10)

                Picker("", selection: $statusFilter) {
                    Text("Active").tag(ProjectStatus.active)
                    Text("Completed").tag(ProjectStatus.completed)
                    Text("Cancelled").tag(ProjectStatus.inactive)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 10)
                .onChange(of: statusFilter) { _, _ in
                    selectedProjectID = projectList.first?.id
                }

                List(selection: $selectedProjectID) {
                    ForEach(projectList) { p in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).textSelection(.enabled)
                            Text(p.client).font(.caption).foregroundColor(.secondary)
                        }
                        .tag(Optional.some(p.id))
                    }
                }
                .searchable(text: $projectSearchText, placement: .automatic, prompt: "Search projects")
            }
            .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)

            Divider()

            // ── Right: detail ─────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 0) {

                // Header
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedProject?.name ?? "Select a project").textSelection(.enabled)
                            .font(.title2).bold()
                        Text(selectedProject?.client ?? "").textSelection(.enabled)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Reload") { invoices.reload(); payments.reload() }
                }
                .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)

                Divider()

                // Totals + overdue warning
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 24) {
                        FinanceKPI(label: "Invoiced",    value: totalInvoiced,  color: .primary)
                        FinanceKPI(label: "Paid",        value: totalPaid,      color: .green)
                        FinanceKPI(label: "Outstanding", value: outstanding,    color: outstanding > 0 ? .orange : .green)
                    }

                    if !overdueInvoices.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text("\(overdueInvoices.count) overdue invoice\(overdueInvoices.count == 1 ? "" : "s") — € \(Finance.currency(overdueInvoices.reduce(0) { $0 + $1.amount }))")
                                .foregroundColor(.red)
                                .font(.callout.weight(.semibold))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)

                Divider()

                // Tables
                HStack(alignment: .top, spacing: 0) {

                    // Invoices
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Invoices").font(.headline)
                            Spacer()
                            Button("Add…") { addInvoice() }
                                .disabled(selectedProjectID == nil)
                        }
                        .padding(.horizontal, 12).padding(.top, 10)

                        Table(invoicesForSelected, selection: $selectedInvoiceID) {
                            TableColumn("Date") { i in
                                Text(i.date.formatted(date: .abbreviated, time: .omitted))
                                    .contentShape(Rectangle())
                                    .onTapGesture(count: 2) { editingInvoice = i }
                            }
                            .width(min: 90, ideal: 100)

                            TableColumn("Due") { i in
                                if let due = i.dueDate {
                                    HStack(spacing: 4) {
                                        if i.isOverdue && !isInvoicePaid(i) {
                                            Image(systemName: "exclamationmark.circle.fill")
                                                .foregroundColor(.red)
                                                .font(.caption)
                                        }
                                        Text(due.formatted(date: .abbreviated, time: .omitted))
                                            .foregroundColor(i.isOverdue && !isInvoicePaid(i) ? .red : .primary)
                                    }
                                } else {
                                    Text("–").foregroundColor(.secondary)
                                }
                            }
                            .width(min: 100, ideal: 110)

                            TableColumn("Invoice #") { i in
                                Text(i.invoiceNumber.isEmpty ? "–" : i.invoiceNumber).textSelection(.enabled)
                            }
                            .width(min: 80, ideal: 90)

                            TableColumn("Amount") { i in
                                Text("€ " + Finance.currency(i.amount)).textSelection(.enabled)
                            }
                            .width(min: 80, ideal: 90)

                            TableColumn("Note") { i in
                                Text(i.note.isEmpty ? "–" : i.note).textSelection(.enabled)
                            }
                        }
                        .onTapGesture(count: 2) {
                            guard let sel = selectedInvoiceID,
                                  let inv = invoicesForSelected.first(where: { $0.id == sel }) else { return }
                            editingInvoice = inv
                        }
                        .frame(minHeight: 200)
                        .padding(.horizontal, 12)
                    }

                    Divider()

                    // Payments
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Payments").font(.headline)
                            Spacer()
                            Button("Add…") { addPayment() }
                                .disabled(selectedProjectID == nil)
                        }
                        .padding(.horizontal, 12).padding(.top, 10)

                        Table(paymentsForSelected, selection: $selectedPaymentID) {
                            TableColumn("Date") { p in
                                Text(p.date.formatted(date: .abbreviated, time: .omitted))
                                    .contentShape(Rectangle())
                                    .onTapGesture(count: 2) { editingPayment = p }
                            }
                            .width(min: 90, ideal: 100)
                            TableColumn("Amount") { p in
                                Text("€ " + Finance.currency(p.amount)).textSelection(.enabled)
                                    .contentShape(Rectangle())
                                    .onTapGesture(count: 2) { editingPayment = p }
                            }
                            .width(min: 80, ideal: 90)
                            TableColumn("Note") { p in
                                Text(p.note.isEmpty ? "–" : p.note).textSelection(.enabled)
                                    .contentShape(Rectangle())
                                    .onTapGesture(count: 2) { editingPayment = p }
                            }
                        }
                        .onTapGesture(count: 2) {
                            guard let sel = selectedPaymentID,
                                  let pay = paymentsForSelected.first(where: { $0.id == sel }) else { return }
                            editingPayment = pay
                        }
                        .frame(minHeight: 200)
                        .padding(.horizontal, 12)
                    }
                }

                Spacer()
            }
            .frame(minWidth: 720)
        }
        .frame(minWidth: 980, minHeight: 560)
        .onAppear {
            if selectedProjectID == nil {
                selectedProjectID = projectList.first?.id
            }
        }
        .sheet(item: $editingInvoice) { inv in
            InvoiceEditorSheet(invoice: inv) { updated in
                invoices.update(updated)
            } onDelete: {
                invoices.delete(inv)
            }
        }
        .sheet(item: $editingPayment) { pay in
            PaymentEditorSheet(payment: pay) { updated in
                payments.update(updated)
            } onDelete: {
                payments.delete(pay)
            }
        }
    }

    private func addInvoice() {
        guard let pid = selectedProjectID else { return }
        let inv = InvoiceEvent(projectID: pid, date: Date(), amount: 0)
        invoices.add(inv)
        editingInvoice = inv
    }

    private func addPayment() {
        guard let pid = selectedProjectID else { return }
        let pay = PaymentEvent(projectID: pid, date: Date(), amount: 0, note: "")
        payments.add(pay)
        editingPayment = pay
    }
}

// MARK: - KPI chip

private struct FinanceKPI: View {
    let label: String
    let value: Double
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Text("€ \(Finance.currency(value))").font(.title3).bold().foregroundColor(color)
        }
        .padding(.vertical, 6).padding(.horizontal, 10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Payment Editor Sheet

struct PaymentEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var date: Date
    @State private var amountText: String
    @State private var note: String
    @State private var showDeleteConfirm = false

    let onSave: (PaymentEvent) -> Void
    let onDelete: () -> Void
    let original: PaymentEvent

    init(payment: PaymentEvent, onSave: @escaping (PaymentEvent) -> Void, onDelete: @escaping () -> Void) {
        self.original = payment
        self.onSave = onSave
        self.onDelete = onDelete

        _date       = State(initialValue: payment.date)
        _amountText = State(initialValue: payment.amount == 0 ? "" : String(format: "%.2f", payment.amount))
        _note       = State(initialValue: payment.note)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Payment").font(.title2).bold()
                .padding(.top, 20).padding(.bottom, 16)

            Divider()

            Form {
                DatePicker("Payment date", selection: $date, displayedComponents: .date)

                TextField("Amount (€)", text: $amountText)
                    .multilineTextAlignment(.trailing)

                TextField("Note", text: $note)
            }
            .padding(.vertical, 12)

            Divider()

            HStack {
                Button("Delete", role: .destructive) {
                    showDeleteConfirm = true
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
                    var updated = original
                    updated.date = date
                    updated.amount = amount
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
        .frame(width: 340)
        .alert("Delete Payment", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                onDelete()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete this payment entry. Are you sure?")
        }
    }
}
