//
// DataStores.swift
// Projector
//

import Foundation
import Combine

// MARK: - Overlap helper

func intervalsOverlap(aStart: Date, aEnd: Date, bStart: Date, bEnd: Date) -> Bool {
    max(aStart, bStart) < min(aEnd, bEnd)
}

// MARK: - SessionStore

final class SessionStore: ObservableObject {
    @Published var sessions: [Session] = [] { didSet { if !isLoading { save() } } }
    static let shared = SessionStore()
    @Published var isLoading = false

    private var folderURL: URL { DataPaths.folder("Sessions") }
    private var legacyFileURL: URL { DataPaths.file("sessions.json") }

    private init() { load() }

    private func sessionFileURL(_ id: UUID) -> URL {
        folderURL.appendingPathComponent("\(id.uuidString).json")
    }

    func load() {
        isLoading = true
        let fm = FileManager.default
        do {
            let items = try fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
            let jsonFiles = items.filter { $0.pathExtension.lowercased() == "json" }

            if jsonFiles.isEmpty, fm.fileExists(atPath: legacyFileURL.path) {
                do {
                    let legacyData = try Data(contentsOf: legacyFileURL)
                    let decoded = try JSONDecoder().decode([Session].self, from: legacyData)
                    for session in decoded {
                        let data = try JSONEncoder().encode(session)
                        try data.write(to: sessionFileURL(session.id), options: [.atomic])
                    }
                    sessions = decoded.sorted { $0.start < $1.start }
                    isLoading = false
                    print("✅ Migrated \(decoded.count) sessions from sessions.json → Sessions/ folder")
                    return
                } catch {
                    print("⚠️ Session migration failed: \(error.localizedDescription)")
                }
            }

            var loaded: [Session] = []
            loaded.reserveCapacity(jsonFiles.count)
            for url in jsonFiles {
                do {
                    let data = try Data(contentsOf: url)
                    let session = try JSONDecoder().decode(Session.self, from: data)
                    loaded.append(session)
                } catch {
                    print("⚠️ Skipping corrupt session file \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            sessions = loaded.sorted { $0.start < $1.start }
            isLoading = false
        } catch {
            print("⚠️ Failed to load sessions folder: \(error.localizedDescription)")
            isLoading = false
        }
    }

    func reload() { load() }

    func save() {
        let fm = FileManager.default
        do {
            let existing = try fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "json" }
            if sessions.isEmpty, !existing.isEmpty {
                print("🛑 Refusing to overwrite Sessions/ folder with 0 sessions.")
                return
            }
        } catch {
            print("⚠️ Could not inspect Sessions/ folder: \(error.localizedDescription)")
            return
        }

        do {
            for s in sessions {
                let data = try JSONEncoder().encode(s)
                try data.write(to: sessionFileURL(s.id), options: [.atomic])
            }
            let keep = Set(sessions.map { "\($0.id.uuidString).json" })
            let existing = try fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "json" }
            for url in existing where !keep.contains(url.lastPathComponent) {
                try? fm.removeItem(at: url)
            }
        } catch {
            print("Save error (Sessions folder): \(error)")
        }

        writeIndex()
    }

    // MARK: - Index for Projector Go

    struct SessionIndexEntry: Codable {
        let id: String
        let title: String
        let room: String
        let client: String
        let start: Date
        let durationMinutes: Int
        let peopleIDs: [String]
        let notes: String
        let projectID: String?
        let projectName: String?
    }

    private var indexFileURL: URL {
        DataPaths.file("index.json")
    }

    func writeIndex() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let entries = sessions.map { s in
            let proj = s.projectID.flatMap { pid in ProjectStore.shared.projects.first(where: { $0.id == pid }) }
            return SessionIndexEntry(
                id: s.id.uuidString,
                title: s.title,
                room: s.room,
                client: s.client,
                start: s.start,
                durationMinutes: s.durationMinutes,
                peopleIDs: s.peopleIDs.map { $0.uuidString },
                notes: s.notes,
                projectID: s.projectID?.uuidString,
                projectName: proj?.name
            )
        }
        do {
            let data = try encoder.encode(entries)
            try data.write(to: indexFileURL, options: [.atomic])
            print("✅ Wrote index.json with \(entries.count) sessions")
        } catch {
            print("⚠️ Failed to write index.json: \(error)")
        }
    }

