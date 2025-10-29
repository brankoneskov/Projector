//
//  BudgetModels.swift
//  Projector
//
//  Created by Branko Neskov on 26/10/2025.
//

import Foundation
import Combine

// MARK: - Budget line kind
enum BudgetLineKind: String, Codable, CaseIterable, Hashable {
    case roomCategory   // from RoomCategory.id
    case personCategory // from PersonCategory.id
    case misc           // free-form line (no category source)
}
enum BudgetSection: String, Codable, CaseIterable, Hashable {
    case dailies
    case pictureEditing
    case soundRecordingEditing
    case soundMixing
    case deliveries
    case management
    case others

    var label: String {
        switch self {
        case .dailies:                 return "Dailies"
        case .pictureEditing:          return "Picture Editing"
        case .soundRecordingEditing:   return "Sound Recording & Editing"
        case .soundMixing:             return "Sound Mixing"
        case .deliveries:              return "Deliveries"
        case .management:              return "Management"
        case .others:                  return "Others"
        }
    }
}

// MARK: - Budget state
enum BudgetState: String, Codable, CaseIterable, Hashable {
    case draft           // editable
    case quote           // editable (marked as client's quote)
    case activeLocked    // final / locked (read-only)
}

// MARK: - Budget line (one row in the quote)
struct BudgetLine: Identifiable, Codable, Hashable {
    var id: UUID = UUID()

    // Classification
    var kind: BudgetLineKind
    var name: String                // e.g. "TV Mix" or "ADR Mixer" or "Misc fee"
    var categoryID: UUID? = nil     // when kind is roomCategory / personCategory

    // Quantity + pricing (snapshotted at creation time)
    var unit: String = "h"          // hours by default; can be "day", "flat", etc.
    var quantity: Double = 0        // e.g. 8.0 hours, 3.0 days
    var rateSell: Double = 0        // €/unit (sell)
    var rateBuy: Double = 0         // €/unit (cost)

    // Visibility / notes
    var isActive: Bool = true
    var notes: String = ""

    // Convenience computed amounts
    var amountSell: Double { quantity * rateSell }
    var amountCost: Double { quantity * rateBuy }
    var section: BudgetSection = .others

    // MARK: Builders to snapshot rates from categories
    static func from(roomCategory c: RoomCategory, hours: Double = 0) -> BudgetLine {
        var line = BudgetLine(kind: .roomCategory,
                              name: c.name,
                              categoryID: c.id,
                              unit: "h",
                              quantity: hours,
                              rateSell: c.sellRatePerHour,
                              rateBuy:  c.buyCostPerHour,
                              isActive: true,
                              notes: "")
        // Choose a default section by name heuristics (adjust if desired)
        let n = c.name.lowercased()
        if n.contains("mix") { line.section = .soundMixing }
        else if n.contains("edit") { line.section = .soundRecordingEditing }
        else { line.section = .others }
        return line
    }

    static func from(personCategory c: PersonCategory, hours: Double = 0) -> BudgetLine {
        var line = BudgetLine(kind: .personCategory,
                              name: c.name,
                              categoryID: c.id,
                              unit: "h",
                              quantity: hours,
                              rateSell: c.sellRatePerHour,
                              rateBuy:  c.buyCostPerHour,
                              isActive: true,
                              notes: "")
        let n = c.name.lowercased()
        if n.contains("editor") || n.contains("edit") { line.section = .pictureEditing }
        else if n.contains("mixer") || n.contains("mix") { line.section = .soundMixing }
        else { line.section = .others }
        return line
    }
}

// MARK: - Project Budget (one per project, typically)
struct ProjectBudget: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var projectID: UUID               // links to Project.id
    var title: String = "Budget"
    var lines: [BudgetLine] = []

    // Commercial knobs
    var discountPercent: Double = 0      // e.g. 10 for 10%
    var contingencyPercent: Double = 0   // e.g. 5 for 5%

    // State
    var state: BudgetState = .draft

    // Audit
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // MARK: Totals
    var subtotalSell: Double { lines.filter { $0.isActive }.reduce(0) { $0 + $1.amountSell } }
    var subtotalCost: Double { lines.filter { $0.isActive }.reduce(0) { $0 + $1.amountCost } }

    var discountValue: Double { subtotalSell * (discountPercent / 100.0) }
    var withDiscountSell: Double { subtotalSell - discountValue }

    var contingencyValue: Double { withDiscountSell * (contingencyPercent / 100.0) }
    var totalSell: Double { withDiscountSell + contingencyValue }

    var totalCost: Double { subtotalCost } // contingency usually applied to sell only
    var margin: Double { totalSell - totalCost }
    var marginPercent: Double { totalSell > 0 ? (margin / totalSell * 100.0) : 0 }

    // MARK: Mutating helpers
    mutating func upsert(_ line: BudgetLine) {
        if let idx = lines.firstIndex(where: { $0.id == line.id }) {
            lines[idx] = line
        } else {
            lines.append(line)
        }
        updatedAt = Date()
    }

    mutating func removeLine(_ id: UUID) {
        lines.removeAll { $0.id == id }
        updatedAt = Date()
    }

    mutating func sortByName() {
        lines.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Store
final class BudgetStore: ObservableObject {
    @Published var budgets: [ProjectBudget] = [] { didSet { save() } }

    static let shared = BudgetStore()
    private init() { load() }

    private var fileURL: URL { DataPaths.file("budgets.json") }

    // MARK: Persistence
    private func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode([ProjectBudget].self, from: data)
            self.budgets = decoded
        } catch {
            self.budgets = []
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(budgets)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("BudgetStore save error: \(error)")
        }
    }
}

