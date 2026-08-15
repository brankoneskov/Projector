//
// EditSessionSheet.swift
// Projector
//

import SwiftUI
import Combine
import AppKit

struct EditSessionSheet: View {
    enum Result {
        case cancel
        case save(Session)
        case delete(Session)
    }

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
    @State private var useEndTime: Bool = false
    @State private var durationHoursText: String = ""
    @State private var isUpdatingTime = false
    @State private var breakMinutes: Int = 0
    @State private var breakHoursText: String = ""

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var roomsStore: RoomStore
    @EnvironmentObject private var peopleStore: PeopleStore
    @EnvironmentObject private var roomCategoryStore: RoomCategoryStore
    @EnvironmentObject private var personCategoryStore: PersonCategoryStore
    @Environment(\.openWindow) private var openWindow
    @State private var useDefaultRate = true
    @State private var showShareSheet: Bool = false
    @State private var selectedRoomCategoryID: UUID? = nil
    @State private var confirmed: Bool = false
    @State private var showCategoryWarning = false
    @State private var categoryWarningMessage = ""
    @State private var pendingSession: Session? = nil

    // True when editing an existing session whose end time is in the past
    private var isSessionInPast: Bool {
        guard let existing else { return false }
        return existing.end < Date()
    }
    @State private var selectedPeopleRoles: [UUID: UUID] = [:]

    // MARK: - Computed

    private var selectedProject: Project? {
        guard let id = selectedProjectID else { return nil }
        return projects.first(where: { $0.id == id })
    }

    private var defaultSellRate: Double { defaultRatePerHour() }

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

    // MARK: - Time helpers

