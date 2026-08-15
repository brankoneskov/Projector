//
// CoreModels.swift
// Projector
//

import Foundation

// MARK: - Lossy decoding helpers

extension KeyedDecodingContainer {
    func lossyString(_ key: Key) -> String {
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return String(i) }
        if let d = try? decodeIfPresent(Double.self, forKey: key) {
            return String(format: "%.4f", d).replacingOccurrences(of: ",", with: ".")
        }
        if let b = try? decodeIfPresent(Bool.self, forKey: key) { return b ? "true" : "false" }
        return ""
    }

    func lossyBool(_ key: Key, default def: Bool) -> Bool {
        if let b = try? decodeIfPresent(Bool.self, forKey: key) { return b }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i != 0 }
        if let s = try? decodeIfPresent(String.self, forKey: key) {
            let v = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["true", "yes", "y", "1"].contains(v) { return true }
            if ["false", "no", "n", "0"].contains(v) { return false }
            return def
        }
        return def
    }

    func lossyDoubleOptional(_ key: Key) -> Double? {
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return d }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return Double(i) }
        if let s = try? decodeIfPresent(String.self, forKey: key) {
            let normalized = s.replacingOccurrences(of: ",", with: ".")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Double(normalized)
        }
        return nil
    }
}

// MARK: - Project

// MARK: - Project Status

enum ProjectStatus: String, Codable, CaseIterable {
    case active    = "active"
    case completed = "completed"
    case inactive  = "inactive"   // kept as "inactive" in JSON for backward compatibility
    case cancelled = "cancelled"

    var label: String {
        switch self {
        case .active:    return "Active"
        case .completed: return "Completed"
        case .inactive:  return "Cancelled"  // display as Cancelled
        case .cancelled: return "Cancelled"
        }
    }
}

struct Project: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var client: String
    var status: ProjectStatus = .active
    var notes: String = ""
    var address: String? = nil
    var email: String = ""
    var phone: String = ""

    /// Optional project-level discount percentage (e.g. 10 for 10%).
    var discountPercent: Double? = nil

    /// Backward-compatible computed property — existing code using isActive still works.
    var isActive: Bool {
        get { status == .active }
        set { status = newValue ? .active : .completed }
    }

    // MARK: - Codable (backward compatible with old isActive: Bool format)
    enum CodingKeys: String, CodingKey { case id, name, client, status, isActive, notes, address, email, phone, discountPercent }

    init(id: UUID = UUID(), name: String, client: String = "", status: ProjectStatus = .active,
         notes: String = "", address: String? = nil, email: String = "", phone: String = "",
         discountPercent: Double? = nil) {
        self.id = id; self.name = name; self.client = client; self.status = status
        self.notes = notes; self.address = address; self.email = email; self.phone = phone
        self.discountPercent = discountPercent
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decodeIfPresent(UUID.self,   forKey: .id)             ?? UUID()
        name           = try c.decode(String.self,          forKey: .name)
        client         = try c.decodeIfPresent(String.self, forKey: .client)         ?? ""
        notes          = try c.decodeIfPresent(String.self, forKey: .notes)          ?? ""
        address        = try c.decodeIfPresent(String.self, forKey: .address)
        email          = try c.decodeIfPresent(String.self, forKey: .email)          ?? ""
        phone          = try c.decodeIfPresent(String.self, forKey: .phone)          ?? ""
        discountPercent = try c.decodeIfPresent(Double.self, forKey: .discountPercent)
        // Prefer new status field; fall back to legacy isActive bool
        if let s = try c.decodeIfPresent(ProjectStatus.self, forKey: .status) {
            status = s
        } else {
            let legacy = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
            status = legacy ? .active : .completed
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,              forKey: .id)
        try c.encode(name,            forKey: .name)
        try c.encode(client,          forKey: .client)
        try c.encode(status,          forKey: .status)
        try c.encode(notes,           forKey: .notes)
        try c.encodeIfPresent(address, forKey: .address)
        try c.encode(email,           forKey: .email)
        try c.encode(phone,           forKey: .phone)
        try c.encodeIfPresent(discountPercent, forKey: .discountPercent)
    }
}

// MARK: - Person

struct Person: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var role: String = ""
    var isActive: Bool = true
    var email: String = ""
    var categoryIDs: [UUID] = []

    enum CodingKeys: String, CodingKey { case id, name, role, isActive, email, categoryIDs, categoryID }

    init(id: UUID = UUID(), name: String, role: String = "", isActive: Bool = true, email: String = "", categoryIDs: [UUID] = []) {
        self.id = id; self.name = name; self.role = role; self.isActive = isActive; self.email = email; self.categoryIDs = categoryIDs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? ""
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        if let arr = try c.decodeIfPresent([UUID].self, forKey: .categoryIDs) {
            categoryIDs = arr
        } else if let single = try c.decodeIfPresent(UUID.self, forKey: .categoryID) {
            categoryIDs = [single]
        } else {
            categoryIDs = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(role, forKey: .role)
        try c.encode(isActive, forKey: .isActive)
        try c.encode(email, forKey: .email)
        try c.encode(categoryIDs, forKey: .categoryIDs)
    }
}
