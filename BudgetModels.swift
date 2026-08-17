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
    case soundEditing
    case ADRRecordingEditing
    case FoleyRecordingEditing
    case soundMixing
    case ColorGrading
    case deliveries
    case management
    case others

    var label: String {
        switch self {
        case .dailies:                 return "Dailies"
        case .pictureEditing:          return "Picture Editing"
        case .soundEditing:            return "Sound Editing"
        case .ADRRecordingEditing:     return "ADR Recording&Editing"
        case .FoleyRecordingEditing:   return "Foley Recording&Editing"
        case .soundMixing:             return "Sound Mixing"
        case .ColorGrading:            return "Color Grading"
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
    var linkedServiceID: UUID? = nil   // optional pointer to a catalog Service
    var translationEntryID: UUID? = nil

    // Quantity + pricing (snapshotted at creation time)
    var unit: String = "h"          // hours by default; can be "day", "flat", etc.
    var unitTranslationEntryID: UUID? = nil
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
                              translationEntryID: c.translationEntryID,
                              unit: "h",
                              unitTranslationEntryID: c.unitTranslationEntryID,
                              quantity: hours,
                              rateSell: c.sellRatePerHour,
                              rateBuy:  c.buyCostPerHour,
                              isActive: true,
                              notes: "")
        line.section = c.defaultBudgetSection ?? .others
        return line
    }

    static func from(personCategory c: PersonCategory, hours: Double = 0) -> BudgetLine {
        var line = BudgetLine(kind: .personCategory,
                              name: c.name,
                              categoryID: c.id,
                              translationEntryID: c.translationEntryID,
                              unit: "h",
                              unitTranslationEntryID: c.unitTranslationEntryID,
                              quantity: hours,
                              rateSell: c.sellRatePerHour,
                              rateBuy:  c.buyCostPerHour,
                              isActive: true,
                              notes: "")
        line.section = c.defaultBudgetSection ?? .others
        return line
    }
}

// MARK: - Project Budget (one per project, typically)
struct ProjectBudget: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var projectID: UUID               // links to Project.id
    var title: String = "Budget"
    var attentionTo: String? = nil    // Name of the person this budget is directed to
    var lines: [BudgetLine] = []

    // ✅ NEW: General notes for PDF/Print export (safe for older JSON)
    var generalNotes: String = ""

    // Commercial knobs
    var discountPercent: Double = 0      // e.g. 10 for 10%
    var contingencyPercent: Double = 0   // e.g. 5 for 5%

    /// Optional agreed final price (internal note only, never exported)
    var priceAgreement: Double? = nil

    // State
    var state: BudgetState = .draft
    /// Assigned when a Draft is promoted to a Quote.
    /// Example: "2025-033-MM"
    var quoteNumber: String? = nil

    // Audit
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var exportLanguage: ExportLanguage = .english

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

    // MARK: - Convenience init (keeps your createBudget(...) calls working)
    init(
        id: UUID = UUID(),
        projectID: UUID,
        title: String = "Budget",
        attentionTo: String? = nil,
        lines: [BudgetLine] = [],
        generalNotes: String = "",
        discountPercent: Double = 0,
        contingencyPercent: Double = 0,
        priceAgreement: Double? = nil,
        state: BudgetState = .draft,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        exportLanguage: ExportLanguage = .english
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.attentionTo = attentionTo
        self.lines = lines
        self.generalNotes = generalNotes
        self.discountPercent = discountPercent
        self.contingencyPercent = contingencyPercent
        self.priceAgreement = priceAgreement
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.exportLanguage = exportLanguage
    }

    // MARK: - Codable (backwards compatible)
    enum CodingKeys: String, CodingKey {
        case id, projectID, title, attentionTo, lines
        case generalNotes
        case discountPercent, contingencyPercent, priceAgreement
        case state, quoteNumber, createdAt, updatedAt
        case exportLanguage
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        projectID = try c.decode(UUID.self, forKey: .projectID)

        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Budget"
        attentionTo = try c.decodeIfPresent(String.self, forKey: .attentionTo)

        lines = try c.decodeIfPresent([BudgetLine].self, forKey: .lines) ?? []
        generalNotes = try c.decodeIfPresent(String.self, forKey: .generalNotes) ?? ""

        discountPercent = try c.decodeIfPresent(Double.self, forKey: .discountPercent) ?? 0
        contingencyPercent = try c.decodeIfPresent(Double.self, forKey: .contingencyPercent) ?? 0
        priceAgreement = try c.decodeIfPresent(Double.self, forKey: .priceAgreement)

        state = try c.decodeIfPresent(BudgetState.self, forKey: .state) ?? .draft
        quoteNumber = try c.decodeIfPresent(String.self, forKey: .quoteNumber)

        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()

        exportLanguage = try c.decodeIfPresent(ExportLanguage.self, forKey: .exportLanguage) ?? .english
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)

        try c.encode(id, forKey: .id)
        try c.encode(projectID, forKey: .projectID)
        try c.encode(title, forKey: .title)
        try c.encode(attentionTo, forKey: .attentionTo)
        try c.encode(lines, forKey: .lines)
        try c.encode(generalNotes, forKey: .generalNotes)

        try c.encode(discountPercent, forKey: .discountPercent)
        try c.encode(contingencyPercent, forKey: .contingencyPercent)
        try c.encode(priceAgreement, forKey: .priceAgreement)

        try c.encode(state, forKey: .state)
        try c.encode(quoteNumber, forKey: .quoteNumber)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)

        try c.encode(exportLanguage, forKey: .exportLanguage)
    }
}

