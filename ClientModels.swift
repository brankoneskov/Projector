//
//  ClientModels.swift
//  Projector
//
//  Created by Branko Neskov on 27/10/2025.
//
import Foundation
import Combine

struct Client: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var contactName: String = ""
    var vatNumber: String = ""      // ✅ NEW: VAT Nº (Portugal NIF)
    var email: String = ""
    var phone: String = ""
    var address: String = ""
    var notes: String = ""
    var isActive: Bool = true

    enum CodingKeys: String, CodingKey {
        case id, name, contactName, vatNumber, email, phone, address, notes, isActive
    }

    // ✅ Important: keeps old clients.json compatible (missing vatNumber won't crash)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        contactName = try c.decodeIfPresent(String.self, forKey: .contactName) ?? ""
        vatNumber   = try c.decodeIfPresent(String.self, forKey: .vatNumber) ?? ""   // ✅ safe default
        email       = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        phone       = try c.decodeIfPresent(String.self, forKey: .phone) ?? ""
        address     = try c.decodeIfPresent(String.self, forKey: .address) ?? ""
        notes       = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        isActive    = try c.decodeIfPresent(Bool.self,   forKey: .isActive) ?? true
    }

    init(
        id: UUID = UUID(),
        name: String,
        contactName: String = "",
        vatNumber: String = "",
        email: String = "",
        phone: String = "",
        address: String = "",
        notes: String = "",
        isActive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.contactName = contactName
        self.vatNumber = vatNumber
        self.email = email
        self.phone = phone
        self.address = address
        self.notes = notes
        self.isActive = isActive
    }
}


final class ClientsStore: ObservableObject {
    @Published var clients: [Client] = []
    static let shared = ClientsStore()

    private var isLoading = false

    // NEW: per-record storage
    private var folderURL: URL { DataPaths.folder("Clients") }

    // Legacy (one-file) storage (for migration only)
    private var legacyFileURL: URL { DataPaths.file("clients.json") }

    private init() { load() }

    private func clientFileURL(_ id: UUID) -> URL {
        folderURL.appendingPathComponent("\(id.uuidString).json")
    }

    func reload() { load() }

    private func load() {
        isLoading = true
        defer { isLoading = false }

        let fm = FileManager.default
        let folder = folderURL

        do {
            // Read per-record files
            let items = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            let jsonFiles = items.filter { $0.pathExtension.lowercased() == "json" }

            var loaded: [Client] = []
            loaded.reserveCapacity(jsonFiles.count)

            for url in jsonFiles {
                do {
                    let data = try Data(contentsOf: url)
                    let c = try JSONDecoder().decode(Client.self, from: data)
                    loaded.append(c)
                } catch {
                    print("⚠️ Failed to decode client file \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }

            if !loaded.isEmpty {
                self.clients = loaded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                return
            }

            // Migrate from legacy clients.json if it exists
            if fm.fileExists(atPath: legacyFileURL.path) {
                do {
                    let data = try Data(contentsOf: legacyFileURL)
                    let decoded = try JSONDecoder().decode([Client].self, from: data)

                    for c in decoded { persistRecord(c) }

                    self.clients = decoded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    print("📦 Migrated \(decoded.count) clients to Clients/*.json")
                    return
                } catch {
                    print("⚠️ Failed to migrate clients: \(error.localizedDescription)")
                }
            }

            self.clients = []  // seed empty

        } catch {
            print("⚠️ Failed to list Clients folder: \(error.localizedDescription)")
            // keep existing
        }
    }

    // MARK: - Mutations

    func add(_ c: Client) { upsert(c) }
    func update(_ c: Client) { upsert(c) }

    func upsert(_ c: Client) {
        if let i = clients.firstIndex(where: { $0.id == c.id }) {
            clients[i] = c
        } else {
            clients.append(c)
        }
        sort()
        guard !isLoading else { return }
        persistRecord(c)
    }

    func delete(_ c: Client) {
        clients.removeAll { $0.id == c.id }
        sort()
        guard !isLoading else { return }
        deleteRecordFile(c.id)
    }

    private func sort() {
        clients.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func persistRecord(_ c: Client) {
        do {
            let data = try JSONEncoder().encode(c)
            try data.write(to: clientFileURL(c.id), options: [.atomic])
        } catch {
            print("Save error (Client \(c.id)): \(error)")
        }
    }

    private func deleteRecordFile(_ id: UUID) {
        let url = clientFileURL(id)
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            print("Delete error (Client \(id)): \(error)")
        }
    }
}


