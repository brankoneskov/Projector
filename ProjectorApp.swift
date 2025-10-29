//
//  StudioScheduler.swift
//  StudioScheduler People
//
//  Created by Branko Neskov on 12/10/2025.
//

import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers
import ObjectiveC

// Calls onResolve(window) when the SwiftUI view is attached to a window.
private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // The window is nil in makeNSView; grab it on the next runloop.
        DispatchQueue.main.async { [weak view] in
            if let win = view?.window {
                onResolve(win)
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowFrameBinder {
    private weak var window: NSWindow?
    private let key: String
    private var observers: [NSObjectProtocol] = []

    init(window: NSWindow, key: String) {
        self.window = window
        self.key = key
    }

    func attach() {
        guard let win = window else { return }

        // Restore previously saved frame (if any)
        restoreFrame(on: win)

        // Save on motion/resize events
        let center = NotificationCenter.default
        let save: (Notification) -> Void = { [weak self] _ in self?.saveFrame() }
        observers.append(center.addObserver(forName: NSWindow.didMoveNotification, object: win, queue: .main, using: save))
        observers.append(center.addObserver(forName: NSWindow.didResizeNotification, object: win, queue: .main, using: save))
        observers.append(center.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: win, queue: .main, using: save))
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: win, queue: .main, using: save))
    }

    private func restoreFrame(on win: NSWindow) {
        let d = UserDefaults.standard
        guard
            d.object(forKey: "\(key).w") != nil,
            d.object(forKey: "\(key).h") != nil,
            d.object(forKey: "\(key).x") != nil,
            d.object(forKey: "\(key).y") != nil
        else { return }

        var f = win.frame
        f.size.width  = max(400, d.double(forKey: "\(key).w"))
        f.size.height = max(300, d.double(forKey: "\(key).h"))
        f.origin.x    = d.double(forKey: "\(key).x")
        f.origin.y    = d.double(forKey: "\(key).y")

        // Apply immediately…
        win.setFrame(f, display: true)
        // …and once more on the next tick to override SwiftUI defaultSize/layout.
        DispatchQueue.main.async {
            win.setFrame(f, display: true)
        }
    }

    private func saveFrame() {
        guard let f = window?.frame else { return }
        let d = UserDefaults.standard
        d.set(f.size.width,  forKey: "\(key).w")
        d.set(f.size.height, forKey: "\(key).h")
        d.set(f.origin.x,    forKey: "\(key).x")
        d.set(f.origin.y,    forKey: "\(key).y")
    }

    // MARK: Associated-object retention

    private static var assocKey: UInt8 = 0

    /// Attaches a retained binder to the window, so it isn't deallocated.
    static func attach(to window: NSWindow, key: String) {
        if let existing = objc_getAssociatedObject(window, &assocKey) as? WindowFrameBinder {
            existing.attach()
            return
        }
        let binder = WindowFrameBinder(window: window, key: key)
        objc_setAssociatedObject(window, &assocKey, binder, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        binder.attach()
    }
}

private struct WindowFramePersistence: ViewModifier {
    let key: String
    func body(content: Content) -> some View {
        content.background(
            WindowAccessor { win in
                WindowFrameBinder.attach(to: win, key: key)
            }
        )
    }
}

extension View {
    /// Persists/restores the NSWindow frame using the given unique key.
    func persistWindowFrame(_ key: String) -> some View {
        modifier(WindowFramePersistence(key: key))
    }
}

// MARK: - Model
struct Session: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var client: String
    var room: String
    var start: Date
    var durationMinutes: Int
    var ratePerHour: Double?
    var notes: String
    var projectID: UUID?
    var peopleIDs: [UUID] = []

    // NEW: category selections used for THIS booking
    var roomCategoryID: UUID? = nil             // chosen category for the booked room
    var peopleRoles: [UUID: UUID] = [:]         // personID -> chosen categoryID

    var end: Date { start.addingTimeInterval(TimeInterval(durationMinutes * 60)) }

    var revenue: Double? {
        guard let rate = ratePerHour else { return nil }
        return (Double(durationMinutes) / 60.0) * rate
    }
}

struct Project: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var client: String
    var isActive: Bool = true
    var notes: String = ""
}

struct Person: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var role: String = ""
    var isActive: Bool = true
    var email: String = ""

    // OLD: var categoryID: UUID?
    // NEW: multiple categories
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
        // accept either old single field or the new array
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

// MARK: - Categories
struct RoomCategory: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var sellRatePerHour: Double = 0
    var buyCostPerHour: Double = 0
    var isActive: Bool = true
}


struct PersonCategory: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var sellRatePerHour: Double = 0
    var buyCostPerHour: Double = 0
    var isActive: Bool = true
}

final class RoomCategoryStore: ObservableObject {
    @Published var categories: [RoomCategory] = [] { didSet { save() } }
    static let shared = RoomCategoryStore()
    private init() { loadOrSeed() }

    private var fileURL: URL { DataPaths.file("roomCategories.json") }

    private func loadOrSeed() {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode([RoomCategory].self, from: data)
            self.categories = decoded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            // Seed with your defaults (rates start at 0 — set them later in UI)
            self.categories = [
                "Film Edit","Sound Edit","Film Mix","Tv Mix","Sound Recording","Color Grading"
            ].map { RoomCategory(name: $0) }
        }
    }

    private func save() {
        do { let data = try JSONEncoder().encode(categories); try data.write(to: fileURL, options: [.atomic]) }
        catch { print("Save error (RoomCategoryStore): \(error)") }
    }

    func add(_ c: RoomCategory) { categories.append(c); sort() }
    func update(_ c: RoomCategory) { if let i = categories.firstIndex(where: { $0.id == c.id }) { categories[i] = c; sort() } }
    func delete(_ c: RoomCategory) { categories.removeAll { $0.id == c.id } }
    private func sort() { categories.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }
}

final class PersonCategoryStore: ObservableObject {
    @Published var categories: [PersonCategory] = [] { didSet { save() } }
    static let shared = PersonCategoryStore()
    private init() { loadOrSeed() }

    private var fileURL: URL { DataPaths.file("personCategories.json") }

    private func loadOrSeed() {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode([PersonCategory].self, from: data)
            self.categories = decoded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            self.categories = [
                "Film Re-Recording Mixer","Tv Re-Recording Mixer","Sound Editor","ADR Mixer",
                "Foley Mixer","Film Editor","Assistant Film Editor"
            ].map { PersonCategory(name: $0) }
        }
    }

    private func save() {
        do { let data = try JSONEncoder().encode(categories); try data.write(to: fileURL, options: [.atomic]) }
        catch { print("Save error (PersonCategoryStore): \(error)") }
    }

    func add(_ c: PersonCategory) { categories.append(c); sort() }
    func update(_ c: PersonCategory) { if let i = categories.firstIndex(where: { $0.id == c.id }) { categories[i] = c; sort() } }
    func delete(_ c: PersonCategory) { categories.removeAll { $0.id == c.id } }
    private func sort() { categories.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }
}

// MARK: - Persistence
final class SessionStore: ObservableObject {
    @Published var sessions: [Session] = [] { didSet { save() } }
    static let shared = SessionStore()

    private let fileURL: URL = DataPaths.file("sessions.json")

    private init() { load() }

    func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode([Session].self, from: data)
            self.sessions = decoded.sorted { $0.start < $1.start }
        } catch {
            self.sessions = []
        }
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(sessions)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("Save error: \(error)")
        }
    }

    // Prevent overlapping sessions in the same room OR with the same person(s)
    func canSchedule(_ newSession: Session, ignoring idToIgnore: UUID? = nil) -> Bool {
        !sessions.contains { existing in
            if let idToIgnore, existing.id == idToIgnore { return false }

            let roomsConflict = existing.room.caseInsensitiveCompare(newSession.room) == .orderedSame
            let peopleOverlap = !Set(existing.peopleIDs).isDisjoint(with: Set(newSession.peopleIDs))
            let timeOverlap = intervalsOverlap(aStart: existing.start, aEnd: existing.end,
                                               bStart: newSession.start, bEnd: newSession.end)

            // Conflict if same room overlaps OR any same person overlaps
            return timeOverlap && (roomsConflict || peopleOverlap)
        }
    }

    func add(_ s: Session) throws {
        guard canSchedule(s) else { throw ValidationError.overlap }
        sessions.append(s)
        sessions.sort { $0.start < $1.start }
    }

    func update(_ s: Session) throws {
        guard canSchedule(s, ignoring: s.id) else { throw ValidationError.overlap }
        if let idx = sessions.firstIndex(where: { $0.id == s.id }) {
            sessions[idx] = s
            sessions.sort { $0.start < $1.start }
        }
    }

    func delete(_ s: Session) { sessions.removeAll { $0.id == s.id } }

    enum ValidationError: LocalizedError {
        case overlap
        var errorDescription: String? { "This session overlaps (room or person) with another session." }
    }
}

final class ProjectStore: ObservableObject {
    @Published var projects: [Project] = [] { didSet { save() } }
    static let shared = ProjectStore()

    private let fileURL: URL = DataPaths.file("projects.json")

    private init() { load() }

    func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode([Project].self, from: data)
            self.projects = decoded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            self.projects = []
        }
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(projects)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("Save error: \(error)")
        }
    }

    func add(_ p: Project) { projects.append(p); sort() }
    func update(_ p: Project) { if let i = projects.firstIndex(where: { $0.id == p.id }) { projects[i] = p; sort() } }
    func delete(_ p: Project) { projects.removeAll { $0.id == p.id } }
    private func sort() { projects.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }
}

final class PeopleStore: ObservableObject {
    @Published var people: [Person] = [] { didSet { save() } }
    static let shared = PeopleStore()

    private let fileURL: URL = DataPaths.file("people.json")

    private init() { load() }

    func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode([Person].self, from: data)
            self.people = decoded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            self.people = []
        }
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(people)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("Save error: \(error)")
        }
    }

    func add(_ p: Person) { people.append(p); sort() }
    func update(_ p: Person) { if let i = people.firstIndex(where: { $0.id == p.id }) { people[i] = p; sort() } }
    func delete(_ p: Person) { people.removeAll { $0.id == p.id } }
    private func sort() { people.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }
}

fileprivate func intervalsOverlap(aStart: Date, aEnd: Date, bStart: Date, bEnd: Date) -> Bool {
    max(aStart, bStart) < min(aEnd, bEnd)
}

// MARK: - Filters
final class Filters: ObservableObject {
    @Published var query: String = ""
    @Published var room: String = "All Rooms"
    @Published var client: String = "All Clients"
    @Published var projectID: UUID? = nil
    @Published var personID: UUID? = nil           // NEW: filter by person
    @Published var day: Date = Date()
    func reset() { query = ""; room = "All Rooms"; client = "All Clients"; projectID = nil; personID = nil }
}

// MARK: - App Entry
@main
struct ProjectorApp: App {
    init() {
        DataPaths.migrateFromOldIfNeeded()
    }
    @StateObject private var budgetStore = BudgetStore.shared
    @StateObject private var store      = SessionStore.shared
    @StateObject private var projects   = ProjectStore.shared
    @StateObject private var people     = PeopleStore.shared
    @StateObject private var roomsStore = RoomStore.shared
    @StateObject private var filters    = Filters()
    @StateObject private var roomCategories   = RoomCategoryStore.shared
    @StateObject private var personCategories = PersonCategoryStore.shared
    @StateObject private var clientsStore = ClientsStore.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // 1) Main window
        WindowGroup {
            ContentView()
                .environmentObject(budgetStore)
                .environmentObject(store)
                .environmentObject(projects)
                .environmentObject(people)
                .environmentObject(roomsStore)
                .environmentObject(filters)
                .environmentObject(roomCategories)
                .environmentObject(personCategories)
                .environmentObject(clientsStore)
        }
        // 2) Other windows you already use
        WindowGroup(id: "projects") {
            ManageProjectsSheet()
                .environmentObject(projects)
                .environmentObject(roomsStore)
                .environmentObject(clientsStore)
        }
        // ✅ Your Project Dashboard window (kept exactly as pattern you used)
        WindowGroup(id: "projectDashboard", for: UUID.self) { $projectID in
            if let id = projectID,
               let proj = projects.projects.first(where: { $0.id == id }) {
                ProjectDashboardView(project: proj)
                    .environmentObject(store)
                    .environmentObject(projects)
                    .environmentObject(people)
                    .environmentObject(roomsStore)
                    .environmentObject(roomCategories)
                    .environmentObject(personCategories)
            } else {
                Text("No project selected")
                    .frame(minWidth: 420, minHeight: 320)
            }
        }
        