// MARK: - Helpers and Actions
extension BudgetStore {
    /// Auto-title: "<Project Name> Budget 01/02/…"
    func nextAutoTitle(for project: Project) -> String {
        let existing = budgets(for: project.id).count + 1
        return "\(project.name) Budget \(String(format: "%02d", existing))"
    }

    /// Create with auto title (if nil passed)
    func createBudget(project: Project, title: String? = nil) -> ProjectBudget {
        let t = (title?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? nextAutoTitle(for: project)

        var b = ProjectBudget(projectID: project.id, title: t, lines: [])
        b.createdAt = Date(); b.updatedAt = Date(); b.state = .draft
        budgets.append(b)
        return b
    }

    /// Convenience: create by projectID with explicit title (no auto numbering)
    func createBudget(projectID: UUID, title: String = "Budget") -> ProjectBudget {
        var b = ProjectBudget(projectID: projectID, title: title)
        b.createdAt = Date(); b.updatedAt = Date(); b.state = .draft
        budgets.append(b)
        return b
    }

    /// Mark a single budget as the “Quote” for its project (others become .draft if they were .quote)
    func markAsQuote(_ budgetID: UUID) {
        guard let idx = budgets.firstIndex(where: { $0.id == budgetID }) else { return }
        let pid = budgets[idx].projectID
        for i in budgets.indices where budgets[i].projectID == pid {
            if budgets[i].id == budgetID {
                budgets[i].state = .quote
            } else if budgets[i].state == .quote {
                budgets[i].state = .draft
            }
            budgets[i].updatedAt = Date()
        }
    }

    /// Mark as Active (locked). Only one activeLocked per project.
    func markAsActive(_ budgetID: UUID) {
        guard let idx = budgets.firstIndex(where: { $0.id == budgetID }) else { return }
        let pid = budgets[idx].projectID
        for i in budgets.indices where budgets[i].projectID == pid {
            if budgets[i].id == budgetID {
                budgets[i].state = .activeLocked
            } else if budgets[i].state == .activeLocked {
                budgets[i].state = .draft
            }
            budgets[i].updatedAt = Date()
        }
    }

    /// Optional: unlock back to draft
    func unlock(_ budgetID: UUID) {
        guard let idx = budgets.firstIndex(where: { $0.id == budgetID }) else { return }
        budgets[idx].state = .draft
        budgets[idx].updatedAt = Date()
    }

    // MARK: CRUD-like helpers
    func budgets(for projectID: UUID) -> [ProjectBudget] {
        budgets.filter { $0.projectID == projectID }
    }

    func firstBudget(for projectID: UUID) -> ProjectBudget? {
        budgets.first { $0.projectID == projectID }
    }

    func upsert(_ budget: ProjectBudget) {
        if let i = budgets.firstIndex(where: { $0.id == budget.id }) {
            var copy = budget
            copy.updatedAt = Date()
            budgets[i] = copy
        } else {
            var copy = budget
            copy.createdAt = Date()
            copy.updatedAt = Date()
            budgets.append(copy)
        }
    }

    func delete(_ budget: ProjectBudget) {
        budgets.removeAll { $0.id == budget.id }
    }

    // MARK: Line helpers on a given budget
    func addLine(to budgetID: UUID, line: BudgetLine) {
        guard let i = budgets.firstIndex(where: { $0.id == budgetID }) else { return }
        budgets[i].upsert(line)
    }

    func removeLine(from budgetID: UUID, lineID: UUID) {
        guard let i = budgets.firstIndex(where: { $0.id == budgetID }) else { return }
        budgets[i].removeLine(lineID)
    }
}
