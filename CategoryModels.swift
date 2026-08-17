//
// CategoryModels.swift
// Projector
//

import Foundation
import Combine

// MARK: - RoomCategory

struct RoomCategory: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var sellRatePerHour: Double = 0
    var buyCostPerHour: Double = 0
    var isActive: Bool = true

    // User-selected links into TranslationStore. Optional keeps all existing
    // RoomCategories/*.json records backwards compatible.
    var translationEntryID: UUID? = nil
    var unitTranslationEntryID: UUID? = nil
    var defaultBudgetSection: BudgetSection? = nil
}

// MARK: - PersonCategory

struct PersonCategory: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var sellRatePerHour: Double = 0
    var buyCostPerHour: Double = 0
    var isActive: Bool = true

    // User-selected links into TranslationStore. Optional keeps all existing
    // PersonCategories/*.json records backwards compatible.
    var translationEntryID: UUID? = nil
    var unitTranslationEntryID: UUID? = nil
    var defaultBudgetSection: BudgetSection? = nil
}

// MARK: - RoomCategoryStore

final class RoomCategoryStore: ObservableObject {
    @Published var categories: [RoomCategory] = [] { didSet { if !isLoading { save() } } }
    static let shared = RoomCategoryStore()
    private var isLoading = false

    private var folderURL: URL { DataPaths.folder("RoomCategories") }
    private var legacyFileURL: URL { DataPaths.file("roomCategories.json") }

    private init() { load() }

    private func categoryFileURL(_ id: UUID) -> URL {
        folderURL.appendingPathComponent("\(id.uuidString).json")
    }

    func load() {
        isLoading = true
        defer { isLoading = false }

        let fm = FileManager.default

        do {
            let items = try fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
            let jsonFiles = items.filter { $0.pathExtension.lowercased() == "json" }

            if jsonFiles.isEmpty, fm.fileExists(atPath: legacyFileURL.path) {
                do {
                    let legacyData = try Data(contentsOf: legacyFileURL)
                    let decoded = try JSONDecoder().decode([RoomCategory].self, from: legacyData)
                    for c in decoded {
                        let data = try JSONEncoder().encode(c)
                        try data.write(to: categoryFileURL(c.id), options: [.atomic])
                    }
                    self.categories = decoded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    print("✅ Migrated \(decoded.count) room categories → RoomCategories/ folder")
                    return
                } catch {
                    print("⚠️ RoomCategory migration failed: \(error.localizedDescription)")
                }
            }

            var loaded: [RoomCategory] = []
            loaded.reserveCapacity(jsonFiles.count)
            for url in jsonFiles {
                do {
                    let data = try Data(contentsOf: url)
                    let c = try JSONDecoder().decode(RoomCategory.self, from: data)
                    loaded.append(c)
                } catch {
                    print("⚠️ Skipping corrupt room category file \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            self.categories = loaded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            print("⚠️ Failed to load RoomCategories folder: \(error.localizedDescription)")
        }
    }

    func reload() { load() }

    private func save() {
        let fm = FileManager.default
        do {
            let existing = try fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "json" }
            if categories.isEmpty, !existing.isEmpty {
                print("🛑 Refusing to overwrite RoomCategories/ folder with 0 categories.")
                return
            }
        } catch {
            print("⚠️ Could not inspect RoomCategories/ folder: \(error.localizedDescription)")
            return
        }

        do {
            for c in categories {
                let data = try JSONEncoder().encode(c)
                try data.write(to: categoryFileURL(c.id), options: [.atomic])
            }
            let keep = Set(categories.map { "\($0.id.uuidString).json" })
            let existing = try fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "json" }
            for url in existing where !keep.contains(url.lastPathComponent) {
                try? fm.removeItem(at: url)
            }
        } catch {
            print("Save error (RoomCategories folder): \(error)")
        }
    }

    func add(_ c: RoomCategory) { categories.append(c); sort() }

    func update(_ c: RoomCategory) {
        if let i = categories.firstIndex(where: { $0.id == c.id }) {
            categories[i] = c
        } else {
            categories.append(c)
        }
        sort()
    }

    func delete(_ c: RoomCategory) { categories.removeAll { $0.id == c.id } }

    private func sort() {
        categories.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: - PersonCategoryStore

final class PersonCategoryStore: ObservableObject {
    @Published var categories: [PersonCategory] = []
    static let shared = PersonCategoryStore()
    private var isLoading = false

    private var folderURL: URL { DataPaths.folder("PersonCategories") }
    private var legacyFileURL: URL { DataPaths.file("personCategories.json") }

    private init() { load() }

    private func categoryFileURL(_ id: UUID) -> URL {
        folderURL.appendingPathComponent("\(id.uuidString).json")
    }

    func reload() { load() }

    func load() {
        isLoading = true
        defer { isLoading = false }

        let fm = FileManager.default

        do {
            let items = try fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
            let jsonFiles = items.filter { $0.pathExtension.lowercased() == "json" }

            var loaded: [PersonCategory] = []
            loaded.reserveCapacity(jsonFiles.count)
            for url in jsonFiles {
                do {
                    let data = try Data(contentsOf: url)
                    let c = try JSONDecoder().decode(PersonCategory.self, from: data)
                    loaded.append(c)
                } catch {
                    print("⚠️ Failed to decode person category file \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }

            if !loaded.isEmpty {
                self.categories = loaded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                return
            }

            if fm.fileExists(atPath: legacyFileURL.path) {
                do {
                    let data = try Data(contentsOf: legacyFileURL)
                    let decoded = try JSONDecoder().decode([PersonCategory].self, from: data)
                    for c in decoded { persistRecord(c) }
                    self.categories = decoded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    print("📦 Migrated \(decoded.count) person categories to PersonCategories/*.json")
                    return
                } catch {
                    print("⚠️ Failed to migrate person categories: \(error.localizedDescription)")
                }
            }

            self.categories = [
                "Film Re-Recording Mixer","Tv Re-Recording Mixer","Sound Editor","ADR Mixer",
                "Foley Mixer","Film Editor","Assistant Film Editor"
            ].map { PersonCategory(name: $0) }
            for c in self.categories { persistRecord(c) }
            sort()
        } catch {
            print("⚠️ Failed to list PersonCategories folder: \(error.localizedDescription)")
        }
    }

    func add(_ c: PersonCategory) { upsert(c) }
    func update(_ c: PersonCategory) { upsert(c) }

    func upsert(_ c: PersonCategory) {
        if let i = categories.firstIndex(where: { $0.id == c.id }) {
            categories[i] = c
        } else {
            categories.append(c)
        }
        sort()
        guard !isLoading else { return }
        persistRecord(c)
    }

    func delete(_ c: PersonCategory) {
        categories.removeAll { $0.id == c.id }
        sort()
        guard !isLoading else { return }
        deleteRecordFile(c.id)
    }

    private func sort() {
        categories.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func persistRecord(_ c: PersonCategory) {
        do {
            let data = try JSONEncoder().encode(c)
            try data.write(to: categoryFileURL(c.id), options: [.atomic])
        } catch {
            print("Save error (PersonCategory \(c.id)): \(error)")
        }
    }

    private func deleteRecordFile(_ id: UUID) {
        let url = categoryFileURL(id)
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            print("Delete error (PersonCategory \(id)): \(error)")
        }
    }
}