        WindowGroup(id: "peopleManager") {
            ManagePeopleSheet()
                .environmentObject(people)
                .environmentObject(personCategories)
        }
        // Rooms manager (if you still keep it as a window)
        WindowGroup(id: "rooms") {
            ManageRoomsSheet()
                .environmentObject(roomsStore)
                .environmentObject(roomCategories)
        }
        // Category windows
        WindowGroup(id: "roomCategories") {
            ManageRoomCategoriesView()
                .environmentObject(roomCategories)
        }
        WindowGroup(id: "personCategories") {
            ManagePersonCategoriesView()
                .environmentObject(personCategories)
        }
        // Project-scoped Budget window
        WindowGroup(id: "budget", for: UUID.self) { $projectID in
            if let id = projectID,
               projects.projects.first(where: { $0.id == id }) != nil {
                BudgetManagerView(projectID: id)
                    .environmentObject(budgetStore)
                    .environmentObject(projects)
                    .environmentObject(roomsStore)
                    .environmentObject(roomCategories)
                    .environmentObject(personCategories)
            } else {
                Text("No project selected")
                    .frame(minWidth: 420, minHeight: 320)
            }
        }

        .defaultSize(width: 920, height: 640)
        .windowResizability(.automatic)
        WindowGroup(id: "clients") {
            ManageClientsSheet()
                .environmentObject(clientsStore)
        }
        // 4) Commands (menus & shortcuts) — chained at the same Scene level
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Session") {
                    // hook up your “new session” trigger if desired
                }
                .keyboardShortcut("n", modifiers: [.command])
            }

            CommandMenu("Projector") {
                Button("Open Projects") { openWindow(id: "projects") }
                    .keyboardShortcut("p", modifiers: [.command, .shift])

                Button("Open Rooms")    { openWindow(id: "rooms") }
                    .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("Open People")   { openWindow(id: "peopleManager") }
                    .keyboardShortcut("o", modifiers: [.command, .shift])

                Divider()
                Button("Open Clients") {
                    openWindow(id: "clients")
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Button("Open Budgets") {
                    // this still calls your custom selector if you have it in another file;
                    // otherwise, if Budgets is the window group with id "budgets", just:
                    openWindow(id: "budgets")
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            }
        }
    }
}

// MARK: - Finance helpers
struct Finance {
    static func sessionRevenue(
        _ s: Session,
        rooms: [Room],
        people: [Person],
        roomCategories: [RoomCategory] = RoomCategoryStore.shared.categories,
        personCategories: [PersonCategory] = PersonCategoryStore.shared.categories
    ) -> Double {
        let roomRate = rateForRoomSelection(roomName: s.room,
                                            chosenCategoryID: s.roomCategoryID,
                                            rooms: rooms,
                                            roomCategories: roomCategories,
                                            kind: .sell)
        let peopleRate = people
            .filter { s.peopleIDs.contains($0.id) }
            .reduce(0.0) { sum, p in
                let chosen = s.peopleRoles[p.id]
                return sum + rateForPersonSelection(person: p,
                                                    chosenCategoryID: chosen,
                                                    personCategories: personCategories,
                                                    kind: .sell)
            }
        return (Double(s.durationMinutes) / 60.0) * (roomRate + peopleRate)
    }

    static func sessionCost(
        _ s: Session,
        rooms: [Room],
        people: [Person],
        roomCategories: [RoomCategory] = RoomCategoryStore.shared.categories,
        personCategories: [PersonCategory] = PersonCategoryStore.shared.categories
    ) -> Double {
        let roomCost = rateForRoomSelection(roomName: s.room,
                                            chosenCategoryID: s.roomCategoryID,
                                            rooms: rooms,
                                            roomCategories: roomCategories,
                                            kind: .buy)
        let peopleCost = people
            .filter { s.peopleIDs.contains($0.id) }
            .reduce(0.0) { sum, p in
                let chosen = s.peopleRoles[p.id]
                return sum + rateForPersonSelection(person: p,
                                                    chosenCategoryID: chosen,
                                                    personCategories: personCategories,
                                                    kind: .buy)
            }
        return (Double(s.durationMinutes) / 60.0) * (roomCost + peopleCost)
    }

    private enum RateKind { case sell, buy }

    private static func rateForRoomSelection(
        roomName: String,
        chosenCategoryID: UUID?,
        rooms: [Room],
        roomCategories: [RoomCategory],
        kind: RateKind
    ) -> Double {
        guard let r = rooms.first(where: { $0.name.caseInsensitiveCompare(roomName) == .orderedSame }) else { return 0 }
        let idToUse = chosenCategoryID ?? r.categoryIDs.first
        if let id = idToUse, let cat = roomCategories.first(where: { $0.id == id }) {
            return (kind == .sell) ? cat.sellRatePerHour : cat.buyCostPerHour
        }
        // legacy fallback
        return (kind == .sell) ? r.sellRatePerHour : r.buyCostPerHour
    }

    private static func rateForPersonSelection(
        person: Person,
        chosenCategoryID: UUID?,
        personCategories: [PersonCategory],
        kind: RateKind
    ) -> Double {
        let idToUse = chosenCategoryID ?? person.categoryIDs.first
        guard let id = idToUse, let cat = personCategories.first(where: { $0.id == id }) else { return 0 }
        return (kind == .sell) ? cat.sellRatePerHour : cat.buyCostPerHour
    }

    static func currency(_ v: Double) -> String { String(format: "%.2f", v) }
}


import AppKit

enum ICSBuilder {
    /// Format like 20251021T130000Z (UTC) per RFC5545
    private static func utc(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.string(from: date)
    }

    static func makeICS(
        summary: String,
        start: Date,
        end: Date,
        location: String,
        description: String,
        attendees: [(name: String, email: String)] = []
    ) -> Data {
        let now = Date()
        let uid = UUID().uuidString + "@studioscheduler"
        var lines: [String] = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//StudioScheduler People//EN",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH",
            "BEGIN:VEVENT",
            "UID:\(uid)",
            "DTSTAMP:\(utc(now))",
            "DTSTART:\(utc(start))",
            "DTEND:\(utc(end))",
            "SUMMARY:\(summary)",
        ]
        if !location.isEmpty { lines.append("LOCATION:\(location)") }
        if !description.isEmpty { lines.append("DESCRIPTION:\(description.replacingOccurrences(of: "\n", with: "\\n"))") }

        // Optional attendees
        for a in attendees where !a.email.isEmpty {
            let cn = a.name.isEmpty ? a.email : a.name
            lines.append("ATTENDEE;CN=\(cn):mailto:\(a.email)")
        }

        lines.append(contentsOf: [
            "END:VEVENT",
            "END:VCALENDAR"
        ])
        // Join with CRLF is safest, but LF is widely accepted.
        return lines.joined(separator: "\n").data(using: .utf8) ?? Data()
    }

    /// Writes an .ics to a temp file and returns the URL.
    static func writeTempICS(filename: String, data: Data) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }
}

// MARK: - Rooms
struct Room: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var isActive: Bool = true

    // Deprecated legacy per-room fields:
    var sellRatePerHour: Double = 0
    var buyCostPerHour: Double = 0

    // OLD: var categoryID: UUID?
    // NEW: multiple categories
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

final class RoomStore: ObservableObject {
    @Published var rooms: [Room] = [] { didSet { save() } }
    static let shared = RoomStore()

    private let fileURL: URL = DataPaths.file("rooms.json")

    private init() { load() }

