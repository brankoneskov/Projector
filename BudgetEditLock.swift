//
//  BudgetEditLock.swift
//  Projector
//
//  Created by Branko Neskov on 28/12/2025.
//
import Foundation

struct BudgetEditLockInfo: Codable {
    let budgetID: String
    let deviceName: String
    let initials: String?
    let createdAtISO8601: String
}

enum BudgetEditLock {
    /// If a budget lock is older than this, assume it is stale (crash/force-quit) and clear it.
    static let staleAfter: TimeInterval = 8 * 60 * 60


    static func lockURL(for budgetID: UUID) -> URL {
        // Lock lives next to the budget record files (even if you haven't migrated yet)
        // ProjectorData_v2/Budgets/<id>.lock
        let folder = DataPaths.file("Budgets")
        ensureDirectoryExists(folder)
        return folder.appendingPathComponent("\(budgetID.uuidString).lock")
    }

    static func readLockInfo(for budgetID: UUID) -> BudgetEditLockInfo? {
        let url = lockURL(for: budgetID)
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url),
              let info = try? JSONDecoder().decode(BudgetEditLockInfo.self, from: data) else { return nil }

        // Stale lock handling
        let fmt = ISO8601DateFormatter()
        if let created = fmt.date(from: info.createdAtISO8601) {
            if Date().timeIntervalSince(created) > staleAfter {
                try? fm.removeItem(at: url)
                return nil
            }
        } else {
            // If timestamp is unreadable, treat as stale to avoid permanent lockout
            try? fm.removeItem(at: url)
            return nil
        }

        return info
    }


    /// Try to acquire lock. Returns true if lock created, false if lock already exists.
    static func acquire(for budgetID: UUID, initials: String?) -> Bool {
        let url = lockURL(for: budgetID)
        let fm = FileManager.default

        // If already exists, we do NOT override.
        guard !fm.fileExists(atPath: url.path) else { return false }

        let info = BudgetEditLockInfo(
            budgetID: budgetID.uuidString,
            deviceName: Host.current().localizedName ?? "Unknown Mac",
            initials: initials?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().nilIfEmpty,
            createdAtISO8601: ISO8601DateFormatter().string(from: Date())
        )

        guard let data = try? JSONEncoder().encode(info) else { return false }
        return fm.createFile(atPath: url.path, contents: data, attributes: nil)
    }

    static func release(for budgetID: UUID) {
        let url = lockURL(for: budgetID)
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try? fm.removeItem(at: url)
        }
    }

    private static func ensureDirectoryExists(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

