//
//  FinanceModels.swift
//  Projector
//
import Foundation

// MARK: - Shared helpers

fileprivate func clampFinite(_ x: Double) -> Double {
    guard x.isFinite else { return 0 }
    return x
}

// MARK: - Invoice

struct InvoiceEvent: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var projectID: UUID
    var date: Date
    var dueDate: Date? = nil       // nil = no due date set
    var amount: Double
    var invoiceNumber: String = ""
    var note: String = ""

    /// True if a due date is set and it is in the past.
    /// Does NOT consider payments — callers must check isPaid or outstanding balance themselves.
    var isOverdue: Bool {
        guard let due = dueDate else { return false }
        return due < Calendar.current.startOfDay(for: Date())
    }

    init(id: UUID = UUID(), projectID: UUID, date: Date, dueDate: Date? = nil,
         amount: Double, invoiceNumber: String = "", note: String = "") {
        self.id = id
        self.projectID = projectID
        self.date = date
        self.dueDate = dueDate
        self.amount = clampFinite(amount)
        self.invoiceNumber = invoiceNumber
        self.note = note
    }
}

// MARK: - Payment

struct PaymentEvent: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var projectID: UUID
    var date: Date
    var amount: Double
    var note: String = ""

    init(id: UUID = UUID(), projectID: UUID, date: Date, amount: Double, note: String = "") {
        self.id = id
        self.projectID = projectID
        self.date = date
        self.amount = clampFinite(amount)
        self.note = note
    }
}