    func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode([Room].self, from: data)
            self.rooms = decoded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            self.rooms = []
        }
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(rooms)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("Save error: \(error)")
        }
    }

    func add(_ r: Room) { rooms.append(r); sort() }
    func update(_ r: Room) { if let i = rooms.firstIndex(where: { $0.id == r.id }) { rooms[i] = r; sort() } }
    func delete(_ r: Room) { rooms.removeAll { $0.id == r.id } }

    private func sort() {
        rooms.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Content
struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var projects: ProjectStore
    @EnvironmentObject private var people: PeopleStore
    @EnvironmentObject private var roomsStore: RoomStore
    @EnvironmentObject private var filters: Filters
    
    enum ViewMode: String, CaseIterable, Identifiable {
        case list = "List"
        case timeline = "Timeline"
        case week = "Week"     // ← NEW
        var id: String { rawValue }
    }
    
    @State private var viewMode: ViewMode = .list
    @State private var zoom: Double = 1.0
    @State private var showingEditor = false
    @State private var showingProjects = false
    @State private var editing: Session? = nil
    @State private var errorText: String? = nil
    @State private var selection: Set<Session.ID> = []
    @State private var showShareSheet = false
    @State private var pendingDelete: Session? = nil
    @State private var showDeleteConfirm: Bool = false
    @State private var reopenEditorDraft: Session? = nil
    @State private var shouldReopenEditor: Bool = false
    
    var body: some View {
            VStack(spacing: 6) {
                // Header
                VStack(spacing: 2) {
                    Text("Projector")
                        .font(.largeTitle)
                        .bold()
                    Text("plan, schedule, and manage your post-production world.")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
                .padding(.horizontal, 12)

                Divider()
                
        NavigationSplitView {
            SidebarView(
                rooms: rooms,
                clients: clients,
                projects: projects.projects,
                people: people.people,
                selectedProjectID: $filters.projectID,
                selectedPersonID: $filters.personID
            )
        } detail: {
            VStack(spacing: 0) {
                // Toolbar
                HStack(alignment: .center) {
                    Button(action: { newSession() }) { Label("New", systemImage: "plus") }
                    Button(action: {
                        if let id = selection.first, let s = store.sessions.first(where: { $0.id == id }) { edit(s) }
                    }) { Label("Edit", systemImage: "pencil") }
                        .disabled(selection.isEmpty)
                    Button(role: .destructive, action: {
                        if let id = selection.first,
                           let s = store.sessions.first(where: { $0.id == id }) {
                            pendingDelete = s
                            showDeleteConfirm = true
                        }
                    }) { Label("Delete", systemImage: "trash") }
                        .disabled(selection.isEmpty)
                    
                    Divider().frame(height: 22)
                    Button(action: { openWindow(id: "projects") }) { Label("Projects", systemImage: "folder") }
                    Button(action: { openWindow(id: "rooms") }) { Label("Rooms", systemImage: "building.2") }
                    Button(action: { openWindow(id: "peopleManager") }) { Label("People", systemImage: "person.2") }
                    
                    Spacer()
                    
                    // Week navigation when in Week view
                    if viewMode == .week {
                        Button("◀︎ Week") {
                            if let d = Calendar.current.date(byAdding: .day, value: -7, to: filters.day) { filters.day = d }
                        }
                        Button("Today") { filters.day = Date() }
                        Button("Week ▶︎") {
                            if let d = Calendar.current.date(byAdding: .day, value: 7, to: filters.day) { filters.day = d }
                        }
                        Divider().frame(height: 22)
                    }
                    
                    Picker("View", selection: $viewMode) {
                        ForEach(ViewMode.allCases) { m in Text(m.rawValue).tag(m) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                    
                    // ONE zoom slider for both day + week (not list)
                    if viewMode == .timeline || viewMode == .week {
                        HStack {
                            Image(systemName: "minus.magnifyingglass")
                            Slider(value: $zoom, in: 0.6...1.4)  // widened a bit for week
                                .frame(width: 160)
                            Image(systemName: "plus.magnifyingglass")
                        }
                        .help("Zoom timeline scale")
                    }
                }
            }
                .padding(8)
                
                
                Divider()
                
                // BEGIN Timeline/List content (always render timeline, even with zero sessions)
                switch viewMode {
                case .list:
                    if filteredSessions.isEmpty {
                        EmptyStateView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Table(filteredSessions, selection: $selection) {
                            TableColumn("Start") { s in Text(s.start.formatted(date: .abbreviated, time: .shortened)) }
                            TableColumn("End")   { s in Text(s.end.formatted(date: .omitted, time: .shortened)) }
                            TableColumn("Title", value: \.title)
                            TableColumn("Client", value: \.client)
                            TableColumn("Room", value: \.room)
                            TableColumn("Project") { s in Text(projectName(for: s.projectID)) }
                            TableColumn("People")  { s in Text(peopleNames(for: s.peopleIDs)) }
                            TableColumn("Dur (h)") { s in
                                Text(String(format: "%.1f", Double(s.durationMinutes) / 60.0)
                                    .replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? "."))
                            }
                            TableColumn("€ / h")   { s in Text(s.ratePerHour.map { String(format: "%.2f", $0) } ?? "–") }
                            TableColumn("Revenue") { s in Text(s.revenue.map { String(format: "%.2f", $0) } ?? "–") }
                        }
                        .onTapGesture(count: 2) {
                            if let id = selection.first,
                               let s = filteredSessions.first(where: { $0.id == id }) { edit(s) }
                        }
                    }
                    
                case .timeline:
                    // Always show all active rooms even with zero sessions
                    TimelineDayView(
                        day: filters.day,
                        sessions: filteredSessions,
                        rooms: dayRooms,
                        zoom: zoom
                    ) { s in
                        edit(s)
                    }
                    .environmentObject(store)
                    .environmentObject(people)
                    .environmentObject(projects)
                case .week:
                    TimelineWeekView(
                        weekStart: weekStart,
                        sessions: store.sessions,    // (or use filteredSessions if you want sidebar filters applied)
                        rooms: dayRooms,
                        zoom: zoom,
                        onSelect: { s in edit(s) }
                    )
                    .environmentObject(store)
                    .environmentObject(people)
                    .environmentObject(projects)
                    
                }
                // END Timeline/List content
            }
            
            // Editor & Manager sheets
            .sheet(isPresented: $showingEditor) {
                EditSessionSheet(
                    existing: editing,
                    rooms: rooms,
                    clients: clients,
                    projects: projects.projects,
                    people: people.people
                ) { result in
                    switch result {
                    case .cancel:
                        break
                    case .save(let s):
                        do {
                            if store.sessions.contains(where: { $0.id == s.id }) {
                                try store.update(s)
                            } else {
                                try store.add(s)
                            }
                            // success: clear any leftover draft
                            reopenEditorDraft = nil
                        } catch {
                            errorText = error.localizedDescription
                            reopenEditorDraft = s     // keep the draft so we can reopen
                        }
                    }
                    editing = nil
                }
                .environmentObject(roomsStore)
                .environmentObject(people)
                .environmentObject(RoomCategoryStore.shared)
                .environmentObject(PersonCategoryStore.shared)
                .frame(minWidth: 880, minHeight: 640)
            }
            
            .sheet(isPresented: $showingProjects) {
                ManageProjectsSheet()
                    .environmentObject(projects)
                    .frame(minWidth: 520, minHeight: 420)
            }
            
            
            .alert("Can't schedule",
                   isPresented: Binding(get: { errorText != nil },
                                       set: { if !$0 { errorText = nil } })) {
                Button("Continue Editing") {
                    if let draft = reopenEditorDraft {
                        editing = draft              // put the same draft back
                        showingEditor = true         // reopen editor
                    }
                    // reset flags
                    reopenEditorDraft = nil
                    shouldReopenEditor = false
                }
            } message: {
                Text(errorText ?? "This session overlaps (room or person) with another session.")
            }

                .alert("Delete this session?", isPresented: $showDeleteConfirm) {
                    Button("Delete", role: .destructive) {
                        if let s = pendingDelete { store.delete(s) }
                        pendingDelete = nil
                        selection.removeAll()
                    }
                    Button("Cancel", role: .cancel) {
                        pendingDelete = nil
                    }
                } message: {
                    if let s = pendingDelete {
                        Text("“\(s.title)” on \(s.start.formatted(date: .abbreviated, time: .shortened)) in \(s.room)")
                    } else {
                        Text("This action cannot be undone.")
                    }
                }
        }
    }

    private var rooms: [String] {
        ["All Rooms"] + roomsStore.rooms.map { $0.name }.sorted()
    }
    private var clients: [String] { ["All Clients"] + Set(store.sessions.map { $0.client }).sorted() }
    private var dayRooms: [String] {
        roomsStore.rooms.filter { $0.isActive }.map { $0.name }.sorted()
    }
    private var filteredSessions: [Session] {
        store.sessions.filter { s in
            let matchesRoom = (filters.room == "All Rooms") || s.room == filters.room
            let matchesClient = (filters.client == "All Clients") || s.client == filters.client
            let matchesQuery = filters.query.isEmpty ||
                s.title.localizedCaseInsensitiveContains(filters.query) ||
                s.client.localizedCaseInsensitiveContains(filters.query) ||
                s.room.localizedCaseInsensitiveContains(filters.query) ||
                s.notes.localizedCaseInsensitiveContains(filters.query)
            let sameDay = Calendar.current.isDate(s.start, inSameDayAs: filters.day)
            let matchesProject = (filters.projectID == nil) || s.projectID == filters.projectID
            let matchesPerson: Bool = {
                guard let pid = filters.personID else { return true }
                return s.peopleIDs.contains(pid)
            }()
            return matchesRoom && matchesClient && matchesQuery && sameDay && matchesProject && matchesPerson
        }
    }
    private var weekStart: Date {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Monday
        // ISO week start:
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: filters.day)
        return cal.date(from: comps) ?? filters.day
    }

    private func projectName(for id: UUID?) -> String {
        guard let id, let p = projects.projects.first(where: { $0.id == id }) else { return "–" }
        return p.isActive ? p.name : "\(p.name) (Completed)"
    }

    private func peopleNames(for ids: [UUID]) -> String {
        let map = Dictionary(uniqueKeysWithValues: people.people.map { ($0.id, $0.name) })
        let names = ids.compactMap { map[$0] }
        if names.isEmpty { return "–" }
        let joined = names.joined(separator: ", ")
        if joined.count <= 28 { return joined }

        // Fallback to initials (max 3 parts), all caps
        let compact = names.map { name in
            name.split(separator: " ")
                .prefix(3)
                .compactMap { $0.first }
                .map(String.init)
                .joined()
                .uppercased()
        }
        return compact.joined(separator: ", ")
    }

    private func newSession() { editing = nil; showingEditor = true }
    private func edit(_ s: Session) { editing = s; showingEditor = true }
}
// MARK: - Week View
struct TimelineWeekView: View {
    let weekStart: Date
    let sessions: [Session]
    let rooms: [String]
    let zoom: Double
    var onSelect: (Session) -> Void

    private var days: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: weekStart) }
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(spacing: 8) {
                ForEach(days, id: \.self) { day in
                    VStack(spacing: 6) {
                        Text(day.formatted(.dateTime.weekday(.wide).day().month()))
                            .font(.headline)
                        TimelineDayView(
                            day: day,
                            sessions: sessions.filter { Calendar.current.isDate($0.start, inSameDayAs: day) },
                            rooms: rooms,
                            zoom: zoom,
                            onSelect: onSelect,
                            condensed: true
                        )
                    }
                    .frame(minWidth: 220) // gives each day a comfortable width; tweak as you like
                }
            }
            .padding(8)
        }
    }
}

// MARK: - Sidebar
// MARK: - Sidebar
struct SidebarView: View {
    @EnvironmentObject private var filters: Filters
    @Environment(\.openWindow) private var openWindow   // <- needed for "Manage Clients…" button

    let rooms: [String]
    let clients: [String]
    let projects: [Project]
    let people: [Person]
    @Binding var selectedProjectID: UUID?
    @Binding var selectedPersonID: UUID?

    var body: some View {
        List {
            Section("Filters") {
                DatePicker("Day", selection: $filters.day, displayedComponents: .date)

                Picker("Room", selection: $filters.room) {
                    ForEach(rooms, id: \.self) { Text($0) }
                }

                // Client filter uses the simple String list (NOT ClientsStore)
                Picker("Client", selection: $filters.client) {
                    ForEach(clients, id: \.self) { Text($0) }
                }

                Picker("Project", selection: $selectedProjectID) {
                    Text("All Projects").tag(UUID?.none)
                    ForEach(projects) { p in
                        Text(p.isActive ? p.name : "\(p.name) (Completed)")
                            .tag(UUID?.some(p.id))
                    }
                }

                Picker("People", selection: $selectedPersonID) {
                    Text("All People").tag(UUID?.none)
                    ForEach(people) { person in
                        Text(person.name).tag(UUID?.some(person.id))
                    }
                }

                TextField("Search", text: $filters.query)

                HStack(spacing: 8) {
                    Button("Reset") { filters.reset() }
                        .buttonStyle(.bordered)

                    // Optional convenience button; remove if you don't want it here.
                    Button("Manage Clients…") { openWindow(id: "clients") }
                        .buttonStyle(.bordered)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 280)
        .navigationTitle("Projector")
    }
}

// MARK: - Empty State (macOS 13 compatible)
struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar").font(.system(size: 48)).padding(.bottom, 2)
            Text("No sessions").font(.title3).bold()
            Text("Click New to add your first session.").foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Editor Sheet
struct EditSessionSheet: View {
    enum Result { case cancel, save(Session) }
    
    var existing: Session?
    let rooms: [String]
    let clients: [String]
    let projects: [Project]
    let people: [Person]
    var onClose: (Result) -> Void
    
    @State private var title: String = ""
    @State private var client: String = ""
    @State private var room: String = ""
    @State private var start: Date = Date()
    @State private var duration: Int = 120
    @State private var ratePerHour: String = ""
    @State private var notes: String = ""
    @State private var selectedProjectID: UUID? = nil
    @State private var selectedPeople: Set<UUID> = []
    @State private var end: Date = Date()
    @State private var useEndTime: Bool = false   // if ON, duration derives from start→end
    @State private var durationHoursText: String = ""  // user-facing (e.g. "3.5" or "3,5")
    @State private var isUpdatingTime = false     // guard to avoid onChange feedback loops
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var roomsStore: RoomStore
    @EnvironmentObject private var peopleStore: PeopleStore      // ← add
    @EnvironmentObject private var roomCategoryStore: RoomCategoryStore
    @EnvironmentObject private var personCategoryStore: PersonCategoryStore
    @Environment(\.openWindow) private var openWindow
    @State private var showRooms = false
    @State private var useDefaultRate = true  // show computed rate from Room + People
    @State private var showShareSheet: Bool = false
    // Chosen categories for THIS booking
    @State private var selectedRoomCategoryID: UUID? = nil
    @State private var selectedPeopleRoles: [UUID: UUID] = [:]   // personID -> categoryID
    
    private var selectedProject: Project? {
        guard let id = selectedProjectID else { return nil }
        return projects.first(where: { $0.id == id })
    }

    private var defaultSellRate: Double {
        let roomPart: Double = {
            guard let cid = selectedRoomCategoryID,
                  let cat = roomCategoryStore.categories.first(where: { $0.id == cid }) else { return 0 }
            return cat.sellRatePerHour
        }()
        
        let peoplePart: Double = selectedPeople.reduce(0.0) { sum, pid in
            guard let cid = selectedPeopleRoles[pid],
                  let cat = personCategoryStore.categories.first(where: { $0.id == cid }) else { return sum }
            return sum + cat.sellRatePerHour
        }
        return roomPart + peoplePart
    }
    
    private func defaultRatePerHour() -> Double {
        
        let roomPart: Double = {
            guard let cid = selectedRoomCategoryID,
                  let cat = roomCategoryStore.categories.first(where: { $0.id == cid }) else { return 0 }
            return cat.sellRatePerHour
        }()
        
        let peoplePart: Double = selectedPeople.reduce(0.0) { sum, pid in
            guard let cid = selectedPeopleRoles[pid],
                  let cat = personCategoryStore.categories.first(where: { $0.id == cid }) else { return sum }
            return sum + cat.sellRatePerHour
        }
        return roomPart + peoplePart
    }
    
    // Snap helpers (30 min)
    
    private func nextHalfHour(from date: Date) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let minute = (comps.minute ?? 0)
        let add = (minute == 0 ? 30 : (minute <= 30 ? (30 - minute) : (60 - minute)))
        return cal.date(byAdding: .minute, value: add, to: date) ?? date
    }
    private func minutesToHoursText(_ minutes: Int) -> String {
        let h = Double(minutes) / 60.0
        // 1 decimal, localized decimal separator
        let s = String(format: "%.1f", h)
        return s.replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ".")
    }
    