    private func nextHalfHour(from date: Date) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let minute = (comps.minute ?? 0)
        let add = (minute == 0 ? 30 : (minute <= 30 ? (30 - minute) : (60 - minute)))
        return cal.date(byAdding: .minute, value: add, to: date) ?? date
    }

    private func minutesToHoursText(_ minutes: Int) -> String {
        let h = Double(minutes) / 60.0
        return String(format: "%.1f", h).replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ".")
    }

    private func hoursTextToMinutes(_ text: String) -> Int? {
        let raw = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let h = Double(raw), h >= 0 else { return nil }
        return max(30, Int((h * 2).rounded() * 30.0))
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
        max(end, start.addingTimeInterval(30*60))
    }

    // MARK: - Init

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

        _title = State(initialValue: existing?.title ?? "")
        _selectedProjectID = State(initialValue: existing?.projectID)
        _selectedPeople = State(initialValue: Set(existing?.peopleIDs ?? []))
        _selectedRoomCategoryID = State(initialValue: existing?.roomCategoryID)
        _selectedPeopleRoles    = State(initialValue: existing?.peopleRoles ?? [:])
        _room = State(initialValue: existing?.room ?? (rooms.dropFirst().first ?? "Room A"))

        let startDefault = existing?.start ?? nextHalfHour(from: Date())
        let minutesDefault = existing?.durationMinutes ?? 120
        let endDefault = startDefault.addingTimeInterval(TimeInterval(minutesDefault * 60))

        _start = State(initialValue: startDefault)
        _duration = State(initialValue: minutesDefault)
        _end = State(initialValue: endDefault)
        _durationHoursText = State(initialValue: minutesToHoursText(minutesDefault))
        _useEndTime = State(initialValue: false)

        let initialBreak = existing?.breakMinutes ?? 0
        _breakMinutes = State(initialValue: initialBreak)
        _breakHoursText = State(initialValue: minutesToHoursText(initialBreak))
        _confirmed = State(initialValue: existing?.confirmed ?? false)

        if let pid = existing?.projectID,
           let p = projects.first(where: { $0.id == pid }),
           (existing?.client ?? "").isEmpty {
            _client = State(initialValue: p.client)
        } else {
            _client = State(initialValue: existing?.client ?? "")
        }

        _notes = State(initialValue: existing?.notes ?? "")

        if let existingRate = existing?.ratePerHour {
            _useDefaultRate = State(initialValue: false)
            _ratePerHour = State(initialValue: String(format: "%.2f", existingRate))
        } else {
            _useDefaultRate = State(initialValue: true)
            _ratePerHour = State(initialValue: "")
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ──────────────────────────────────────────────────────
            VStack(spacing: 8) {
                Text(existing == nil ? "New Session" : "Edit Session")
                    .font(.title2).bold()

                TextField("Session title", text: $title)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 7)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    .frame(maxWidth: 420)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)
            .padding(.horizontal, 24)
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)

            Divider()

            // ── Scrollable cards ─────────────────────────────────────────────
            ScrollView {
                VStack(spacing: 14) {

                    // SCHEDULING
                    SectionCard(label: "SCHEDULING", icon: "building.2") {
                        FormRow(label: "Room") {
                            Picker("", selection: $room) {
                                ForEach(roomsStore.rooms.filter { $0.isActive }, id: \.name) { r in
                                    Text(r.name).tag(r.name)
                                }
                            }
                            .labelsHidden().frame(minWidth: 140)

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
                            .labelsHidden().frame(minWidth: 130)
                        }
                        .onChangeCompat(room) { _ in
                            selectedRoomCategoryID = roomsStore.rooms.first(where: { $0.name == room })?.categoryIDs.first
                        }

                        Divider().padding(.vertical, 2)

                        FormRow(label: "Project") {
                            Picker("", selection: $selectedProjectID) {
                                Text("None").tag(UUID?.none)
                                // Show active projects + currently selected project (even if inactive/completed)
                                ForEach(projects.filter { $0.status == .active || $0.id == selectedProjectID }) { p in
                                    Text(p.status == .active ? p.name : "\(p.name) (\(p.status.label))").tag(UUID?.some(p.id))
                                }
                            }
                            .labelsHidden().frame(minWidth: 200)

                            if let p = selectedProject {
                                Label(p.client, systemImage: "person")
                                    .foregroundColor(.secondary).font(.callout)
                            }
                        }
                    }

                    // PEOPLE
                    SectionCard(label: "PEOPLE", icon: "person.2") {
                        HStack {
                            Menu {
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
                                        selectedPeople.removeAll(); selectedPeopleRoles.removeAll()
                                    }
                                }
                            } label: {
                                Label(selectedPeople.isEmpty ? "Add People…" : "Add / Remove…",
                                      systemImage: "person.badge.plus")
                            }
                            Spacer()
                        }

                        if !selectedPeople.isEmpty {
                            VStack(spacing: 6) {
                                ForEach(Array(selectedPeople), id: \.self) { pid in
                                    if let person = people.first(where: { $0.id == pid }) {
                                        HStack(spacing: 10) {
                                            HStack(spacing: 6) {
                                                Image(systemName: "person.circle.fill")
                                                    .foregroundColor(.secondary)
                                                Text(person.name).fontWeight(.medium)
                                                if !person.role.isEmpty {
                                                    Text("· \(person.role)")
                                                        .foregroundColor(.secondary).font(.callout)
                                                }
                                                Button {
                                                    selectedPeople.remove(pid)
                                                    selectedPeopleRoles.removeValue(forKey: pid)
                                                } label: {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .foregroundColor(.secondary)
                                                }
                                                .buttonStyle(.borderless)
                                            }
                                            .padding(.horizontal, 10).padding(.vertical, 5)
                                            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))

                                            Picker("", selection: Binding(
                                                get: { selectedPeopleRoles[pid] },
                                                set: { selectedPeopleRoles[pid] = $0 }
                                            )) {
                                                Text("Role…").tag(UUID?.none)
                                                ForEach(person.categoryIDs, id: \.self) { cid in
                                                    if let cat = personCategoryStore.categories.first(where: { $0.id == cid }) {
                                                        Text(cat.name).tag(UUID?.some(cid))
                                                    }
                                                }
                                            }
                                            .labelsHidden().frame(minWidth: 160)
                                            Spacer()
                                        }
                                    }
                                }
                            }
                            .padding(.top, 4)
                        }
                    }

                    // TIME
                    SectionCard(label: "TIME", icon: "clock") {
                        FormRow(label: "Start") {
                            DatePicker("", selection: $start, displayedComponents: [.date, .hourAndMinute])
                                .labelsHidden()
                                .onChangeCompat(start) { newValue in
                                    guard !isUpdatingTime else { return }
                                    isUpdatingTime = true
                                    start = snappedHalfHour(newValue)
                                    if useEndTime {
                                        end = clampEndAfterStart(start, snappedHalfHour(end))
                                        durationHoursText = minutesToHoursText(max(30, Int(end.timeIntervalSince(start) / 60)))
                                    } else {
                                        end = start.addingTimeInterval(TimeInterval((hoursTextToMinutes(durationHoursText) ?? 120) * 60))
                                    }
                                    isUpdatingTime = false
                                }
                        }

                        Divider().padding(.vertical, 2)

                        HStack {
                            Toggle("Use end time instead of duration", isOn: $useEndTime)
                                .toggleStyle(.switch).controlSize(.small)
                            Spacer()
                        }

                        if useEndTime {
                            FormRow(label: "End") {
                                DatePicker("", selection: $end, displayedComponents: [.date, .hourAndMinute])
                                    .labelsHidden()
                                    .onChangeCompat(end) { newValue in
                                        guard useEndTime, !isUpdatingTime else { return }
                                        isUpdatingTime = true
                                        end = clampEndAfterStart(start, snappedHalfHour(newValue))
                                        durationHoursText = minutesToHoursText(max(30, Int(end.timeIntervalSince(start) / 60)))
                                        isUpdatingTime = false
                                    }
                            }
                        }

                        Divider().padding(.vertical, 2)

                        HStack(spacing: 32) {
                            HStack(spacing: 8) {
                                Text("Duration").foregroundColor(.secondary)
                                TextField("0,0", text: $durationHoursText)
                                    .frame(width: 54).multilineTextAlignment(.trailing)
                                    .textFieldStyle(.roundedBorder).disabled(useEndTime)
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

                            HStack(spacing: 8) {
                                Text("Unpaid break").foregroundColor(.secondary)
                                TextField("0,0", text: $breakHoursText)
                                    .frame(width: 54).multilineTextAlignment(.trailing)
                                    .textFieldStyle(.roundedBorder)
                                    .onChangeCompat(breakHoursText) { _ in
                                        if let mins = hoursTextToMinutes(breakHoursText) {
                                            breakMinutes = max(0, mins)
                                        }
                                    }
                                Text("h").foregroundColor(.secondary)
                            }
                            .help("Time that is NOT billed (e.g. lunch)")

                            Spacer()
                        }

                        // Confirmation toggle — highlighted in orange for past unconfirmed sessions
                        if existing != nil {
                            Divider().padding(.vertical, 2)

                            HStack {
                                Toggle(isOn: $confirmed) {
                                    Label(
                                        isSessionInPast && !confirmed
                                            ? "Confirm duration (session is complete)"
                                            : "Duration confirmed",
                                        systemImage: confirmed
                                            ? "checkmark.seal.fill"
                                            : "clock.badge.exclamationmark"
                                    )
                                    .foregroundColor(isSessionInPast && !confirmed ? .orange : .primary)
                                }
                                .toggleStyle(.switch)
                                Spacer()
                            }
                        }
                    }

                    // BILLING
                    SectionCard(label: "BILLING", icon: "eurosign.circle") {
                        HStack(spacing: 16) {
                            Toggle("Use default rate", isOn: $useDefaultRate)
                                .toggleStyle(.switch).controlSize(.small)
                                .onChangeCompat(useDefaultRate) { isOn in
                                    if isOn { ratePerHour = String(format: "%.2f", defaultRatePerHour()) }
                                }

                            Spacer()

                            if useDefaultRate {
                                Text("€ \(String(format: "%.2f", defaultRatePerHour())) / h")
                                    .font(.title3).bold()
                                    .foregroundColor(defaultRatePerHour() > 0 ? .primary : .secondary)
                            } else {
                                HStack(spacing: 4) {
                                    Text("€").foregroundColor(.secondary)
                                    TextField("0.00", text: $ratePerHour)
                                        .frame(width: 80).multilineTextAlignment(.trailing)
                                        .textFieldStyle(.roundedBorder)
                                    Text("/ h").foregroundColor(.secondary)
                                }
                            }
                        }
                        .onChangeCompat(room) { _ in
                            if useDefaultRate { ratePerHour = String(format: "%.2f", defaultRatePerHour()) }
                        }
                        .onChangeCompat(selectedPeople) { _ in
                            if useDefaultRate { ratePerHour = String(format: "%.2f", defaultRatePerHour()) }
                        }
                    }

                    // NOTES
                    SectionCard(label: "NOTES", icon: "note.text") {
                        TextField("Add notes…", text: $notes, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(4, reservesSpace: true)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 16)
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
            }
            .background(alignment: .center) {
                if let nsImage = NSImage(named: "AppIcon") {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220)
                        .opacity(0.04)
                        .allowsHitTesting(false)
                }
            }

            Divider()

            // ── Footer ────────────────────────────────────────────────────────
            HStack(spacing: 12) {
                Button("Cancel") { onClose(.cancel); dismiss() }
                    .keyboardShortcut(.cancelAction)

                if let existing = existing {
                    ConfirmingDestructiveButton(
                        title: "Delete booking",
                        message: "This action cannot be undone.",
                        confirmText: "Delete"
                    ) {
                        onClose(.delete(existing)); dismiss()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }

                Spacer()

                Button("Share .ics…") { showShareSheet = true }
                    .buttonStyle(.bordered)

                Button(existing == nil ? "Add Session" : "Save Changes") {
                    let rate: Double? = {
                        if useDefaultRate { return nil }
                        return Double(ratePerHour.replacingOccurrences(of: ",", with: "."))
                    }()
                    let finalDurationMinutes: Int = {
                        if useEndTime {
                            let mins = Int(end.timeIntervalSince(start) / 60)
                            return max(30, mins - (mins % 30))
                        }
                        return hoursTextToMinutes(durationHoursText) ?? 120
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
                        breakMinutes: breakMinutes,
                        confirmed: confirmed,
                        ratePerHour: rate,
                        notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                        projectID: selectedProjectID,
                        peopleIDs: Array(selectedPeople),
                        roomCategoryID: selectedRoomCategoryID,
                        peopleRoles: Dictionary(uniqueKeysWithValues: selectedPeople.map { pid in
                            (pid, selectedPeopleRoles[pid] ?? UUID())
                        }),
                    )

                    // ── Category validation ───────────────────────────────
                    var warnings: [String] = []
                    if selectedRoomCategoryID == nil && !room.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        warnings.append("• No room category selected for \(room.trimmingCharacters(in: .whitespacesAndNewlines))")
                    }
                    let missingCategoryPeople = selectedPeople.compactMap { pid -> String? in
                        guard selectedPeopleRoles[pid] == nil else { return nil }
                        return people.first(where: { $0.id == pid })?.name
                    }
                    for name in missingCategoryPeople {
                        warnings.append("• No category selected for \(name)")
                    }

                    if warnings.isEmpty {
                        onClose(.save(session)); dismiss()
                    } else {
                        categoryWarningMessage = warnings.joined(separator: "\n")
                        pendingSession = session
                        showCategoryWarning = true
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(
                    title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    room.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    selectedProjectID == nil
                )
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .frame(minHeight: 540)
        .alert("Missing Categories", isPresented: $showCategoryWarning) {
            Button("Save Anyway") {
                if let session = pendingSession {
                    onClose(.save(session)); dismiss()
                }
            }
            Button("Go Back", role: .cancel) {
                pendingSession = nil
            }
        } message: {
            Text("The following categories are not set:\n\n\(categoryWarningMessage)\n\nYou can save anyway, but revenue calculations may be inaccurate.")
        }
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
                location: room, start: startLocal, end: computedEnd,
                descriptionText: {
                    var desc = ""
                    if let id = selectedProjectID, let p = projects.first(where: { $0.id == id }) {
                        desc += "Project: \(p.name)\nClient: \(p.client)\n"
                    } else if !client.isEmpty { desc += "Client: \(client)\n" }
                    if !notes.isEmpty { desc += "\nNotes:\n\(notes)\n" }
                    return desc
                }(),
                attendees: attendeeList
            )
        }
    }
}

// MARK: - Layout helpers (private to this file)

private struct SectionCard<Content: View>: View {
    let label: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text(label)
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .kerning(0.5)
            }
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        }
    }
}

private struct FormRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 68, alignment: .trailing)
            content()
            Spacer(minLength: 0)
        }
    }
}
