//
//  QuoteNumbering.swift
//  Projector
//
//  Created by Branko Neskov on 28/12/2025.
//
import Foundation

/// Generates unique quote numbers like "2025-033-MM"
/// Uses:
/// - quoteCounters.json (persistent counters)
/// - .quoteCounters.lock (short-lived edit lock to prevent collisions across Macs)
enum QuoteNumbering {

    // MARK: - Public API

    /// Reserve the next quote number for a given year.
    /// - Parameters:
    ///   - year: Usually Calendar.current.component(.year, from: Date())
    ///   - initials: Stored per Mac (e.g. "MM")
    /// - Returns: e.g. "2025-033-MM"
    static func reserveNextQuoteNumber(year: Int, initials: String) throws -> String {
        let cleanInitials = initials.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanInitials.isEmpty else {
            throw QuoteNumberingError.missingInitials
        }

        // Acquire Dropbox-friendly lock before we read+write the counter JSON
        let lock = LockFile(url: lockURL, staleAfter: 30)

        try lock.acquire(timeout: 4.0)

        defer {
            try? lock.release()
        }

        var counters = try loadCounters()

        let next = (counters.lastNumberByYear[String(year)] ?? 0) + 1
        counters.lastNumberByYear[String(year)] = next
        counters.updatedAtISO8601 = ISO8601DateFormatter().string(from: Date())

        try saveCounters(counters)

        return "\(year)-\(String(format: "%03d", next))-\(cleanInitials)"
    }
    /// Preview the next quote number WITHOUT reserving it.
    /// This is used for the confirmation dialog.
    static func previewNextQuoteNumber(year: Int, initials: String) throws -> String {
        let cleanInitials = initials.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanInitials.isEmpty else { throw QuoteNumberingError.missingInitials }

        let counters = try loadCounters()
        let next = (counters.lastNumberByYear[String(year)] ?? 0) + 1
        return "\(year)-\(String(format: "%03d", next))-\(cleanInitials)"
    }

    // MARK: - Storage

    private static var countersURL: URL { DataPaths.file("quoteCounters.json") }
    private static var lockURL: URL { DataPaths.file(".quoteCounters.lock") }

    private struct CountersFile: Codable {
        var lastNumberByYear: [String: Int] = [:]
        var updatedAtISO8601: String? = nil
    }

    private static func loadCounters() throws -> CountersFile {
        let fm = FileManager.default
        if !fm.fileExists(atPath: countersURL.path) {
            // First run: create an empty file
            let empty = CountersFile()
            try saveCounters(empty)
            return empty
        }

        let data = try Data(contentsOf: countersURL)
        if data.isEmpty {
            // Defensive: treat empty as new
            let empty = CountersFile()
            try saveCounters(empty)
            return empty
        }

        do {
            return try JSONDecoder().decode(CountersFile.self, from: data)
        } catch {
            // Defensive: if corrupted, do not overwrite silently — bail loudly
            throw QuoteNumberingError.countersCorrupted(error.localizedDescription)
        }
    }

    private static func saveCounters(_ file: CountersFile) throws {
        let data = try JSONEncoder().encode(file)
        try data.write(to: countersURL, options: [.atomic])
    }

    // MARK: - Errors

    enum QuoteNumberingError: LocalizedError {
        case missingInitials
        case countersCorrupted(String)
        case lockTimeout
        case lockIO(String)

        var errorDescription: String? {
            switch self {
            case .missingInitials:
                return "Initials are missing. Please set your initials in Settings."
            case .countersCorrupted(let msg):
                return "quoteCounters.json is not readable: \(msg)"
            case .lockTimeout:
                return "Could not acquire quote numbering lock (another Mac is reserving a number). Try again."
            case .lockIO(let msg):
                return "Lock file I/O error: \(msg)"
            }
        }
    }

    // MARK: - Lock file (Dropbox-friendly)

    private struct LockFile {
        let url: URL
        let staleAfter: TimeInterval

        /// Acquire a lock by creating a new file exclusively.
        /// If it already exists, we wait a bit (and also clear stale locks).
        func acquire(timeout: TimeInterval) throws {
            let start = Date()
            let fm = FileManager.default

            while Date().timeIntervalSince(start) < timeout {
                // If lock exists, see if it is stale
                if fm.fileExists(atPath: url.path) {
                    if isStale() {
                        try? fm.removeItem(at: url)
                        // continue loop and try again
                    } else {
                        // wait and retry
                        Thread.sleep(forTimeInterval: 0.15)
                    }
                    continue
                }

                // Attempt to create lock file
                do {
                    let payload = [
                        "createdAt": ISO8601DateFormatter().string(from: Date()),
                        "host": Host.current().localizedName ?? "Unknown Mac",
                        "pid": "\(ProcessInfo.processInfo.processIdentifier)"
                    ]
                    let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
                    let ok = fm.createFile(atPath: url.path, contents: data, attributes: nil)
                    if ok {
                        return // lock acquired
                    } else {
                        // rare: creation failed without throwing
                        Thread.sleep(forTimeInterval: 0.15)
                    }
                } catch {
                    throw QuoteNumberingError.lockIO(error.localizedDescription)
                }
            }

            throw QuoteNumberingError.lockTimeout
        }

        func release() throws {
            let fm = FileManager.default
            if fm.fileExists(atPath: url.path) {
                try fm.removeItem(at: url)
            }
        }

        private func isStale() -> Bool {
            let fm = FileManager.default
            guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                  let modDate = attrs[.modificationDate] as? Date else {
                return false
            }
            return Date().timeIntervalSince(modDate) > staleAfter
        }
    }
}