    private func hoursTextToMinutes(_ text: String) -> Int? {
        let raw = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let h = Double(raw), h >= 0 else { return nil }
        // snap to 30 minutes (0.5h)
        let snappedHalfHours = (h * 2).rounded()
        return max(30, Int(snappedHalfHours * 30.0))  // min 30 min
    }
    
    private func snappedHalfHour(_ date: Date) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year,.month,.day,.hour,.minute], from: date)
        let minute = comps.minute ?? 0
        let snappedMinute = (minute < 15 ? 0 : (minute < 45 ? 30 : 60))
        var base = cal.date(from: DateComponents(year: comps.year, month: comps.month, day: comps.day, hour: comps.hour, minute: 0))!
        if snappedMinute == 60 { base = cal.date(byAdding: .hour, value: 1, to: base)! }
        else { base = cal.date(byAdding: .minute, value: snappedMinute, to: base)! }
        return base
    }
    
    private func clampEndAfterStart(_ start: Date, _ end: Date) -> Date {
        max(end, start.addingTimeInterval(30*60)) // at least 30 min
    }
    
    init(existing: Session?,
         rooms: [String],
         clients: [String],
         projects: [Project],
         people: [Person],
         onClose: @escaping (Result) -> Void) {
        self.existing = existing
        self.rooms = rooms
        self.clients = clients
        self.projects = projects
        self.people = people
        self.onClose = onClose
        
        // Title
        _title = State(initialValue: existing?.title ?? "Add Session Description")
        
        // Project / People
        _selectedProjectID = State(initialValue: existing?.projectID)
        _selectedPeople = State(initialValue: Set(existing?.peopleIDs ?? []))
        // Pre-fill chosen categories when editing existing session
        _selectedRoomCategoryID = State(initialValue: existing?.roomCategoryID)
        _selectedPeopleRoles    = State(initialValue: existing?.peopleRoles ?? [:])
        
        // Room
        _room = State(initialValue: existing?.room ?? (rooms.dropFirst().first ?? "Room A"))
        
        // Start / Duration / End
        let startDefault = existing?.start ?? nextHalfHour(from: Date())
        let minutesDefault = existing?.durationMinutes ?? 120
        let endDefault = startDefault.addingTimeInterval(TimeInterval(minutesDefault * 60))
        
        _start = State(initialValue: startDefault)
        _duration = State(initialValue: minutesDefault)
        _end = State(initialValue: endDefault)
        _durationHoursText = State(initialValue: minutesToHoursText(minutesDefault))
        _useEndTime = State(initialValue: false)
        
        // Client (prefer project’s client if session has none)
        if let pid = existing?.projectID,
           let p = projects.first(where: { $0.id == pid }),
           (existing?.client ?? "").isEmpty {
            _client = State(initialValue: p.client)
        } else {
            _client = State(initialValue: existing?.client ?? "")
        }
        
        // Notes
        _notes = State(initialValue: existing?.notes ?? "")
        
        // Rate behavior: if session had a custom rate, show it;
        // otherwise default to auto-computed (UI shows computed price read-only).
        if let existingRate = existing?.ratePerHour, existingRate > 0 {
            _useDefaultRate = State(initialValue: false)
            _ratePerHour = State(initialValue: String(format: "%.2f", existingRate))
        } else {
            _useDefaultRate = State(initialValue: true)
            _ratePerHour = State(initialValue: "")
        }
    }
    
    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            Text(existing == nil ? "New Session" : "Edit Session")
                .font(.title2).bold()
            Spacer().frame(height: 20)
            Form {
                // Title & Client
                HStack {
                        Spacer()
                        TextField("Title", text: $title)
                            .frame(width: 300)
                            .multilineTextAlignment(.center)
                    Spacer().frame(height: 80)
                    }
                // Room + Room Category
                HStack {
                    Spacer()
                    Picker("Room", selection: $room) {
                        ForEach(roomsStore.rooms.filter { $0.isActive }, id: \.name) { r in
                            Text(r.name).tag(r.name)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 300)
                    Picker("", selection: Binding(
                        get: { selectedRoomCategoryID },
                        set: { selectedRoomCategoryID = $0 }
                    )) {
                        Text("Category…").tag(UUID?.none)
                        if let r = roomsStore.rooms.first(where: { $0.name == room }) {
                            ForEach(r.categoryIDs, id: \.self) { cid in
                                if let cat = roomCategoryStore.categories.first(where: { $0.id == cid }) {
                                    Text(cat.name).tag(UUID?.some(cid))
                                }
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)
                    
                    Button("Manage Rooms…") {
                        openWindow(id: "rooms")
                    }
                        .buttonStyle(.bordered)
                    Spacer()
                }
                Spacer().frame(height: 24)
                .onChangeCompat(room) { _ in
                    if let r = roomsStore.rooms.first(where: { $0.name == room }) {
                        selectedRoomCategoryID = r.categoryIDs.first
                    } else {
                        selectedRoomCategoryID = nil
                    }
                }
                
                // Project
                Picker("Project", selection: $selectedProjectID) {
                    Text("None").tag(UUID?.none)
                    ForEach(projects) { p in
                        Text(p.isActive ? p.name : "\(p.name) (Completed)").tag(UUID?.some(p.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 300)
                Spacer().frame(height: 24)
                .onChangeCompat(selectedProjectID) { newID in
                    if let id = newID, let _ = projects.first(where: { $0.id == id }) {
                        // client is derived; no field to update anymore
                    }
                }
                if let p = selectedProject {
                    Text("Client: \(p.client)")
                        .foregroundColor(.secondary)
                        .font(.callout)
                        .padding(.leading, 4)
                }
                // People (★ this is the fragile part — fully closed now)
                // People (compact picker + chips)
                VStack(alignment: .leading, spacing: 10) {
                    Text("People").font(.headline)
                    
                    // Add people via a compact menu
                    HStack(spacing: 20) {
                        Menu {
                            // Add/remove people quickly
                            ForEach(peopleStore.people.filter { $0.isActive }) { person in
                                let isSelected = selectedPeople.contains(person.id)
                                Button {
                                    if isSelected {
                                        selectedPeople.remove(person.id)
                                        selectedPeopleRoles.removeValue(forKey: person.id)
                                    } else {
                                        selectedPeople.insert(person.id)
                                        if selectedPeopleRoles[person.id] == nil {
                                            selectedPeopleRoles[person.id] = person.categoryIDs.first
                                        }
                                    }
                                } label: {
                                    Label(person.name, systemImage: isSelected ? "checkmark.circle.fill" : "plus.circle")
                                }
                            }

                            if !selectedPeople.isEmpty {
                                Divider()
                                Button("Clear all", role: .destructive) {
                                    selectedPeople.removeAll()
                                    selectedPeopleRoles.removeAll()
                                }
                            }
                        } label: {
                            Label(selectedPeople.isEmpty ? "Add People…" : "Add/Remove People…", systemImage: "person.2.fill")
                        }
                        .frame(width: 180, alignment: .leading)   // ← apply width to the Menu
                        .controlSize(.small)                      // ← smaller height
                        //.menuStyle(.borderedButton)             // optional: different look
                        Spacer()
                    }
                    
                    // Selected people chips + per-person role pickers
                    if !selectedPeople.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(selectedPeople), id: \.self) { pid in
                                if let person = people.first(where: { $0.id == pid }) {
                                    HStack(spacing: 10) {
                                        // Chip with remove action
                                        HStack(spacing: 6) {
                                            Text(person.name)
                                                .lineLimit(1)
                                            if !person.role.isEmpty {
                                                Text("· \(person.role)")
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                            }
                                            Button {
                                                selectedPeople.remove(pid)
                                                selectedPeopleRoles.removeValue(forKey: pid)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                            }
                                            .buttonStyle(.borderless)
                                            .help("Remove \(person.name)")
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Color.gray.opacity(0.12), in: Capsule())
                                        
                                        // Role picker for this person
                                        HStack(spacing: 6) {
                                            Text("Role:").foregroundColor(.secondary)
                                            Picker("", selection: Binding(
                                                get: { selectedPeopleRoles[pid] },
                                                set: { selectedPeopleRoles[pid] = $0 }
                                            )) {
                                                Text("Select…").tag(UUID?.none)
                                                ForEach(person.categoryIDs, id: \.self) { cid in
                                                    if let cat = personCategoryStore.categories.first(where: { $0.id == cid }) {
                                                        Text(cat.name).tag(UUID?.some(cid))
                                                    }
                                                }
                                            }
                                            .pickerStyle(.menu)
                                            .frame(width: 200)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.top, 4)
                    } else {
                        Text("No people added yet")
                            .foregroundColor(.secondary)
                            .font(.callout)
                    }
                }
            }
            // Time controls
            Toggle("Set end time instead of duration", isOn: $useEndTime)
                .toggleStyle(.switch)
            
            DatePicker("Start", selection: $start, displayedComponents: [.date, .hourAndMinute])
                .onChangeCompat(start) { newValue in
                    guard !isUpdatingTime else { return }
                    isUpdatingTime = true
                    start = snappedHalfHour(newValue)
                    if useEndTime {
                        end = clampEndAfterStart(start, snappedHalfHour(end))
                        let mins = Int(end.timeIntervalSince(start) / 60)
                        durationHoursText = minutesToHoursText(max(30, mins))
                    } else {
                        if let mins = hoursTextToMinutes(durationHoursText) {
                            end = start.addingTimeInterval(TimeInterval(mins * 60))
                        } else {
                            end = start.addingTimeInterval(TimeInterval(120 * 60))
                        }
                    }
                    isUpdatingTime = false
                }
            
            DatePicker("End", selection: $end, displayedComponents: [.date, .hourAndMinute])
                .disabled(!useEndTime)
                .onChangeCompat(end) { newValue in
                    guard useEndTime, !isUpdatingTime else { return }
                    isUpdatingTime = true
                    end = clampEndAfterStart(start, snappedHalfHour(newValue))
                    let mins = Int(end.timeIntervalSince(start) / 60)
                    durationHoursText = minutesToHoursText(max(30, mins))
                    isUpdatingTime = false
                }
            
            HStack {
                Text("Duration (h)")
                TextField("e.g. 3.5", text: $durationHoursText)
                    .frame(width: 80)
                    .multilineTextAlignment(.trailing)
                    .disabled(useEndTime)
                    .onChangeCompat(durationHoursText) { _ in
                        guard !useEndTime, !isUpdatingTime else { return }
                        isUpdatingTime = true
                        if let mins = hoursTextToMinutes(durationHoursText) {
                            end = start.addingTimeInterval(TimeInterval(mins * 60))
                        }
                        isUpdatingTime = false
                    }
                Text("h").foregroundColor(.secondary)
            }
            
            HStack {
                Spacer()
                Toggle("Use default rate", isOn: $useDefaultRate)
                    .toggleStyle(.switch)

                if useDefaultRate {
                    Text("€ \(String(format: "%.2f", defaultRatePerHour()))/h")
                        .frame(width: 140, alignment: .trailing)
                } else {
                    TextField("Rate €/h", text: $ratePerHour)
                        .frame(width: 120)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                }
                Spacer()
            }
            .onChangeCompat(room) { _ in
                if useDefaultRate { ratePerHour = String(format: "%.2f", defaultRatePerHour()) }
            }
            .onChangeCompat(selectedPeople) { _ in
                if useDefaultRate { ratePerHour = String(format: "%.2f", defaultRatePerHour()) }
            }
            .onChangeCompat(useDefaultRate) { isOn in
                if isOn { ratePerHour = String(format: "%.2f", defaultRatePerHour()) }
            }

            
            TextField("Notes", text: $notes, axis: .vertical)
                .lineLimit(3, reservesSpace: true)
            
        } // Form
        
        // Footer buttons
        HStack {
            Button(existing == nil ? "Add" : "Save") {
                let rate: Double? = {
                    if useDefaultRate { return defaultSellRate }
                    return Double(ratePerHour.replacingOccurrences(of: ",", with: "."))
                }()
                
                let finalDurationMinutes: Int = {
                    if useEndTime {
                        let mins = Int(end.timeIntervalSince(start) / 60)
                        return max(30, mins - (mins % 30))
                    } else {
                        return hoursTextToMinutes(durationHoursText) ?? 120
                    }
                }()
                
                let clientValue: String = {
                    guard let id = selectedProjectID,
                          let p = projects.first(where: { $0.id == id }) else { return "" }
                    return p.client
                }()
                let session = Session(
                    id: existing?.id ?? UUID(),
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    client: clientValue,
                    room: room.trimmingCharacters(in: .whitespacesAndNewlines),
                    start: snappedHalfHour(start),
                    durationMinutes: finalDurationMinutes,
                    ratePerHour: rate,
                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                    projectID: selectedProjectID,
                    peopleIDs: Array(selectedPeople),
                    roomCategoryID: selectedRoomCategoryID,
                    peopleRoles: Dictionary(uniqueKeysWithValues: selectedPeople.map { pid in
                        (pid, selectedPeopleRoles[pid] ?? UUID())
                    })
                )
                
                onClose(.save(session))
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(
                title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                room.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                selectedProjectID == nil
            )
            
            Button("Export / Share .ics…") { showShareSheet = true }
                .buttonStyle(.bordered)
            
            Spacer()
        }
        
        .padding(.horizontal, 20)   // ← add this
        .padding(.bottom, 12)
        .padding(24)
        
        // Sheets attached to the editor root view
        .sheet(isPresented: $showShareSheet) {
            let attendeeList: [(String, String)] = people
                .filter { selectedPeople.contains($0.id) }
                .map { ($0.name, $0.email.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .filter { !$0.1.isEmpty }
            
            let startLocal = snappedHalfHour(start)
            let computedEnd: Date = {
                if useEndTime { return clampEndAfterStart(startLocal, end) }
                if let mins = hoursTextToMinutes(durationHoursText) {
                    return startLocal.addingTimeInterval(TimeInterval(mins * 60))
                }
                return startLocal.addingTimeInterval(120 * 60)
            }()
            
            ShareBookingSheet(
                summary: title.isEmpty ? "Session" : title,
                location: room,
                start: startLocal,
                end: computedEnd,
                descriptionText: {
                    var desc = ""
                    if let id = selectedProjectID, let p = projects.first(where: { $0.id == id }) {
                        desc += "Project: \(p.name)\nClient: \(p.client)\n"
                    } else if !client.isEmpty {
                        desc += "Client: \(client)\n"
                    }
                    if !notes.isEmpty { desc += "\nNotes:\n\(notes)\n" }
                    return desc
                }(),
                attendees: attendeeList
            )
        }
    }
}

// MARK: - Projects Manager
struct ManageProjectsSheet: View {
    @EnvironmentObject private var projects: ProjectStore
    @EnvironmentObject private var roomsStore: RoomStore
    @State private var showRooms = false
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var clientsStore: ClientsStore
    @Environment(\.openWindow) private var openWindow   // fixes “Cannot find 'openWindow'"
    
    @State private var name: String = ""
    @State private var notes: String = ""
    @State private var selectedClientID: UUID? = nil
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Projects").font(.title2).bold()
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .keyboardShortcut("w", modifiers: [.command])
            }
            .padding(12)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TextField("New project name", text: $name)

                    Picker("Client", selection: $selectedClientID) {
                        Text("Choose…").tag(UUID?.none)
                        ForEach(clientsStore.clients.filter { $0.isActive }) { c in
                            Text(c.name).tag(UUID?.some(c.id))
                        }
                    }
                    .frame(width: 220)

                    Button("Manage Clients…") { openWindow(id: "clients") }
                        .buttonStyle(.bordered)

                    Button("Add") {
                        let nm = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !nm.isEmpty else { return }

                        let clientName: String = {
                            guard let id = selectedClientID,
                                  let c = clientsStore.clients.first(where: { $0.id == id }) else { return "" }
                            return c.name
                        }()

                        let p = Project(name: nm, client: clientName, isActive: true, notes: notes)
                        projects.add(p)
                        name = ""
                        selectedClientID = nil
                        notes = ""
                    }
                    .keyboardShortcut(.return)
                }
                List {
                    Section("Active") {
                        ForEach(projects.projects.filter { $0.isActive }) { p in
                            ProjectRow(project: p)
                        }
                    }
                    Section("Completed") {
                        ForEach(projects.projects.filter { !$0.isActive }) { p in
                            ProjectRow(project: p)
                        }
                    }
                }
            }
            .padding(16)
        }
    }
}
// MARK: - Project Dashboard
struct ProjectDashboardView: View {
    let project: Project

    @EnvironmentObject private var sessions: SessionStore
    @EnvironmentObject private var projects: ProjectStore
    @EnvironmentObject private var people: PeopleStore
    @EnvironmentObject private var rooms: RoomStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    // Optional date filter
    @State private var useDateFilter = false
    @State private var rangeStart: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var rangeEnd: Date = Date()

    // Editing from the dashboard
    @State private var editing: Session? = nil
    @State private var showEditor = false
    @State private var errorText: String? = nil

    private var filteredSessions: [Session] {
        sessions.sessions
            .filter { $0.projectID == project.id }
            .filter { s in
                guard useDateFilter else { return true }
                return (s.start >= rangeStart) && (s.start < rangeEnd)
            }
            .sorted { $0.start < $1.start }
    }

    private var totalMinutes: Int {
        filteredSessions.reduce(0) { $0 + $1.durationMinutes }
    }
    private var totalHours: Double { Double(totalMinutes) / 60.0 }

    private var totalRevenue: Double {
        filteredSessions.reduce(0) { sum, s in
            sum + Finance.sessionRevenue(s, rooms: rooms.rooms, people: people.people)
        }
    }
    private var totalCost: Double {
        filteredSessions.reduce(0) { sum, s in
            sum + Finance.sessionCost(s, rooms: rooms.rooms, people: people.people)
        }
    }
    private var profit: Double { totalRevenue - totalCost }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.title2).bold()
                    Text(project.client)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Budget…") { openWindow(id: "budget", value: project.id) }
                    .keyboardShortcut("b", modifiers: [.command])

            }
            .padding(12)

            Divider()

            // KPIs + Filters
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 24) {
                    KPI(title: "Sessions", value: "\(filteredSessions.count)")
                    KPI(title: "Hours", value: String(format: "%.2f h", totalHours))
                    KPI(title: "Revenue", value: "€ " + Finance.currency(totalRevenue))
                    KPI(title: "Cost", value: "€ " + Finance.currency(totalCost))
                    KPI(title: "Profit", value: "€ " + Finance.currency(profit))
                }

                HStack(spacing: 12) {
                    Toggle("Filter by date", isOn: $useDateFilter)
                    if useDateFilter {
                        DatePicker("From", selection: $rangeStart, displayedComponents: [.date])
                        DatePicker("To", selection: $rangeEnd, displayedComponents: [.date])
                    }
                    Spacer()
                }
            }
            .padding(12)

            Divider()

            // Sessions table
            if filteredSessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "calendar.badge.exclamationmark").font(.system(size: 42))
                    Text("No sessions for this project").foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(filteredSessions) {
                    TableColumn("Start") { s in Text(s.start.formatted(date: .abbreviated, time: .shortened)) }
                    TableColumn("End") { s in Text(s.end.formatted(date: .omitted, time: .shortened)) }
                    TableColumn("Title", value: \.title)
                    TableColumn("Room", value: \.room)
                    TableColumn("People") { s in Text(peopleNames(for: s.peopleIDs)) }
                    TableColumn("Hours") { s in Text(String(format: "%.2f", Double(s.durationMinutes)/60.0)) }
                    TableColumn("Revenue") { s in
                        let v = Finance.sessionRevenue(s, rooms: rooms.rooms, people: people.people)
                        Text("€ " + Finance.currency(v))
                    }
                    TableColumn("Cost") { s in
                        let v = Finance.sessionCost(s, rooms: rooms.rooms, people: people.people)
                        Text("€ " + Finance.currency(v))
                    }
                }
                .onTapGesture(count: 2) {
                    // Double-click to edit the first selected row (Table doesn't expose selection here; we open last row tapped)
                    // Simple approach: open the most recent session in the filtered list (or you can wire a @State selection)
                    if let s = filteredSessions.last {
                        editing = s
                        showEditor = true
                    }
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            EditSessionSheet(
                existing: editing,
                rooms: ["All Rooms"] + rooms.rooms.map { $0.name }.sorted(),
                clients: Array(Set(sessions.sessions.map { $0.client })).sorted().withPrefix("All Clients"),
                projects: projects.projects,
                people: people.people
            ) { result in
                if case .save(let s) = result {
                    do {
                        if sessions.sessions.contains(where: { $0.id == s.id }) {
                            try sessions.update(s)
                        } else {
                            try sessions.add(s)
                        }
                    } catch {
                        errorText = error.localizedDescription
                    }
                }
            }

            .environmentObject(rooms)   // pass RoomStore to the editor
            .environmentObject(people)  // pass PeopleStore to the editor
            .frame(minWidth: 640)
        }
        .alert("Can't update", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
        .padding(.bottom, 8)
        .frame(minWidth: 820, minHeight: 540)
    }

    private func peopleNames(for ids: [UUID]) -> String {
        let dict = Dictionary(uniqueKeysWithValues: people.people.map { ($0.id, $0.name) })
        let list = ids.compactMap { dict[$0] }
        if list.isEmpty { return "–" }
        let joined = list.joined(separator: ", ")
        if joined.count <= 32 { return joined }
        return list.map { name in
            name.split(separator: " ").prefix(3).compactMap { $0.first }.map(String.init).joined().uppercased()
        }.joined(separator: ", ")
    }
}