enum ExportLanguage: String, Codable, CaseIterable, Identifiable {
    case english    = "en"
    case portuguese = "pt"
    case french     = "fr"
    case german     = "de"
    case spanish    = "es"
    case italian    = "it"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .english:    return "EN"
        case .portuguese: return "PT"
        case .french:     return "FR"
        case .german:     return "DE"
        case .spanish:    return "ES"
        case .italian:    return "IT"
        }
    }

    var fullName: String {
        switch self {
        case .english:    return "English"
        case .portuguese: return "Portuguese"
        case .french:     return "French"
        case .german:     return "German"
        case .spanish:    return "Spanish"
        case .italian:    return "Italian"
        }
    }
}

// MARK: - Store
final class BudgetStore: ObservableObject {
    @Published private(set) var budgets: [ProjectBudget] = []

    static let shared = BudgetStore()
    private init() { load() }

    // Root folder is whatever DataPaths.file("budgets.json") points to (same root as other JSON files)
    private var rootFolderURL: URL { DataPaths.file("budgets.json").deletingLastPathComponent() }

    // New v2 structure:
    //   <root>/Budgets/<budgetID>.json
    //   <root>/Meta/...
    private var budgetsFolderURL: URL { rootFolderURL.appendingPathComponent("Budgets", isDirectory: true) }
    private var metaFolderURL: URL { rootFolderURL.appendingPathComponent("Meta", isDirectory: true) }

    // Legacy (single file) kept only for optional import fallback
    private var legacyFileURL: URL { DataPaths.file("budgets.json") }

    private func ensureFoldersExist() {
        do {
            try FileManager.default.createDirectory(at: budgetsFolderURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: metaFolderURL, withIntermediateDirectories: true)
        } catch {
            print("⚠️ BudgetStore: failed creating folders: \(error)")
        }
    }

    func reload() { load() }

    // MARK: - Per-record Persistence

    private func budgetFileURL(for budgetID: UUID) -> URL {
        budgetsFolderURL.appendingPathComponent("\(budgetID.uuidString).json")
    }