    func canSchedule(_ newSession: Session, ignoring idToIgnore: UUID? = nil) -> Bool {
        let calendar = Calendar.current
        let vacations = VacationsStore.shared.vacations

        let vacationConflict: Bool = !isTintedDay(newSession.start) && vacations.contains { entry in
            entry.status != .canceled &&
            newSession.peopleIDs.contains(entry.personId) &&
            calendar.isDate(entry.date, inSameDayAs: newSession.start)
        }
        if vacationConflict { return false }

        return !sessions.contains { existing in
            if let idToIgnore, existing.id == idToIgnore { return false }
            let roomsConflict = existing.room.caseInsensitiveCompare(newSession.room) == .orderedSame
            let peopleOverlap = !Set(existing.peopleIDs).isDisjoint(with: Set(newSession.peopleIDs))
            let timeOverlap = intervalsOverlap(
                aStart: existing.start, aEnd: existing.end,
                bStart: newSession.start, bEnd: newSession.end
            )
            return timeOverlap && (roomsConflict || peopleOverlap)
        }
    }

    func add(_ s: Session) throws {
        guard canSchedule(s) else { throw ValidationError.overlap }
        sessions.append(s)
        sessions.sort { $0.start < $1.start }
        // Push registrations are bound to authenticated person UUIDs.
        APNsSender.shared.sendNewBooking(
            title: s.title,
            date: s.start,
            forPeopleIDs: s.peopleIDs
        )
    }

    func update(_ s: Session) throws {
        guard canSchedule(s, ignoring: s.id) else { throw ValidationError.overlap }
        if let idx = sessions.firstIndex(where: { $0.id == s.id }) {
            sessions[idx] = s
            sessions.sort { $0.start < $1.start }
        }
    }

    func delete(_ s: Session) {
        sessions.removeAll { $0.id == s.id }
        // Also delete the message thread for this session if one exists
        let threadURL = DataPaths.folder("Messages").appendingPathComponent("\(s.id.uuidString).json")
        MessageStore.persistenceLock.lock()
        try? FileManager.default.removeItem(at: threadURL)
        MessageStore.persistenceLock.unlock()
        MessageStore.shared.reload()
    }

    enum ValidationError: LocalizedError {
        case overlap
        var errorDescription: String? { "This session overlaps (room or person) with another session." }
    }
}

// MARK: - ProjectStore

final class ProjectStore: ObservableObject {
    @Published var projects: [Project] = [] { didSet { if !isLoading { save() } } }
    static let shared = ProjectStore()
    private var isLoading = false

    private var folderURL: URL { DataPaths.folder("Projects") }
    private var legacyFileURL: URL { DataPaths.file("projects.json") }

    private init() { load() }