private struct KPI: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(value).font(.title3).bold()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

private extension Array where Element == String {
    func withPrefix(_ p: String) -> [String] { [p] + self }
}

struct ProjectRow: View {
    @EnvironmentObject private var projects: ProjectStore
    @State var project: Project
    @State private var editingName = false
    @State private var editingClient = false
    @State private var showDeleteConfirm = false   // 👈 Add this

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 12) {
            if editingName {
                TextField("Name", text: $project.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 180)
            } else {
                Text(project.name)
                    .bold()
                    .frame(minWidth: 180, alignment: .leading)
            }

            if editingClient {
                TextField("Client", text: $project.client)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 160)
            } else {
                Text(project.client)
                    .foregroundColor(.secondary)
                    .frame(minWidth: 160, alignment: .leading)
            }

            Spacer()

            Button("Open…") {
                openWindow(id: "projectDashboard", value: project.id)
            }
            Button("Budgets…") {
                openWindow(id: "budget", value: project.id)
            }

            Button(project.isActive ? "Complete" : "Activate") {
                var p = project
                p.isActive.toggle()
                projects.update(p)
                project = p
            }
            .buttonStyle(.bordered)

            Menu("•••") {
                Button(editingName ? "Stop Editing Name" : "Edit Name") {
                    editingName.toggle()
                    if !editingName { projects.update(project) }
                }

                Button(editingClient ? "Stop Editing Client" : "Edit Client") {
                    editingClient.toggle()
                    if !editingClient { projects.update(project) }
                }

                Divider()

                Button("Delete", role: .destructive) {
                    showDeleteConfirm = true   // 👈 Trigger confirmation
                }
            }
        }
        .padding(.vertical, 4)
        // ✅ Confirmation dialog outside the menu
        .confirmationDialog(
            "Delete Project?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                projects.delete(project)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deleting is undoable. Are you sure?")
        }
    }
}



