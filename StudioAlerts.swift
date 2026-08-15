//
//  StudioAlerts.swift
//  Projector
//
//  Computed alerts for the Messages window sidebar.
//  Alerts are never persisted — they are derived live from existing stores
//  and automatically disappear when the underlying condition is resolved.
//

import SwiftUI
import Combine

// MARK: - Alert severity

enum AlertSeverity {
    case critical   // red  — e.g. overdue invoice
    case warning    // orange — e.g. outstanding balance

    var color: Color {
        switch self {
        case .critical: return .red
        case .warning:  return Color.orange
        }
    }

    var icon: String {
        switch self {
        case .critical: return "exclamationmark.triangle.fill"
        case .warning:  return "exclamationmark.circle.fill"
        }
    }
}

// MARK: - Studio Alert

struct StudioAlert: Identifiable {
    let id: UUID = UUID()
    let severity: AlertSeverity
    let title: String
    let detail: String
    let action: AlertAction
}

enum AlertAction {
    case openFinance
    case openProject(UUID)
}

// MARK: - Alert Store

final class AlertStore: ObservableObject {
    static let shared = AlertStore()

    @Published var alerts: [StudioAlert] = []

    private let outstandingBalanceThreshold: Double = 1000.0

    private init() {}

    // Call this whenever financial data might have changed
    func refresh(
        projects: [Project],
        invoices: [InvoiceEvent],
        payments: [PaymentEvent]
    ) {
        var result: [StudioAlert] = []

        for project in projects where project.status == .active {
            let projectInvoices = invoices.filter { $0.projectID == project.id }
            let projectPayments = payments.filter { $0.projectID == project.id }
            let totalInvoiced = projectInvoices.reduce(0) { $0 + $1.amount }
            let totalPaid     = projectPayments.reduce(0) { $0 + $1.amount }
            let outstanding   = totalInvoiced - totalPaid

            // Overdue invoices — critical
            let overdueInvoices = projectInvoices.filter { $0.isOverdue && outstanding > 0 }
            for inv in overdueInvoices {
                let dueDays = Calendar.current.dateComponents([.day], from: inv.dueDate!, to: Date()).day ?? 0
                result.append(StudioAlert(
                    severity: .critical,
                    title: "Overdue Invoice",
                    detail: "\(project.name) · € \(Finance.currency(inv.amount)) · \(dueDays)d overdue",
                    action: .openFinance
                ))
            }

            // Outstanding balance over threshold — warning (only if no overdue invoices already flagged)
            if overdueInvoices.isEmpty && outstanding >= outstandingBalanceThreshold {
                result.append(StudioAlert(
                    severity: .warning,
                    title: "Outstanding Balance",
                    detail: "\(project.name) · € \(Finance.currency(outstanding)) unpaid",
                    action: .openFinance
                ))
            }
        }

        // Sort: critical first, then by detail text
        DispatchQueue.main.async {
            self.alerts = result.sorted {
                if $0.severity == .critical && $1.severity != .critical { return true }
                if $0.severity != .critical && $1.severity == .critical { return false }
                return $0.detail < $1.detail
            }
        }
    }
}
