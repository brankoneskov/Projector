//
//  InvoiceStore.swift
//  Projector
//
//  Created by Branko Neskov on 12/01/2026.
//
import Foundation
import Combine

final class InvoiceStore: ObservableObject {
    @Published var invoices: [InvoiceEvent] = [] { didSet { if !isLoading { save() } } }

    static let shared = InvoiceStore()
    private var isLoading = false

    private var folderURL: URL { DataPaths.folder("Invoices") }

    private init() { load() }

    private func recordURL(for id: UUID) -> URL {
        folderURL.appendingPathComponent("\(id.uuidString).json")
    }

    func load() {
        isLoading = true
        defer { isLoading = false }

        let fm = FileManager.default

        do {
            let urls = try fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "json" }

            var loaded: [InvoiceEvent] = []
            loaded.reserveCapacity(urls.count)

            for url in urls {
                do {
                    let data = try Data(contentsOf: url)
                    let inv = try JSONDecoder().decode(InvoiceEvent.self, from: data)
                    loaded.append(inv)
                } catch {
                    print("⚠️ Skipping unreadable invoice file \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }

            // Defensive: if folder has files but none were readable, don't wipe in-memory list.
            if !loaded.isEmpty {
                invoices = loaded.sorted { $0.date < $1.date }
            } else if !urls.isEmpty {
                print("⚠️ Loaded 0 invoices from \(urls.count) files; keeping existing list.")
            } else {
                invoices = []
            }
        } catch {
            print("⚠️ Failed to load Invoices folder: \(error.localizedDescription)")
            // keep existing invoices as-is
        }
    }

    func reload() { load() }

    // MARK: - Mutations

    func add(_ inv: InvoiceEvent) {
        invoices.append(inv)
        invoices.sort { $0.date < $1.date }
    }

    func update(_ inv: InvoiceEvent) {
        if let i = invoices.firstIndex(where: { $0.id == inv.id }) {
            invoices[i] = inv
        } else {
            invoices.append(inv)
        }
        invoices.sort { $0.date < $1.date }
    }

    func delete(_ inv: InvoiceEvent) {
        invoices.removeAll { $0.id == inv.id }
    }

    // MARK: - Persistence

    private func save() {
        let fm = FileManager.default

        // Seatbelt: refuse to overwrite folder with 0 records if folder has files.
        do {
            let existing = try fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "json" }
            if invoices.isEmpty, !existing.isEmpty {
                print("🛑 Refusing to overwrite Invoices/ folder with 0 invoices.")
                return
            }
        } catch {
            print("⚠️ Could not inspect Invoices/ folder: \(error.localizedDescription)")
            return
        }

        do {
            let encoder = JSONEncoder()

            // 1) write/update (atomic)
            for inv in invoices {
                let data = try encoder.encode(inv)
                try data.write(to: recordURL(for: inv.id), options: [.atomic])
            }

            // 2) remove orphans
            let keep = Set(invoices.map { "\($0.id.uuidString).json" })
            let existing = try fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "json" }

            for url in existing where !keep.contains(url.lastPathComponent) {
                try? fm.removeItem(at: url)
            }
        } catch {
            print("Save error (Invoices folder): \(error)")
        }
    }
}