// MARK: - People Manager
struct ManagePeopleSheet: View {
    @EnvironmentObject private var people: PeopleStore      // ← IMPORTANT: name is `people`
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var personCategoryStore: PersonCategoryStore
    @Environment(\.openWindow) private var openWindow

    @State private var name: String = ""
    @State private var role: String = ""
    @State private var email: String = ""
    @State private var showPersonCategories = false

    private func isValidEmail(_ s: String) -> Bool {
        let pattern = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        return NSPredicate(format: "SELF MATCHES %@", pattern).evaluate(with: s)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("People").font(.title3).bold()
                Spacer()
                Button("Manage Categories…") { openWindow(id: "personCategories") }
                    .buttonStyle(.bordered)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .keyboardShortcut("w", modifiers: [.command])
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            Divider()

            // Add row
            HStack(spacing: 8) {
                TextField("New person name", text: $name)
                TextField("Role (optional)", text: $role)
                TextField("Email (optional)", text: $email)
                Button("Add") {
                    let nm = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let rl = role.trimmingCharacters(in: .whitespacesAndNewlines)
                    let em = email.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !nm.isEmpty else { return }
                    if !em.isEmpty && !isValidEmail(em) { NSSound.beep(); return }
                    var p = Person(name: nm, role: rl, isActive: true)
                    p.email = em
                    people.add(p)                    // ← use `people` store
                    name = ""; role = ""; email = ""
                }
                .keyboardShortcut(.return)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .controlSize(.small)

            Divider()

            // Lists
            List {
                Section("Active") {
                    ForEach($people.people) { $p in
                        if p.isActive {
                            PersonRow(person: $p)   // ← pass binding
                        }
                    }
                }
                Section("Inactive") {
                    ForEach($people.people) { $p in
                        if !p.isActive {
                            PersonRow(person: $p)
                        }
                    }
                }
            }
            .environment(\.defaultMinListRowHeight, 26)
            .listStyle(.inset)
            .controlSize(.small)
            .frame(minHeight: 140)
        }
    }
}
struct ManagePersonCategoriesSheet: View {
    @EnvironmentObject private var store: PersonCategoryStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var sell: String = ""
    @State private var buy: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("People Categories").font(.title3).bold()
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            Divider()

            // Add row
            HStack(spacing: 8) {
                TextField("New category name", text: $name)
                TextField("Sell €/h", text: $sell)
                    .frame(width: 90).multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                TextField("Buy €/h", text: $buy)
                    .frame(width: 90).multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    let nm = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !nm.isEmpty else { return }
                    let c = PersonCategory(
                        name: nm,
                        sellRatePerHour: Double(sell.replacingOccurrences(of: ",", with: ".")) ?? 0,
                        buyCostPerHour: Double(buy.replacingOccurrences(of: ",", with: ".")) ?? 0,
                        isActive: true
                    )
                    store.add(c)
                    name = ""; sell = ""; buy = ""
                }
                .keyboardShortcut(.return)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .controlSize(.small)

            Divider()

            List {
                Section("Active") {
                    ForEach(store.categories.filter { $0.isActive }) { c in
                        PersonCategoryRow(category: c)
                            .environmentObject(store)
                    }
                }
                Section("Inactive") {
                    ForEach(store.categories.filter { !$0.isActive }) { c in
                        PersonCategoryRow(category: c)
                            .environmentObject(store)
                    }
                }
            }
            .listStyle(.inset)
            .environment(\.defaultMinListRowHeight, 28)
        }
    }
}

private struct PersonCategoryRow: View {
    @EnvironmentObject private var store: PersonCategoryStore
    @State var category: PersonCategory
    @State private var editingName = false

    @State private var sellText: String
    @State private var buyText: String

    init(category: PersonCategory) {
        _category = State(initialValue: category)
        _sellText = State(initialValue:
            category.sellRatePerHour == 0 ? "" : String(format: "%.2f", category.sellRatePerHour))
        _buyText = State(initialValue:
            category.buyCostPerHour == 0 ? "" : String(format: "%.2f", category.buyCostPerHour))
    }

    var body: some View {
        HStack(spacing: 12) {
            if editingName {
                TextField("Name", text: $category.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 220)
            } else {
                Text(category.name).bold().frame(minWidth: 220, alignment: .leading)
            }

            HStack(spacing: 6) {
                Text("Sell €/h").foregroundColor(.secondary)
                TextField("0", text: $sellText)
                    .frame(width: 80)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .onChangeCompat(sellText) { _ in persist() }
            }

            HStack(spacing: 6) {
                Text("Buy €/h").foregroundColor(.secondary)
                TextField("0", text: $buyText)
                    .frame(width: 80)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .onChangeCompat(buyText) { _ in persist() }
            }

            Spacer()

            Toggle("Active", isOn: Binding(
                get: { category.isActive },
                set: { v in category.isActive = v; persist() }
            )).labelsHidden()

            Menu("•••") {
                Button(editingName ? "Stop Editing Name" : "Edit Name") {
                    editingName.toggle()
                    if !editingName { persist() }
                }
                Divider()
                ConfirmingDestructiveButton("Delete",
                    title: "Delete Category",
                    onConfirm: { store.delete(category) }
                )
            }

        }
        .padding(.vertical, 4)
    }

    private func persist() {
        let sell = Double(sellText.replacingOccurrences(of: ",", with: ".")) ?? category.sellRatePerHour
        let buy  = Double(buyText.replacingOccurrences(of: ",", with: ".")) ?? category.buyCostPerHour
        var c = category
        c.sellRatePerHour = sell
        c.buyCostPerHour  = buy
        store.update(c)
        category = c
    }
}


// MARK: - Rooms Manager
struct ManageRoomsSheet: View {
    @EnvironmentObject private var rooms: RoomStore
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var roomCategoryStore: RoomCategoryStore
    @Environment(\.openWindow) private var openWindow

    @State private var name: String = ""
    @State private var sell: String = ""
    @State private var buy: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Rooms").font(.title2).bold()
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .keyboardShortcut("w", modifiers: [.command])
                // Open the room categories manager in its own window
                Button("Manage Categories…") {
                    openWindow(id: "roomCategories")
                }
                .buttonStyle(.bordered)
            }
            .padding(12)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TextField("New room name", text: $name)
                    TextField("Sell €/h", text: $sell)
                        .frame(width: 90)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                    TextField("Buy €/h", text: $buy)
                        .frame(width: 90)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        let r = Room(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            isActive: true,
                            sellRatePerHour: Double(sell.replacingOccurrences(of: ",", with: ".")) ?? 0,
                            buyCostPerHour: Double(buy.replacingOccurrences(of: ",", with: ".")) ?? 0
                        )
                        guard !r.name.isEmpty else { return }
                        rooms.add(r)
                        name = ""; sell = ""; buy = ""
                    }
                    .keyboardShortcut(.return)
                }

                List {
                    Section("Active") {
                        ForEach(rooms.rooms.filter { $0.isActive }) { r in
                            RoomRowView(room: r)
                        }
                    }
                    Section("Inactive") {
                        ForEach(rooms.rooms.filter { !$0.isActive }) { r in
                            RoomRowView(room: r)
                        }
                    }
                }

            }
            .padding(16)
        }
    }
}
// MARK: - Room row
struct RoomRowView: View {
    @EnvironmentObject private var rooms: RoomStore
    @EnvironmentObject private var roomCategoryStore: RoomCategoryStore
    @State var room: Room
    @State private var showDeleteConfirm = false   // ← add this

    var body: some View {
        HStack(spacing: 12) {
            TextField("Name", text: $room.name)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 180)
                .onSubmit { persist() }
                .onChangeCompat(room.name) { _ in persist() }

            // Categories (multi-select)
            Menu {
                ForEach(roomCategoryStore.categories) { c in
                    if c.isActive {
                        let isOn = room.categoryIDs.contains(c.id)
                        Button {
                            if isOn {
                                room.categoryIDs.removeAll { $0 == c.id }
                            } else if !room.categoryIDs.contains(c.id) {
                                room.categoryIDs.append(c.id)
                            }
                            persist()
                        } label: {
                            Label(c.name, systemImage: isOn ? "checkmark" : "")
                        }
                    }
                }

                if !room.categoryIDs.isEmpty {
                    Divider()
                    Button("Clear All", role: .destructive) {
                        room.categoryIDs.removeAll()
                        persist()
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selectedCategoryNames.isEmpty ? "No Categories"
                         : selectedCategoryNames.joined(separator: ", "))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .foregroundColor(.secondary)
                }
            }
            .frame(minWidth: 220)

            // Effective rates (first selected category, fallback to legacy)
            let firstCat: RoomCategory? = room.categoryIDs
                .compactMap { cid in roomCategoryStore.categories.first { $0.id == cid } }
                .first

            let effectiveSell = firstCat?.sellRatePerHour ?? room.sellRatePerHour
            let effectiveBuy  = firstCat?.buyCostPerHour  ?? room.buyCostPerHour

            Text("Sell €/h: \(String(format: "%.2f", effectiveSell))")
                .foregroundColor(.secondary)
                .frame(minWidth: 120, alignment: .leading)

            Text("Buy €/h: \(String(format: "%.2f", effectiveBuy))")
                .foregroundColor(.secondary)
                .frame(minWidth: 110, alignment: .leading)

            Spacer()

            Toggle("Active", isOn: Binding(
                get: { room.isActive },
                set: { v in room.isActive = v; persist() }
            ))
            .labelsHidden()

            Menu("•••") {
                Button("Delete", role: .destructive) {
                    showDeleteConfirm = true       // ← trigger dialog
                }
            }
        }
        .padding(.vertical, 4)
        // ← attach the dialog to the row container (reliable in List on macOS)
        .confirmationDialog(
            "Delete Room?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                rooms.delete(room)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deleting is undoable. Are you sure?")
        }
    }

    private var selectedCategoryNames: [String] {
        roomCategoryStore.categories
            .filter { room.categoryIDs.contains($0.id) }
            .map { $0.name }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func persist() { rooms.update(room) }
}


