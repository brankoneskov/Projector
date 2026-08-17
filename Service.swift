//
//  Service.swift
//  Projector
//
//  Created by Branko Neskov on 02/11/2025.
//
import Foundation

struct Service: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var category: String? = nil
    var unitName: String = "unit"              // e.g. "master", "archive", "file"
    var variableUnitName: String? = nil        // e.g. "minute", "TB", "GB"
    var unitPriceEUR: Decimal
    var unitCostEUR: Decimal = 0
    var notes: String = ""

    // User-selected Translation dictionary links and quote placement.
    // Optional fields preserve compatibility with existing Services/*.json.
    var translationEntryID: UUID? = nil
    var unitTranslationEntryID: UUID? = nil
    var variableUnitTranslationEntryID: UUID? = nil
    var defaultBudgetSection: BudgetSection? = nil

    enum CodingKeys: String, CodingKey {
        case id, name, category, unitName, variableUnitName, unitPriceEUR, unitCostEUR, notes
        case translationEntryID, unitTranslationEntryID, variableUnitTranslationEntryID
        case defaultBudgetSection

        // legacy
        case usesMinutes
    }

    init(
        id: UUID = UUID(),
        name: String,
        category: String? = nil,
        unitName: String = "unit",
        variableUnitName: String? = nil,
        unitPriceEUR: Decimal,
        unitCostEUR: Decimal = 0,
        notes: String = "",
        translationEntryID: UUID? = nil,
        unitTranslationEntryID: UUID? = nil,
        variableUnitTranslationEntryID: UUID? = nil,
        defaultBudgetSection: BudgetSection? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.unitName = unitName
        self.variableUnitName = variableUnitName
        self.unitPriceEUR = unitPriceEUR
        self.unitCostEUR = unitCostEUR
        self.notes = notes
        self.translationEntryID = translationEntryID
        self.unitTranslationEntryID = unitTranslationEntryID
        self.variableUnitTranslationEntryID = variableUnitTranslationEntryID
        self.defaultBudgetSection = defaultBudgetSection
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        unitName = try c.decodeIfPresent(String.self, forKey: .unitName) ?? "unit"

        // New field first
        if let v = try c.decodeIfPresent(String.self, forKey: .variableUnitName),
           !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            variableUnitName = v
        } else {
            // Legacy fallback: usesMinutes = true  -> "minute"
            let usesMinutes = try c.decodeIfPresent(Bool.self, forKey: .usesMinutes) ?? false
            variableUnitName = usesMinutes ? "minute" : nil
        }

        unitPriceEUR = try c.decode(Decimal.self, forKey: .unitPriceEUR)
        unitCostEUR = try c.decodeIfPresent(Decimal.self, forKey: .unitCostEUR) ?? 0
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        translationEntryID = try c.decodeIfPresent(UUID.self, forKey: .translationEntryID)
        unitTranslationEntryID = try c.decodeIfPresent(UUID.self, forKey: .unitTranslationEntryID)
        variableUnitTranslationEntryID = try c.decodeIfPresent(UUID.self, forKey: .variableUnitTranslationEntryID)
        defaultBudgetSection = try c.decodeIfPresent(BudgetSection.self, forKey: .defaultBudgetSection)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(category, forKey: .category)
        try c.encode(unitName, forKey: .unitName)
        try c.encodeIfPresent(variableUnitName, forKey: .variableUnitName)
        try c.encode(unitPriceEUR, forKey: .unitPriceEUR)
        try c.encode(unitCostEUR, forKey: .unitCostEUR)
        try c.encode(notes, forKey: .notes)
        try c.encodeIfPresent(translationEntryID, forKey: .translationEntryID)
        try c.encodeIfPresent(unitTranslationEntryID, forKey: .unitTranslationEntryID)
        try c.encodeIfPresent(variableUnitTranslationEntryID, forKey: .variableUnitTranslationEntryID)
        try c.encodeIfPresent(defaultBudgetSection, forKey: .defaultBudgetSection)
    }
}

enum ServiceStatus: String, Codable, CaseIterable, Identifiable {
    case scheduled
    case completed
    case canceled

    var id: String { rawValue }
}

struct ServiceBooking: Identifiable, Hashable, Codable {
    let id: UUID
    var serviceId: UUID
    var projectId: UUID?
    var date: Date
    var status: ServiceStatus
    var variableQuantity: Decimal? = nil
    var notes: String = ""
    var linkedRoomId: UUID? = nil
    var linkedPersonId: UUID? = nil

    enum CodingKeys: String, CodingKey {
        case id, serviceId, projectId, date, status, variableQuantity, notes, linkedRoomId, linkedPersonId

        // legacy
        case minutes
    }

    init(
        id: UUID,
        serviceId: UUID,
        projectId: UUID?,
        date: Date,
        status: ServiceStatus,
        variableQuantity: Decimal? = nil,
        notes: String = "",
        linkedRoomId: UUID? = nil,
        linkedPersonId: UUID? = nil
    ) {
        self.id = id
        self.serviceId = serviceId
        self.projectId = projectId
        self.date = date
        self.status = status
        self.variableQuantity = variableQuantity
        self.notes = notes
        self.linkedRoomId = linkedRoomId
        self.linkedPersonId = linkedPersonId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        id = try c.decode(UUID.self, forKey: .id)
        serviceId = try c.decode(UUID.self, forKey: .serviceId)
        projectId = try c.decodeIfPresent(UUID.self, forKey: .projectId)
        date = try c.decode(Date.self, forKey: .date)
        status = try c.decode(ServiceStatus.self, forKey: .status)

        if let q = try c.decodeIfPresent(Decimal.self, forKey: .variableQuantity) {
            variableQuantity = q
        } else if let oldMinutes = try c.decodeIfPresent(Int.self, forKey: .minutes) {
            variableQuantity = Decimal(oldMinutes)
        } else {
            variableQuantity = nil
        }

        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        linkedRoomId = try c.decodeIfPresent(UUID.self, forKey: .linkedRoomId)
        linkedPersonId = try c.decodeIfPresent(UUID.self, forKey: .linkedPersonId)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(serviceId, forKey: .serviceId)
        try c.encodeIfPresent(projectId, forKey: .projectId)
        try c.encode(date, forKey: .date)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(variableQuantity, forKey: .variableQuantity)
        try c.encode(notes, forKey: .notes)
        try c.encodeIfPresent(linkedRoomId, forKey: .linkedRoomId)
        try c.encodeIfPresent(linkedPersonId, forKey: .linkedPersonId)
    }
}
