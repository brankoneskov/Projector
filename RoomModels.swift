//
// RoomModels.swift
// Projector
//

import Foundation
import Combine

// MARK: - Room

struct Room: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var isActive: Bool = true

    // Deprecated legacy per-room fields:
    var sellRatePerHour: Double = 0
    var buyCostPerHour: Double = 0
    var categoryIDs: [UUID] = []

    enum CodingKeys: String, CodingKey {
        case id, name, isActive, sellRatePerHour, buyCostPerHour, categoryIDs, categoryID
    }

    init(id: UUID = UUID(), name: String, isActive: Bool = true,
         sellRatePerHour: Double = 0, buyCostPerHour: Double = 0,
         categoryIDs: [UUID] = []) {
        self.id = id; self.name = name; self.isActive = isActive
        self.sellRatePerHour = sellRatePerHour; self.buyCostPerHour = buyCostPerHour
        self.categoryIDs = categoryIDs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        sellRatePerHour = try c.decodeIfPresent(Double.self, forKey: .sellRatePerHour) ?? 0
        buyCostPerHour  = try c.decodeIfPresent(Double.self, forKey: .buyCostPerHour)  ?? 0
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
        try c.encode(isActive, forKey: .isActive)
        try c.encode(sellRatePerHour, forKey: .sellRatePerHour)
        try c.encode(buyCostPerHour, forKey: .buyCostPerHour)
        try c.encode(categoryIDs, forKey: .categoryIDs)
    }
}

// MARK: - RoomStore

final class RoomStore: ObservableObject {
    @Published var rooms: [Room] = [] { didSet { if !isLoading { save() } } }
    static let shared = RoomStore()
    private var isLoading = false
    private var folderURL: URL { DataPaths.folder("Rooms") }
    private var legacyFileURL: URL { DataPaths.file("rooms.json") }
    private func recordURL(for id: UUID) -> URL { folderURL.appendingPathComponent("\(id.uuidString).json") }
    private init() { load() }

    func load() {
        isLoading = true
        defer { isLoading = false }

        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

            let existing = (try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)) ?? []
            if existing.isEmpty, FileManager.default.fileExists(atPath: legacyFileURL.path) {
                do {
                    let data = try Data(contentsOf: legacyFileURL)
                    let decoded = try JSONDecoder().decode([Room].self, from: data)
                    self.rooms = decoded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    save()
                    return
                } catch {
                    print("⚠️ Failed to import legacy rooms.json:", error)
                }
            }

            var loaded: [Room] = []
            for url in existing where url.pathExtension.lowercased() == "json" {
                do {
                    let data = try Data(contentsOf: url)
                    let room = try JSONDecoder().decode(Room.self, from: data)
                    loaded.append(room)
                } catch {
                    print("⚠️ Failed to decode room file \(url.lastPathComponent):", error)
                }
            }
            self.rooms = loaded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            print("⚠️ Failed to load rooms from folder:", error)
        }
    }

    func reload() { load() }

    func save() {
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

            let existingFiles = (try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)) ?? []
            if rooms.isEmpty, !existingFiles.isEmpty {
                print("🛑 Refusing to overwrite Rooms/ with empty array.")
                return
            }

            let encoder = JSONEncoder()
            for r in rooms {
                let data = try encoder.encode(r)
                try data.write(to: recordURL(for: r.id), options: [.atomic])
            }

            let liveIDs = Set(rooms.map { $0.id.uuidString.lowercased() })
            for url in existingFiles where url.pathExtension.lowercased() == "json" {
                let stem = url.deletingPathExtension().lastPathComponent.lowercased()
                if !liveIDs.contains(stem) {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        } catch {
            print("Save error (Rooms folder):", error)
        }
    }

    func add(_ r: Room) { rooms.append(r); sort() }
    func update(_ r: Room) { if let i = rooms.firstIndex(where: { $0.id == r.id }) { rooms[i] = r; sort() } }
    func delete(_ r: Room) { rooms.removeAll { $0.id == r.id } }

    private func sort() {
        rooms.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