// MARK: - Person Categories Manager (Window content)
struct ManagePersonCategoriesView: View {
    @EnvironmentObject private var store: PersonCategoryStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var sellText: String = ""
    @State private var buyText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Person Categories").font(.title2).bold()
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .keyboardShortcut("w", modifiers: [.command])
            }
            .padding(12)

            Divider()

            // Add row
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    TextField("New category name", text: $name)
                    TextField("Sell €/h", text: $sellText)
                        .frame(width: 90)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                    TextField("Buy €/h", text: $buyText)
                        .frame(width: 90)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)

                    Button("Add") {
                        let nm  = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let sell = Double(sellText.replacingOccurrences(of: ",", with: ".")) ?? 0
                        let buy  = Double(buyText.replacingOccurrences(of: ",", with: ".")) ?? 0
                        guard !nm.isEmpty else { return }
                        let c = PersonCategory(name: nm, sellRatePerHour: sell, buyCostPerHour: buy, isActive: true)
                        store.add(c)
                        name = ""; sellText = ""; buyText = ""
                    }
                    .keyboardShortcut(.return)
                }

                // Lists
                List {
                    Section("Active") {
                        ForEach(store.categories.filter { $0.isActive }) { c in
                            PersonCategoryRow(category: c)
                        }
                    }
                    Section("Inactive") {
                        ForEach(store.categories.filter { !$0.isActive }) { c in
                            PersonCategoryRow(category: c)
                        }
                    }
                }
            }
            .padding(16)
        }
    }
}


struct ManageRoomCategoriesSheet: View {
    @EnvironmentObject private var store: RoomCategoryStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var sell: String = ""
    @State private var buy: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Room Categories").font(.title3).bold()
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            Divider()

            // Add row
            HStack(spacing: 8) {
                TextField("New category name", text: $name)
                TextField("Sell €/h", text: $sell)
                    .frame(width: 90).multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                TextField("Buy €/h", text: $buy)
                    .frame(width: 90).multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    let nm = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !nm.isEmpty else { return }
                    let c = RoomCategory(
                        name: nm,
                        sellRatePerHour: Double(sell.replacingOccurrences(of: ",", with: ".")) ?? 0,
                        buyCostPerHour: Double(buy.replacingOccurrences(of: ",", with: ".")) ?? 0,
                        isActive: true
                    )
                    store.add(c)
                    name = ""; sell = ""; buy = ""
                }
                .keyboardShortcut(.return)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .controlSize(.small)

            Divider()

            List {
                Section("Active") {
                    ForEach(store.categories.filter { $0.isActive }) { c in
                        RoomCategoryRow(category: c)
                            .environmentObject(store)
                    }
                }
                Section("Inactive") {
                    ForEach(store.categories.filter { !$0.isActive }) { c in
                        RoomCategoryRow(category: c)
                            .environmentObject(store)
                    }
                }
            }
            .listStyle(.inset)
            .environment(\.defaultMinListRowHeight, 28)
        }
    }
}
// MARK: - Room Categories Manager Window
struct ManageRoomCategoriesView: View {
    @EnvironmentObject private var roomCategoryStore: RoomCategoryStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var sellText: String = ""
    @State private var buyText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Room Categories").font(.title2).bold()
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .keyboardShortcut("w", modifiers: [.command])
            }
            .padding(12)

            Divider()

            // Add row
            HStack(spacing: 8) {
                TextField("New category name", text: $name)
                TextField("Sell €/h", text: $sellText)
                    .frame(width: 100)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                TextField("Buy €/h", text: $buyText)
                    .frame(width: 100)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    let nm = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !nm.isEmpty else { return }
                    let sell = Double(sellText.replacingOccurrences(of: ",", with: ".")) ?? 0
                    let buy  = Double(buyText.replacingOccurrences(of: ",", with: ".")) ?? 0
                    roomCategoryStore.add(RoomCategory(name: nm, sellRatePerHour: sell, buyCostPerHour: buy, isActive: true))
                    name = ""; sellText = ""; buyText = ""
                }
                .keyboardShortcut(.return)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Lists
            List {
                Section("Active") {
                    ForEach(roomCategoryStore.categories.filter { $0.isActive }) { c in
                        RoomCategoryRow(category: c)
                    }
                }
                Section("Inactive") {
                    ForEach(roomCategoryStore.categories.filter { !$0.isActive }) { c in
                        RoomCategoryRow(category: c)
                    }
                }
            }
            .listStyle(.inset)
            .environment(\.defaultMinListRowHeight, 28)
            .padding(.bottom, 8)
        }
        .frame(minWidth: 620, minHeight: 420)
    }
}

private struct RoomCategoryRow: View {
    @EnvironmentObject private var roomCategoryStore: RoomCategoryStore
    @State var category: RoomCategory

    @State private var editingName = false
    @State private var sellText: String
    @State private var buyText: String
    @State private var showDeleteConfirm = false

    init(category: RoomCategory) {
        _category = State(initialValue: category)
        _sellText = State(initialValue: category.sellRatePerHour == 0 ? "" : String(format: "%.2f", category.sellRatePerHour))
        _buyText  = State(initialValue: category.buyCostPerHour  == 0 ? "" : String(format: "%.2f", category.buyCostPerHour))
    }

    var body: some View {
        HStack(spacing: 12) {
            if editingName {
                TextField("Name", text: $category.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 220)
                    .onSubmit { persist() }
                    .onChangeCompat(category.name) { _ in persist() }
            } else {
                Text(category.name)
                    .bold()
                    .frame(minWidth: 220, alignment: .leading)
            }
            
            HStack(spacing: 6) {
                Text("Sell €/h").foregroundColor(.secondary)
                TextField("0", text: $sellText)
                    .frame(width: 90)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { persist() }
                    .onChangeCompat(sellText) { _ in persist() }
            }
            
            HStack(spacing: 6) {
                Text("Buy €/h").foregroundColor(.secondary)
                TextField("0", text: $buyText)
                    .frame(width: 90)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { persist() }
                    .onChangeCompat(buyText) { _ in persist() }
            }
            
            Spacer()
            
            Toggle("Active", isOn: Binding(
                get: { category.isActive },
                set: { v in category.isActive = v; persist() }
            ))
            .labelsHidden()
            
            Menu("•••") {
                Button(editingName ? "Stop Editing Name" : "Edit Name") {
                    editingName.toggle()
                    if !editingName { persist() }
                }
                Divider()
                Button("Delete", role: .destructive) { showDeleteConfirm = true }
            }
            .alert("Delete Room Category", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) { roomCategoryStore.delete(category) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Deleting is undoable. Are you sure?")
            }
        }
        .padding(.vertical, 4)
    }

    private func persist() {
        // parse rates
        let sell = Double(sellText.replacingOccurrences(of: ",", with: ".")) ?? category.sellRatePerHour
        let buy  = Double(buyText.replacingOccurrences(of: ",", with: ".")) ?? category.buyCostPerHour
        category.sellRatePerHour = sell
        category.buyCostPerHour  = buy
        roomCategoryStore.update(category)
    }
}
struct PersonRow: View {
    @EnvironmentObject private var people: PeopleStore
    @EnvironmentObject private var personCategoryStore: PersonCategoryStore
    @Binding var person: Person   // ✅ binding to the store

    var body: some View {
        HStack(spacing: 10) {
            // Name
            TextField("Name", text: $person.name)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 220)
                .onSubmit { persist() }
                .onChangeCompat(person.name) { _ in persist() }

            // Role
            TextField("Role", text: $person.role)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 140)
                .onSubmit { persist() }
                .onChangeCompat(person.role) { _ in persist() }

            // Email
            HStack(spacing: 8) {
                TextField("Email", text: $person.email)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 220)
                    .onSubmit { persist() }
                    .onChangeCompat(person.email) { _ in persist() }

                Button {
                    guard !person.email.isEmpty,
                          let url = URL(string: "mailto:\(person.email)") else { NSSound.beep(); return }
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "envelope")
                }
                .buttonStyle(.borderless)
                .help("Compose email")
                .controlSize(.small)
                .padding(.vertical, 2)
            }

            // ✅ Categories (multi-select menu)
            Menu {
                ForEach(personCategoryStore.categories) { c in
                    if c.isActive {
                        let isOn = person.categoryIDs.contains(c.id)
                        Button {
                            if isOn {
                                person.categoryIDs.removeAll { $0 == c.id }
                            } else {
                                if !person.categoryIDs.contains(c.id) {
                                    person.categoryIDs.append(c.id)
                                }
                            }
                            persist()
                        } label: {
                            Label(c.name, systemImage: isOn ? "checkmark" : "")
                        }
                    }
                }

                if !person.categoryIDs.isEmpty {
                    Divider()
                    Button("Clear All", role: .destructive) {
                        person.categoryIDs.removeAll()
                        persist()
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    let names = personCategoryStore.categories
                        .filter { person.categoryIDs.contains($0.id) }
                        .map { $0.name }
                        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                    Text(names.isEmpty ? "No Categories" : names.joined(separator: ", "))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .foregroundColor(.secondary)
                }
            }
            .frame(minWidth: 220)

            // Rates (from first selected category)
            let firstCat: PersonCategory? = person.categoryIDs
                .compactMap { cid in personCategoryStore.categories.first { $0.id == cid } }
                .first

            Text("Sell €/h: \(String(format: "%.2f", firstCat?.sellRatePerHour ?? 0))")
                .foregroundColor(.secondary)
                .frame(minWidth: 120, alignment: .leading)

            Text("Buy €/h: \(String(format: "%.2f", firstCat?.buyCostPerHour ?? 0))")
                .foregroundColor(.secondary)
                .frame(minWidth: 110, alignment: .leading)

            Spacer()

            // Active toggle
            Toggle("Active", isOn: $person.isActive)
                .labelsHidden()
                .toggleStyle(.switch)
                .onChange(of: person.isActive) { _, _ in
                    withAnimation { persist() }
                }
        }
        .padding(.vertical, 4)
    }

    private func persist() {
        people.update(person)
    }
}

// MARK: - Timeline Day View
struct TimelineDayView: View {
    let day: Date
    let sessions: [Session]
    let rooms: [String]
    let zoom: Double
    var onSelect: (Session) -> Void
    var condensed: Bool = false
    
    @EnvironmentObject private var projects: ProjectStore
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var people: PeopleStore
    
    private var dayStart: Date { Calendar.current.startOfDay(for: day) }
    private var dayEnd: Date { Calendar.current.date(byAdding: .day, value: 1, to: dayStart)! }
    
    private var hourWidth: CGFloat {
        // Compact base width in condensed mode to fit multiple days on screen.
        let base: CGFloat = condensed ? 12.0 : 80.0
        return CGFloat((base * zoom).rounded())
    }
    private var totalHours: Int { 24 }
    private var contentWidth: CGFloat { CGFloat(totalHours) * hourWidth }
    private let snapMinutes: Double = 30
    
    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(spacing: 0) {
                // Hour tick header (labels at the LEFT edge of each hour box)
                if !condensed {
                    ZStack(alignment: .topLeading) {
                        HourGrid(totalHours: totalHours, hourWidth: hourWidth, height: 28)
                        
                        HStack(spacing: 0) {
                            ForEach(0..<totalHours, id: \.self) { h in
                                Text(String(format: "%02d:00", h))
                                    .font(.system(size: 11).monospacedDigit())
                                    .frame(width: hourWidth, alignment: .leading)
                            }
                        }
                    }
                    .frame(width: contentWidth)
                    .overlay(alignment: .bottomLeading) {
                        Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1)
                    }
                }
                
