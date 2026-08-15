//
//  PaymentStore.swift
//  Projector
//
//  Created by Branko Neskov on 12/01/2026.
//
import Foundation
import Combine

final class PaymentStore: ObservableObject {
    @Published var payments: [PaymentEvent] = [] { didSet { if !isLoading { save() } } }

    static let shared = PaymentStore()
    private var isLoading = false

    private var folderURL: URL { DataPaths.folder("Payments") }

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

            var loaded: [PaymentEvent] = []
            loaded.reserveCapacity(urls.count)

            for url in urls {
                do {
                    let data = try Data(contentsOf: url)
                    let p = try JSONDecoder().decode(PaymentEvent.self, from: data)
                    loaded.append(p)
                } catch {
                    print("⚠️ Skipping unreadable payment file \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }

            if !loaded.isEmpty {
                payments = loaded.sorted { $0.date < $1.date }
            } else if !urls.isEmpty {
                print("⚠️ Loaded 0 payments from \(urls.count) files; keeping existing list.")
            } else {
                payments = []
            }
        } catch {
            print("⚠️ Failed to load Payments folder: \(error.localizedDescription)")
            // keep existing payments as-is
        }
    }

    func reload() { load() }

    // MARK: - Mutations

    func add(_ p: PaymentEvent) {
        payments.append(p)
        payments.sort { $0.date < $1.date }
    }

    func update(_ p: PaymentEvent) {
        if let i = payments.firstIndex(where: { $0.id == p.id }) {
            payments[i] = p
        } else {
            payments.append(p)
        }
        payments.sort { $0.date < $1.date }
    }

    func delete(_ p: PaymentEvent) {
        payments.removeAll { $0.id == p.id }
    }

    // MARK: - Persistence

    private func save() {
        let fm = FileManager.default

        do {
            let existing = try fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "json" }
            if payments.isEmpty, !existing.isEmpty {
                print("🛑 Refusing to overwrite Payments/ folder with 0 payments.")
                return
            }
        } catch {
            print("⚠️ Could not inspect Payments/ folder: \(error.localizedDescription)")
            return
        }

        do {
            let encoder = JSONEncoder()

            for p in payments {
                let data = try encoder.encode(p)
                try data.write(to: recordURL(for: p.id), options: [.atomic])
            }

            let keep = Set(payments.map { "\($0.id.uuidString).json" })
            let existing = try fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "json" }

            for url in existing where !keep.contains(url.lastPathComponent) {
                try? fm.removeItem(at: url)
            }
        } catch {
            print("Save error (Payments folder): \(error)")
        }
    }
}