    private func load() {
        ensureFoldersExist()

        do {
            let fm = FileManager.default
            let urls = try fm.contentsOfDirectory(
                at: budgetsFolderURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            let jsonFiles = urls.filter { $0.pathExtension.lowercased() == "json" }

            // If there are per-record files, prefer them.
            if !jsonFiles.isEmpty {
                var loaded: [ProjectBudget] = []
                loaded.reserveCapacity(jsonFiles.count)

                for url in jsonFiles {
                    do {
                        let data = try Data(contentsOf: url)
                        let b = try JSONDecoder().decode(ProjectBudget.self, from: data)
                        loaded.append(b)
                    } catch {
                        // Do NOT fail the whole load if one budget file is bad.
                        print("⚠️ Failed to read budget file \(url.lastPathComponent): \(error)")
                    }
                }

                self.budgets = loaded
                print("📂 Loaded \(budgets.count) budgets from per-record folder \(budgetsFolderURL.path)")
                return
            }

            // Optional fallback: if no per-record budgets exist yet, try legacy budgets.json
            if FileManager.default.fileExists(atPath: legacyFileURL.path) {
                let data = try Data(contentsOf: legacyFileURL)
                let decoded = try JSONDecoder().decode([ProjectBudget].self, from: data)

                self.budgets = decoded
                print("📂 Loaded \(budgets.count) budgets from legacy file \(legacyFileURL.path)")

                // Immediately materialize per-record files so we stop using the legacy file.
                for b in decoded {
                    writeBudgetToDisk(b)
                }
                return
            }

            // Nothing to load
            self.budgets = []
        } catch {
            print("⚠️ BudgetStore load error: \(error)")
            // Keep current in-memory budgets if something goes wrong
        }
    }

    private func writeBudgetToDisk(_ budget: ProjectBudget) {
        ensureFoldersExist()

        do {
            let data = try JSONEncoder().encode(budget)
            try data.write(to: budgetFileURL(for: budget.id), options: [.atomic])
        } catch {
            print("⚠️ BudgetStore writeBudgetToDisk error: \(error)")
        }
    }

    private func deleteBudgetFromDisk(_ budgetID: UUID) {
        ensureFoldersExist()

        let url = budgetFileURL(for: budgetID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            print("⚠️ BudgetStore deleteBudgetFromDisk error: \(error)")
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
        writeBudgetToDisk(b)
        return b
    }


    /// Convenience: create by projectID with explicit title (no auto numbering)
    func createBudget(projectID: UUID, title: String = "Budget") -> ProjectBudget {
        var b = ProjectBudget(projectID: projectID, title: title)
        b.createdAt = Date(); b.updatedAt = Date(); b.state = .draft

        budgets.append(b)
        writeBudgetToDisk(b)
        return b
    }

    /// Mark a single budget as “Quote” for its project.
    /// IMPORTANT: does NOT demote other quotes anymore (allows multiple quotes).
    func markAsQuote(_ budgetID: UUID, initials: String) {
        guard let idx = budgets.firstIndex(where: { $0.id == budgetID }) else { return }

        // Assign quote number once
        if budgets[idx].quoteNumber == nil {
            let year = Calendar.current.component(.year, from: Date())
            do {
                budgets[idx].quoteNumber = try QuoteNumbering.reserveNextQuoteNumber(
                    year: year,
                    initials: initials
                )
            } catch {
                print("⚠️ Quote numbering failed:", error.localizedDescription)
                return
            }
        }

        budgets[idx].state = .quote
        budgets[idx].updatedAt = Date()
        writeBudgetToDisk(budgets[idx])
    }

    /// Duplicate any budget (draft/quote/active) into a NEW editable Draft.
    /// - Clears quoteNumber
    /// - Sets state to .draft
    /// - New id + new timestamps
    func duplicateAsDraft(_ budgetID: UUID) -> ProjectBudget? {
        guard let original = budgets.first(where: { $0.id == budgetID }) else { return nil }

        var copy = original
        copy.id = UUID()
        copy.state = .draft
        copy.quoteNumber = nil
        copy.createdAt = Date()
        copy.updatedAt = Date()

        // Title: keep it simple and readable
        let base = original.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty {
            copy.title = "Budget Copy"
        } else if base.localizedCaseInsensitiveContains("copy") {
            copy.title = base
        } else {
            copy.title = "\(base) — Copy"
        }

        budgets.append(copy)
        writeBudgetToDisk(copy)
        return copy
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
            writeBudgetToDisk(budgets[i])
        }
    }


    /// Optional: unlock back to draft
    func unlock(_ budgetID: UUID) {
        guard let idx = budgets.firstIndex(where: { $0.id == budgetID }) else { return }
        budgets[idx].state = .draft
        budgets[idx].updatedAt = Date()
        writeBudgetToDisk(budgets[idx])
    }


    // MARK: CRUD-like helpers
    func budgets(for projectID: UUID) -> [ProjectBudget] {
        budgets.filter { $0.projectID == projectID }
    }

    func firstBudget(for projectID: UUID) -> ProjectBudget? {
        budgets.first { $0.projectID == projectID }
    }

    func upsert(_ budget: ProjectBudget) {
        // Quotes/locked budgets are immutable in Projector.
        // Only explicit state transition methods (markAsQuote / markAsActive / unlock) are allowed to write them.
        guard budget.state == .draft else {
            print("ℹ️ BudgetStore.upsert ignored (immutable state): \(budget.id) state=\(budget.state)")
            return
        }

        if let i = budgets.firstIndex(where: { $0.id == budget.id }) {
            var copy = budget
            copy.updatedAt = Date()
            budgets[i] = copy
            writeBudgetToDisk(copy)
        } else {
            var copy = budget
            copy.createdAt = Date()
            copy.updatedAt = Date()
            budgets.append(copy)
            writeBudgetToDisk(copy)
        }
    }



    func delete(_ budget: ProjectBudget) {
        budgets.removeAll { $0.id == budget.id }
        deleteBudgetFromDisk(budget.id)
    }

    // MARK: Line helpers on a given budget
    func addLine(to budgetID: UUID, line: BudgetLine) {
        guard let i = budgets.firstIndex(where: { $0.id == budgetID }) else { return }
        guard budgets[i].state == .draft else { return }

        budgets[i].upsert(line)
        writeBudgetToDisk(budgets[i])
    }


    func removeLine(from budgetID: UUID, lineID: UUID) {
        guard let i = budgets.firstIndex(where: { $0.id == budgetID }) else { return }
        guard budgets[i].state == .draft else { return }

        budgets[i].removeLine(lineID)
        writeBudgetToDisk(budgets[i])
    }

}
extension BudgetLine {
    static func from(service s: Service, quantity: Double = 1) -> BudgetLine {
        var line = BudgetLine(
            kind: .misc,
            name: s.name,
            categoryID: nil,
            linkedServiceID: s.id,
            translationEntryID: s.translationEntryID,
            unit: s.unitName,
            unitTranslationEntryID: s.unitTranslationEntryID,
            quantity: quantity,
            rateSell: NSDecimalNumber(decimal: s.unitPriceEUR).doubleValue, // ← convert
            rateBuy: 0,
            isActive: true,
            notes: s.notes
        )
        line.section = s.defaultBudgetSection ?? .others
        return line
    }
}