    private func projectFileURL(_ id: UUID) -> URL {
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
                    let decoded = try JSONDecoder().decode([Project].self, from: legacyData)
                    for p in decoded {
                        let data = try JSONEncoder().encode(p)
                        try data.write(to: projectFileURL(p.id), options: [.atomic])
                    }
                    self.projects = decoded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    print("✅ Migrated \(decoded.count) projects → Projects/ folder")
                    return
                } catch {
                    print("⚠️ Project migration failed: \(error.localizedDescription)")
                }
            }

            var loaded: [Project] = []
            loaded.reserveCapacity(jsonFiles.count)
            for url in jsonFiles {
                do {
                    let data = try Data(contentsOf: url)
                    let p = try JSONDecoder().decode(Project.self, from: data)
                    loaded.append(p)
                } catch {
                    print("⚠️ Skipping corrupt project file \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            self.projects = loaded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            print("⚠️ Failed to load Projects folder: \(error.localizedDescription)")
        }
    }

    func reload() { load() }

    private func save() {
        let fm = FileManager.default
        do {
            let existing = try fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "json" }
            if projects.isEmpty, !existing.isEmpty {
                print("🛑 Refusing to overwrite Projects/ folder with 0 projects.")
                return
            }
        } catch {
            print("⚠️ Could not inspect Projects/ folder: \(error.localizedDescription)")
            return
        }

        do {
            for p in projects {
                let data = try JSONEncoder().encode(p)
                try data.write(to: projectFileURL(p.id), options: [.atomic])
            }
            let keep = Set(projects.map { "\($0.id.uuidString).json" })
            let existing = try fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "json" }
            for url in existing where !keep.contains(url.lastPathComponent) {
                try? fm.removeItem(at: url)
            }
        } catch {
            print("Save error (Projects folder): \(error)")
        }
    }

    func add(_ p: Project) { projects.append(p); sort() }

    func update(_ p: Project) {
        if let i = projects.firstIndex(where: { $0.id == p.id }) {
            projects[i] = p
        } else {
            projects.append(p)
        }
        sort()
    }

    func delete(_ p: Project) { projects.removeAll { $0.id == p.id } }

    private func sort() {
        projects.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: - PeopleStore

final class PeopleStore: ObservableObject {
    @Published var people: [Person] = []
    static let shared = PeopleStore()
    private var isLoading = false

    private var folderURL: URL { DataPaths.folder("People") }
    private var legacyFileURL: URL { DataPaths.file("people.json") }

    private init() { load() }

    private func personFileURL(_ id: UUID) -> URL {
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

            var loaded: [Person] = []
            loaded.reserveCapacity(jsonFiles.count)
            for url in jsonFiles {
                do {
                    let data = try Data(contentsOf: url)
                    let p = try JSONDecoder().decode(Person.self, from: data)
                    loaded.append(p)
                } catch {
                    print("⚠️ Failed to decode person file \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }

            if !loaded.isEmpty {
                self.people = loaded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                writePeopleIndex()
                return
            }

            if fm.fileExists(atPath: legacyFileURL.path) {
                do {
                    let data = try Data(contentsOf: legacyFileURL)
                    let decoded = try JSONDecoder().decode([Person].self, from: data)
                    for p in decoded { persistRecord(p) }
                    self.people = decoded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    print("📦 Migrated \(decoded.count) people from people.json to People/*.json")
                    return
                } catch {
                    print("⚠️ Failed to migrate people from \(legacyFileURL.lastPathComponent): \(error.localizedDescription)")
                }
            }
        } catch {
            print("⚠️ Failed to list People folder: \(error.localizedDescription)")
        }
    }

    func add(_ p: Person) { upsert(p) }
    func update(_ p: Person) { upsert(p) }

    func upsert(_ p: Person) {
        if let idx = people.firstIndex(where: { $0.id == p.id }) {
            people[idx] = p
        } else {
            people.append(p)
        }
        sort()
        guard !isLoading else { return }
        persistRecord(p)
    }

    func delete(_ p: Person) {
        people.removeAll { $0.id == p.id }
        sort()
        guard !isLoading else { return }
        deleteRecordFile(p.id)
    }

    private func sort() {
        people.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func persistRecord(_ p: Person) {
        do {
            let data = try JSONEncoder().encode(p)
            try data.write(to: personFileURL(p.id), options: [.atomic])
        } catch {
            print("Save error (Person \(p.id)): \(error)")
        }
        writePeopleIndex()
    }

    func writePeopleIndex() {
        struct PeopleIndexEntry: Codable {
            let id: String
            let name: String
            let isActive: Bool
        }
        let entries = people.map { PeopleIndexEntry(id: $0.id.uuidString, name: $0.name, isActive: $0.isActive) }
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: DataPaths.file("people_index.json"), options: [.atomic])
            print("✅ Wrote people_index.json with \(entries.count) people")
        } catch {
            print("⚠️ Failed to write people_index.json: \(error)")
        }
    }

    private func deleteRecordFile(_ id: UUID) {
        let url = personFileURL(id)
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            print("Delete error (Person \(id)): \(error)")
        }
    }
}