                // One row per room
                ForEach(rooms, id: \.self) { room in
                    TimelineRoomRow(
                        room: room,
                        dayStart: dayStart,
                        dayEnd: dayEnd,
                        hourWidth: hourWidth,
                        contentWidth: contentWidth,
                        sessions: sessions.filter { $0.room == room },
                        color: color(for: room),
                        snapMinutes: snapMinutes,
                        onSelect: onSelect,
                        peopleNames: { ids in self.peopleNames(for: ids) },
                        projectName: { id, client in self.projectTitle(id, fallbackClient: client) }   // ← add this
                    )
                    .environmentObject(store)
                }
            }
            .padding(.bottom, 8)
        }
        .background(Color(NSColor.textBackgroundColor))
    }
    
    private func color(for room: String) -> Color {
        var hasher = Hasher(); hasher.combine(room)
        let hue = Double(abs(hasher.finalize()) % 256) / 256.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.85)
    }
    private func projectTitle(_ id: UUID?, fallbackClient: String) -> String {
        guard let id,
              let p = projects.projects.first(where: { $0.id == id }) else {
            return fallbackClient           // if no project, show client
        }
        return p.isActive ? p.name : "\(p.name) (Completed)"
    }

    private func peopleNames(for ids: [UUID]) -> String {
        let map = Dictionary(uniqueKeysWithValues: people.people.map { ($0.id, $0.name) })
        let names = ids.compactMap { map[$0] }
        if names.isEmpty { return "–" }
        let joined = names.joined(separator: ", ")
        if joined.count <= 28 { return joined }
        
        // Fallback to initials (max 3 parts), all caps
        let compact = names.map { name in
            name.split(separator: " ")
                .prefix(3)
                .compactMap { $0.first }
                .map(String.init)
                .joined()
                .uppercased()
        }
        return compact.joined(separator: ", ")
    }
}
private struct HourGrid: View {
    let totalHours: Int
    let hourWidth: CGFloat
    let height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<totalHours, id: \.self) { _ in
                Rectangle()
                    .fill(Color.secondary.opacity(0.08))
                    .frame(width: hourWidth, height: height)
                    .overlay(
                        Rectangle()
                            .fill(Color.secondary.opacity(0.18))
                            .frame(width: 1),
                        alignment: .trailing
                    )
            }
        }
    }
}

struct TimelineRoomRow: View {
    let room: String
    let dayStart: Date
    let dayEnd: Date
    let hourWidth: CGFloat
    let contentWidth: CGFloat
    let sessions: [Session]
    let color: Color
    let snapMinutes: Double
    var onSelect: (Session) -> Void
    var peopleNames: ([UUID]) -> String
    var projectName: (UUID?, String) -> String

    @EnvironmentObject private var store: SessionStore

    // Gesture mode per-row
    @State private var activeID: UUID? = nil       // which session is being manipulated
    @State private var mode: Mode? = nil           // .move or .resize for the active session
    @State private var dx: CGFloat = 0             // current drag delta (points)

    private enum Mode { case move, resize }

    private var snapSeconds: TimeInterval { snapMinutes * 60 }
    private let handleGrabWidth: CGFloat = 22      // width of the right-edge "grab" zone

    private func x(for date: Date) -> CGFloat {
        let clamped = min(max(date, dayStart), dayEnd)
        let secs = clamped.timeIntervalSince(dayStart)
        return CGFloat(secs / 3600.0) * hourWidth
    }
    private func width(from start: Date, to end: Date) -> CGFloat {
        max(6, x(for: end) - x(for: start))
    }
    private func onDragChanged(for s: Session,
                               startX: CGFloat,
                               baseWidth: CGFloat,
                               value: DragGesture.Value) {
        if activeID == nil {
            activeID = s.id
            let barLeft = startX - baseWidth/2
            let localXAtStart = value.startLocation.x - barLeft
            if localXAtStart >= baseWidth - handleGrabWidth {
                mode = .resize
            } else {
                mode = .move
            }
        }
        guard activeID == s.id, mode != nil else { return }
        dx = value.translation.width
    }

    private func onDragEnded(for s: Session,
                             baseWidth: CGFloat,
                             value: DragGesture.Value) {
        defer { activeID = nil; mode = nil; dx = 0 }
        guard let m = mode, activeID == s.id else { return }

        switch m {
        case .move:
            let hoursDelta = Double(value.translation.width / hourWidth)
            let secondsDelta = hoursDelta * 3600.0
            let proposed = s.start.addingTimeInterval(secondsDelta)
            let snappedStart = Date(timeIntervalSinceReferenceDate: snapped(proposed.timeIntervalSinceReferenceDate))
            let newSession = Session(
                id: s.id, title: s.title, client: s.client, room: s.room,
                start: snappedStart, durationMinutes: s.durationMinutes,
                ratePerHour: s.ratePerHour, notes: s.notes,
                projectID: s.projectID, peopleIDs: s.peopleIDs,
                roomCategoryID: s.roomCategoryID,      // keep selections
                peopleRoles: s.peopleRoles
            )
            if store.canSchedule(newSession, ignoring: s.id) { try? store.update(newSession) } else { NSSound.beep() }

        case .resize:
            let hoursDelta = Double(value.translation.width / hourWidth)
            let secondsDelta = hoursDelta * 3600.0
            let proposedEnd = s.end.addingTimeInterval(secondsDelta)
            let snappedEnd = Date(timeIntervalSinceReferenceDate: snapped(proposedEnd.timeIntervalSinceReferenceDate))
            let minEnd = s.start.addingTimeInterval(30 * 60)
            let finalEnd = max(snappedEnd, minEnd)
            let newDuration = max(30, Int(finalEnd.timeIntervalSince(s.start) / 60))
            let newSession = Session(
                id: s.id, title: s.title, client: s.client, room: s.room,
                start: s.start, durationMinutes: newDuration,
                ratePerHour: s.ratePerHour, notes: s.notes,
                projectID: s.projectID, peopleIDs: s.peopleIDs,
                roomCategoryID: s.roomCategoryID,
                peopleRoles: s.peopleRoles
            )
            if store.canSchedule(newSession, ignoring: s.id) { try? store.update(newSession) } else { NSSound.beep() }
        }
    }

    private func snapped(_ t: TimeInterval) -> TimeInterval { (t / snapSeconds).rounded() * snapSeconds }



    var body: some View {
        ZStack(alignment: .topLeading) {
            // grid
            HourGrid(totalHours: 24, hourWidth: hourWidth, height: 56)
                .frame(width: contentWidth, height: 56)


            // room label
            Text(room)
                .font(.callout).bold()
                .padding(.leading, 6)
                .padding(.top, 4)

            // session bars
            ForEach(sessions) { s in
                let startX = x(for: s.start)
                let baseWidth = width(from: s.start, to: s.end)

                // which session is currently being dragged?
                let isActive = (activeID == s.id)
                let thisMode = isActive ? mode : nil

                // live values while dragging
                let liveWidth: CGFloat = {
                    guard isActive, thisMode == .resize else { return baseWidth }
                    // resizing to the right; apply dx and clamp to ≥ 30 min
                    return max(baseWidth + dx, hourWidth * 0.5)
                }()

                RoundedRectangle(cornerRadius: 6)
                    .fill(color.opacity(isActive ? 0.6 : 0.85))
                    .overlay(
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(s.title) — \(projectName(s.projectID, s.client))")
                                .font(.system(size: 11)).lineLimit(1)
                            if !peopleNames(s.peopleIDs).isEmpty {
                                Text(peopleNames(s.peopleIDs))
                                    .font(.system(size: 10)).lineLimit(1).opacity(0.95)
                            }
                        }
                        .padding(.horizontal, 6)
                        .foregroundColor(.white),
                        alignment: .leading
                    )
                    .frame(width: liveWidth, height: 28)
                    .padding(.top, 22)
                    .position(
                        x: startX + (thisMode == .resize ? liveWidth : baseWidth)/2 + (thisMode == .move ? dx : 0),
                        y: 28
                    )
                    .onTapGesture { onSelect(s) }
                    .help("\(s.title) (\(s.client))\n\(s.start.formatted(date: .omitted, time: .shortened))–\(s.end.formatted(date: .omitted, time: .shortened))")

                    // ONE gesture that decides move vs resize on first movement
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                onDragChanged(for: s, startX: startX, baseWidth: baseWidth, value: value)
                            }
                            .onEnded { value in
                                onDragEnded(for: s, baseWidth: baseWidth, value: value)
                            }
                    )

                    // resize affordance (visual only)
                    .overlay(alignment: .trailing) {
                        Capsule()
                            .fill(Color.white.opacity(0.35))
                            .frame(width: 3, height: 24)
                            .padding(.trailing, 3)
                            .onHover { hovering in
                                #if os(macOS)
                                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                                #endif
                            }
                    }
            }
        }
        .frame(width: contentWidth, height: 56)
        .overlay(Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1), alignment: .bottom)
    }
}

// MARK: - Share / Export ICS
struct ShareBookingSheet: View {
    @Environment(\.dismiss) private var dismiss

    // Seed values (passed from the caller)
    @State var summary: String
    @State var location: String
    @State var start: Date
    @State var end: Date
    @State var descriptionText: String
    @State var attendees: [(name: String, email: String)] = []

    @State private var includeAttendees = true

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Export / Share Calendar Invite").font(.title3).bold()
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            Form {
                TextField("Title", text: $summary)
                TextField("Location", text: $location)

                HStack {
                    DatePicker("Start", selection: $start, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("End", selection: $end, displayedComponents: [.date, .hourAndMinute])
                }

                Toggle("Include attendees", isOn: $includeAttendees)

                TextField("Description / Notes", text: $descriptionText, axis: .vertical)
                    .lineLimit(4, reservesSpace: true)

                if includeAttendees && !attendees.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Will include as ATTENDEE:").font(.caption).foregroundColor(.secondary)
                        ForEach(attendees.indices, id: \.self) { i in
                            let a = attendees[i]
                            Text("• \(a.name.isEmpty ? a.email : a.name) <\(a.email)>")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
            }

            HStack {
                Button("Save .ics…") { saveICS() }
                Button("Share…") { shareICS() }
                Spacer()
            }
        }
        .padding(16)
        .frame(minWidth: 560)
    }

    private func buildICSData() -> Data {
        let atts = includeAttendees ? attendees : []
        return ICSBuilder.makeICS(
            summary: summary,
            start: start,
            end: end,
            location: location,
            description: descriptionText,
            attendees: atts
        )
    }

    private func saveICS() {
        let data = buildICSData()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ics") ?? .data]
        panel.nameFieldStringValue = safeFilename("\(summary).ics")
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func shareICS() {
        let data = buildICSData()
        guard let temp = try? ICSBuilder.writeTempICS(filename: safeFilename("\(summary).ics"), data: data) else { return }
        let picker = NSSharingServicePicker(items: [temp])
        if let window = NSApp.keyWindow, let view = window.contentView {
            picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
        }
    }

    private func safeFilename(_ s: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        return s.components(separatedBy: invalid).joined(separator: "_")
    }
}

    
        // MARK: - CSV Export (optional)
        enum CSVBuilder {
            static func makeCSV(from sessions: [Session]) -> String {
                var rows: [String] = []
                rows.append(["Start","End","Title","Client","Room","Project","People","Duration(min)","Rate(/h)","Revenue","Notes"].joined(separator: ","))
                let df = DateFormatter(); df.dateStyle = .short; df.timeStyle = .short
                for s in sessions {
                    let fields: [String] = [
                        df.string(from: s.start),
                        df.string(from: s.end),
                        s.title.replacingOccurrences(of: ",", with: " "),
                        s.client.replacingOccurrences(of: ",", with: " "),
                        s.room.replacingOccurrences(of: ",", with: " "),
                        s.projectID?.uuidString ?? "",
                        s.peopleIDs.map { $0.uuidString }.joined(separator: "|"),
                        String(s.durationMinutes),
                        s.ratePerHour != nil ? String(format: "%.2f", s.ratePerHour!) : "",
                        s.revenue != nil ? String(format: "%.2f", s.revenue!) : "",
                        s.notes.replacingOccurrences(of: ",", with: " ")
                    ]
                    rows.append(fields.joined(separator: ","))
                }
                return rows.joined(separator: "\n")
            }
        }
// MARK: - Compatibility: onChange for macOS 13.5 and 14+
extension View {
    /// Use this instead of `.onChange(of:)` to support macOS 13.5 and avoid the 14.0 deprecation warning.
    @ViewBuilder
    func onChangeCompat<V: Equatable>(_ value: V, perform action: @escaping (V) -> Void) -> some View {
        if #available(macOS 14.0, *) {
            self.onChange(of: value) { _, newValue in
                action(newValue)
            }
        } else {
            self.onChange(of: value, perform: action)
        }
    }
}
