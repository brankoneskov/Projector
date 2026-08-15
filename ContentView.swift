//
// ContentView.swift
// Projector
//

import SwiftUI
import Combine

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var store = SessionStore.shared
    @EnvironmentObject private var projects: ProjectStore
    @EnvironmentObject private var people: PeopleStore
    @EnvironmentObject private var roomsStore: RoomStore
    @EnvironmentObject private var filters: Filters

    enum ViewMode: String, CaseIterable, Identifiable {
        case list = "List"
        case timeline = "Day"
        case week = "Week"
        var id: String { rawValue }
    }

    @State private var viewMode: ViewMode = .list
    @State private var showBackupWarning = false
    @State private var backupWarningReason = ""
    @State private var showLicenceRevokedBanner = false
    @State private var licenceRevokedReason = ""
    @AppStorage("projector.timeline.lightMode") private var timelineLightMode: Bool = false
    @ObservedObject private var licence = LicenceManager.shared
    @AppStorage("timelineZoom") private var zoom: Double = 1.0
    @State private var showingProjects = false
    @State private var editing: Session? = nil
    @State private var errorText: String? = nil
    @State private var selection: Set<Session.ID> = []
    @State private var showShareSheet = false
    @State private var pendingDelete: Session? = nil
    @State private var showDeleteConfirm: Bool = false
    @State private var reopenEditorDraft: Session? = nil
    @State private var shouldReopenEditor: Bool = false
    @State private var autoReloadTimer =
        Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var rooms: [String] { ["All Rooms"] + roomsStore.rooms.map { $0.name }.sorted() }
    private var clients: [String] { ["All Clients"] + Set(store.sessions.map { $0.client }).sorted() }

    /// Past sessions that have not yet been confirmed by the manager
    private var unconfirmedPastSessions: [Session] {
        let now = Date()
        return store.sessions.filter { !$0.confirmed && $0.end < now }
    }

    func createSession(room: String, start: Date, end: Date) {
        let draft = Session(
            id: UUID(),
            title: "Session",
            client: "",
            room: room,
            start: start,
            durationMinutes: max(30, Int(end.timeIntervalSince(start) / 60)),
            ratePerHour: nil,
            notes: "",
            projectID: nil,
            peopleIDs: [],
            recurrence: .none,
            seriesID: nil,
            exceptions: [],
            roomCategoryID: nil,
            peopleRoles: [:]
        )
        editing = draft
    }

    // MARK: - Body pieces

    private var headerView: some View {
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
    }

    private var dayTitle: String {
        filters.day.formatted(.dateTime.weekday(.wide).day().month().year())
    }

    @ObservedObject private var messageStore = MessageStore.shared

    private var toolbarView: some View {
        HStack(alignment: .center) {
            Button(action: { newSession() }) { Label("New", systemImage: "plus") }

            Button(action: {
                if let id = selection.first,
                   let s = store.sessions.first(where: { $0.id == id }) { edit(s) }
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
            Button(action: { openWindow(id: "finance") }) { Label("Finance", systemImage: "eurosign.circle") }
            Button(action: { openWindow(id: "messages") }) {
                ZStack(alignment: .topTrailing) {
                    Label("Messages", systemImage: "bubble.left.and.bubble.right")
                    if messageStore.unreadCount > 0 {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                            .offset(x: 4, y: -4)
                    }
                }
            }
            Button(action: { openWindow(id: "statistics") }) { Label("Stats", systemImage: "chart.bar.xaxis") }
            Button(action: { openWindow(id: "rooms") }) { Label("Rooms", systemImage: "building.2") }
            Button(action: { openWindow(id: "peopleManager") }) { Label("People", systemImage: "person.2") }

            Spacer()

            if viewMode == .week {
                Button("◀︎") {
                    if let d = Calendar.current.date(byAdding: .day, value: -7, to: filters.day) { filters.day = d }
                }
                Button("Today") { filters.day = Date() }
                    .keyboardShortcut("t", modifiers: [])
                Button("▶︎") {
                    if let d = Calendar.current.date(byAdding: .day, value: 7, to: filters.day) { filters.day = d }
                }
            } else {
                Button("◀︎") {
                    if let d = Calendar.current.date(byAdding: .day, value: -1, to: filters.day) { filters.day = d }
                }
                Button("Today") { filters.day = Date() }
                    .keyboardShortcut("t", modifiers: [])
                Button("▶︎") {
                    if let d = Calendar.current.date(byAdding: .day, value: 1, to: filters.day) { filters.day = d }
                }
            }

            Divider().frame(height: 22)

            DatePicker("", selection: $filters.day, displayedComponents: .date)
                .labelsHidden()
                .frame(width: 140)
                .help("Select day")

            Divider().frame(height: 22)

            Picker("View", selection: $viewMode) {
                Text("List").tag(ViewMode.list).keyboardShortcut("l", modifiers: [])
                Text("Day").tag(ViewMode.timeline).keyboardShortcut("d", modifiers: [])
                Text("Week").tag(ViewMode.week).keyboardShortcut("w", modifiers: [])
            }
            .pickerStyle(.segmented)
            .frame(width: 260)

            if viewMode == .timeline || viewMode == .week {
                HStack {
                    Image(systemName: "minus.magnifyingglass")
                    Slider(value: $zoom, in: 0.6...1.4).frame(width: 160)
                    Image(systemName: "plus.magnifyingglass")
                }
                .help("Zoom timeline scale")
            }
        }
        .padding(8)
    }

    @ViewBuilder
    private var mainModeView: some View {
        switch viewMode {
        case .list:     listModeView
        case .timeline: timelineModeView
        case .week:     weekModeView
        }
    }

    @State private var showBulkConfirmAlert = false

    // MARK: - Confirmation warning banner

    private var confirmationBanner: some View {
        let count = unconfirmedPastSessions.count
        return HStack(spacing: 10) {
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundColor(.orange)
            Text(count == 1
                 ? "1 completed session needs duration confirmation."
                 : "\(count) completed sessions need duration confirmation.")
                .font(.callout)
                .foregroundColor(.primary)
            Spacer()
            Button("Confirm all before today") { showBulkConfirmAlert = true }
                .buttonStyle(.bordered)
                .controlSize(.small)
            // Quick action: open the oldest unconfirmed session
            if let oldest = unconfirmedPastSessions.sorted(by: { $0.start < $1.start }).first {
                Button("Review…") { editing = oldest }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.10))
        .overlay(Rectangle().fill(Color.orange.opacity(0.3)).frame(height: 1), alignment: .bottom)
    }

    @AppStorage("listViewCompact") private var listViewCompact: Bool = false

    @ViewBuilder
    private var listModeView: some View {
        VStack(spacing: 0) {

            // ── Day header ────────────────────────────────────────────────
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dayTitle)
                        .font(.title3).bold()
                    if !filteredSessions.isEmpty {
                        let totalH = filteredSessions.reduce(0.0) { $0 + Double($1.durationMinutes) / 60.0 }
                        Text("\(filteredSessions.count) session\(filteredSessions.count == 1 ? "" : "s")  ·  \(String(format: "%.1f", totalH)) h booked")
                            .font(.callout).foregroundColor(.secondary)
                    }
                }
                Spacer()
                // Compact/card toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { listViewCompact.toggle() }
                } label: {
                    Image(systemName: listViewCompact ? "rectangle.grid.1x2" : "tablecells")
                        .help(listViewCompact ? "Switch to card view" : "Switch to table view")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if filteredSessions.isEmpty {
                EmptyStateView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if listViewCompact {
                // ── Compact table view ────────────────────────────────────
                Table(filteredSessions, selection: $selection) {
                    TableColumn("Start") { s in
                        Text(s.start.formatted(date: .omitted, time: .shortened))
                    }.width(min: 55, ideal: 65)
                    TableColumn("End") { s in
                        Text(s.end.formatted(date: .omitted, time: .shortened))
                    }.width(min: 55, ideal: 65)
                    TableColumn("Title", value: \.title)
                    TableColumn("Project") { s in Text(projectName(for: s.projectID)).textSelection(.enabled) }
                    TableColumn("Room", value: \.room).width(min: 70, ideal: 90)
                    TableColumn("People") { s in Text(peopleNames(for: s.peopleIDs)).textSelection(.enabled) }
                    TableColumn("h") { s in
                        Text(String(format: "%.1f", Double(s.durationMinutes) / 60.0)
                            .replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? "."))
                    }.width(min: 36, ideal: 44)
                    TableColumn("Revenue") { s in
                        Text(s.revenue.map { "€ " + String(format: "%.2f", $0) } ?? "–")
                    }.width(min: 80, ideal: 90)
                }
                .onTapGesture(count: 2) {
                    if let id = selection.first,
                       let s = filteredSessions.first(where: { $0.id == id }) { edit(s) }
                }
            } else {
                // ── Card view ─────────────────────────────────────────────
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredSessions.sorted { $0.start < $1.start }) { s in
                            SessionCard(
                                session: s,
                                projectName: projectName(for: s.projectID),
                                peopleNames: peopleNames(for: s.peopleIDs),
                                isSelected: selection.contains(s.id),
                                onTap: {
                                    selection = [s.id]
                                },
                                onDoubleTap: { edit(s) }
                            )
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private var timelineModeView: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Text(dayTitle).font(.headline).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 8)

            Divider()

            TimelineDayView(
                day: filters.day,
                sessions: filteredSessionsAllDays,
                rooms: dayRooms,
                zoom: zoom,
                lightMode: timelineLightMode,
                onSelect: { s in selectSession(s) },
                condensed: false,
                onPrevDay: {
                    if let d = Calendar.current.date(byAdding: .day, value: -1, to: filters.day) {
                        withAnimation { filters.day = d }
                    }
                },
                onNextDay: {
                    if let d = Calendar.current.date(byAdding: .day, value: 1, to: filters.day) {
                        withAnimation { filters.day = d }
                    }
                },
                onCreate: { room, start, end in
                    createSession(room: room, start: start, end: end)
                }
            )
            .environmentObject(store)
            .environmentObject(people)
            .environmentObject(projects)
        }
    }

    private var weekModeView: some View {
        VStack(spacing: 0) {
            TimelineWeekView(
                weekStart: weekStart,
                sessions: weekViewSessions,
                rooms: dayRooms,
                zoom: zoom,
                lightMode: timelineLightMode,
                selectedDay: $filters.day,
                onSelect: { s, occ in
                    filters.day = (occ?.start ?? s.start)
                    selectSession(s)
                },
                onCreate: { room, start, end in
                    filters.day = start
                    createSession(room: room, start: start, end: end)
                }
            )
            .environmentObject(store)
            .environmentObject(people)
            .environmentObject(projects)

            Divider().padding(.vertical, 4)
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 6) {
            headerView
            Divider()
            VStack(spacing: 0) {
                toolbarView
                Divider()
                // Non-dismissible licence expiry warning
                if licence.showWarningBanner {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.white)
                        Text(licence.warningBannerMessage)
                            .font(.callout)
                            .foregroundColor(.white)
                        Spacer()
                        Button("Renew Licence") {
                            NotificationCenter.default.post(name: Notification.Name("projector.openLicence"), object: nil)
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.red.opacity(0.85))
                }
                // Licence revoked by server — non-dismissible, requires re-activation
                if showLicenceRevokedBanner {
                    HStack(spacing: 10) {
                        Image(systemName: "xmark.seal.fill")
                            .foregroundColor(.white)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Licence revoked")
                                .font(.callout).bold().foregroundColor(.white)
                            Text(licenceRevokedReason)
                                .font(.caption).foregroundColor(.white.opacity(0.85))
                        }
                        Spacer()
                        Button("Open Licence…") {
                            NotificationCenter.default.post(
                                name: Notification.Name("projector.openLicenceWindow"),
                                object: nil
                            )
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.red)
                }
                // Backup failure warning banner
                if showBackupWarning {
                    HStack(spacing: 10) {
                        Image(systemName: "externaldrive.badge.exclamationmark")
                            .foregroundColor(.white)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Auto-backup failed")
                                .font(.callout).bold().foregroundColor(.white)
                            Text(backupWarningReason)
                                .font(.caption).foregroundColor(.white.opacity(0.85))
                        }
                        Spacer()
                        Button("Choose New Destination") {
                            showBackupWarning = false
                            DataBackup.chooseAutoBackupFolder { _ in }
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                        Button { showBackupWarning = false } label: {
                            Image(systemName: "xmark").foregroundColor(.white.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.orange)
                }
                // Warning banner — shown when past sessions need duration confirmation
                if !unconfirmedPastSessions.isEmpty {
                    confirmationBanner
                }
                mainModeView
            }
        }
        .focusable()
        .onMoveCommand { direction in
            switch direction {
            case .left:
                if viewMode == .week {
                    if let d = Calendar.current.date(byAdding: .day, value: -7, to: filters.day) {
                        withAnimation { filters.day = d }
                    }
                } else if viewMode == .timeline {
                    if let d = Calendar.current.date(byAdding: .day, value: -1, to: filters.day) {
                        withAnimation { filters.day = d }
                    }
                }
            case .right:
                if viewMode == .week {
                    if let d = Calendar.current.date(byAdding: .day, value: 7, to: filters.day) {
                        withAnimation { filters.day = d }
                    }
                } else if viewMode == .timeline {
                    if let d = Calendar.current.date(byAdding: .day, value: 1, to: filters.day) {
                        withAnimation { filters.day = d }
                    }
                }
            default:
                break
            }
        }
        .sheet(item: $editing) { (editingSession: Session) in
            EditSessionSheet(
                existing: editingSession,
                rooms: rooms,
                clients: clients,
                projects: projects.projects,
                people: people.people,
                onClose: { result in
                    switch result {
                    case .cancel:
                        break
                    case .save(let s):
                        do {
                            if store.sessions.contains(where: { $0.id == s.id }) {
                                try SessionStore.shared.update(s)
                            } else {
                                try SessionStore.shared.add(s)
                            }
                            reopenEditorDraft = nil
                        } catch {
                            // Show the overlap error and re-open the editor so the user can fix it
                            reopenEditorDraft = s
                            errorText = error.localizedDescription
                        }
                    case .delete(let s):
                        SessionStore.shared.delete(s)
                        reopenEditorDraft = nil
                    }
                    editing = nil
                }
            )
            .environmentObject(roomsStore)
            .environmentObject(people)
            .environmentObject(RoomCategoryStore.shared)
            .environmentObject(PersonCategoryStore.shared)
            .frame(minWidth: 880, minHeight: 640)
            .overlay {
                if store.isLoading {
                    ZStack {
                        Color.black.opacity(0.25)
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Loading sessions…")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
        .alert("Can't schedule",
               isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("Continue Editing") {
                if let draft = reopenEditorDraft { editing = draft }
                reopenEditorDraft = nil
                shouldReopenEditor = false
            }
        } message: {
            Text(errorText ?? "This session cannot be saved — the room or one of the assigned technicians is already booked at this time.")
        }
        .alert("Delete this session?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let s = pendingDelete { SessionStore.shared.delete(s) }
                pendingDelete = nil
                selection.removeAll()
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            if let s = pendingDelete {
                Text("\"\(s.title)\" on \(s.start.formatted(date: .abbreviated, time: .shortened)) in \(s.room)")
            } else {
                Text("This action cannot be undone.")
            }
        }
        .onReceive(autoReloadTimer) { _ in
            autoReloadAllStoresFromDisk()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("projector.jumpToSession"))) { note in
            if let date = note.userInfo?["date"] as? Date {
                filters.day = date
                viewMode = .week
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("projector.setViewMode"))) { note in
            if let mode = note.object as? String {
                switch mode {
                case "list":     withAnimation { viewMode = .list }
                case "timeline": withAnimation { viewMode = .timeline }
                case "week":     withAnimation { viewMode = .week }
                default: break
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: DataBackup.autoBackupFailedNotification)) { note in
            backupWarningReason = note.userInfo?["error"] as? String ?? "Backup destination unavailable."
            showBackupWarning = true
        }
        .onReceive(NotificationCenter.default.publisher(for: LicenceManager.licenceRevokedNotification)) { note in
            licenceRevokedReason = note.userInfo?["reason"] as? String ?? "Your licence is no longer valid."
            showLicenceRevokedBanner = true
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("projector.openLicence"))) { _ in
            NotificationCenter.default.post(name: Notification.Name("projector.openWindow.licence"), object: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("projector.goToToday"))) { _ in
            withAnimation { filters.day = Date() }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("projector.openLicenceWindow"))) { _ in
            print("🔑 Received licence window notification — opening")
            openWindow(id: "licence")
        }
        .alert("Bulk Confirm Sessions", isPresented: $showBulkConfirmAlert) {
            Button("Confirm All", role: .destructive) {
                let yesterday = Calendar.current.startOfDay(for: Date())
                let toConfirm = unconfirmedPastSessions.filter { $0.end < yesterday }
                for var s in toConfirm {
                    s.confirmed = true
                    try? store.update(s)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let yesterday = Calendar.current.startOfDay(for: Date())
            let count = unconfirmedPastSessions.filter { $0.end < yesterday }.count
            Text("This will mark \(count) sessions as confirmed (all sessions ending before today). This cannot be undone. Continue?")
        }
    }

    // MARK: - Helpers

    func selectSession(_ s: Session) { editing = s }
    func edit(_ s: Session) { editing = s }

    func newSession() {
        let defaultRoom =
            roomsStore.rooms.first(where: { $0.isActive })?.name
            ?? store.sessions.first?.room
            ?? "Room A"

        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: filters.day)
        let startBase: Date = cal.isDateInToday(filters.day)
            ? Date()
            : (cal.date(byAdding: .hour, value: 9, to: dayStart) ?? dayStart)

        let start = nextHalfHour(from: startBase)
        let end   = start.addingTimeInterval(2 * 3600)

        let draft = Session(
            id: UUID(),
            title: "Session",
            client: "",
            room: defaultRoom,
            start: start,
            durationMinutes: max(30, Int(end.timeIntervalSince(start) / 60)),
            ratePerHour: nil,
            notes: "",
            projectID: nil,
            peopleIDs: [],
            recurrence: .none,
            seriesID: nil,
            exceptions: [],
            roomCategoryID: nil,
            peopleRoles: [:]
        )
        editing = draft
    }

    func nextHalfHour(from date: Date) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let minute = comps.minute ?? 0
        let add = (minute == 0 ? 30 : (minute <= 30 ? (30 - minute) : (60 - minute)))
        return cal.date(byAdding: .minute, value: add, to: date) ?? date
    }

    private func autoReloadAllStoresFromDisk() {
        BudgetStore.shared.reload()
        SessionStore.shared.reload()
        ProjectStore.shared.reload()
        PeopleStore.shared.reload()
        RoomStore.shared.reload()
        ClientsStore.shared.reload()
        RoomCategoryStore.shared.reload()
        PersonCategoryStore.shared.reload()
        ServiceStore.shared.reload()
    }

    // MARK: - Filters / projections

    private var dayRooms: [String] {
        roomsStore.rooms.filter { $0.isActive }.map { $0.name }.sorted()
    }

    /// Sessions within ±60 days of today for timeline rendering performance
    private var weekViewSessions: [Session] {
        let now = Date()
        let from = Calendar.current.date(byAdding: .day, value: -60, to: now)!
        let to   = Calendar.current.date(byAdding: .day, value: 60, to: now)!
        return store.sessions.filter { $0.start >= from && $0.start <= to }
    }

    private var filteredSessions: [Session] {
        store.sessions.filter { s in
            let matchesRoom    = (filters.room == "All Rooms") || s.room == filters.room
            let matchesClient  = (filters.client == "All Clients") || s.client == filters.client
            let matchesQuery   = filters.query.isEmpty ||
                s.title.localizedCaseInsensitiveContains(filters.query) ||
                s.client.localizedCaseInsensitiveContains(filters.query) ||
                s.room.localizedCaseInsensitiveContains(filters.query) ||
                s.notes.localizedCaseInsensitiveContains(filters.query)
            let sameDay        = Calendar.current.isDate(s.start, inSameDayAs: filters.day)
            let matchesProject = (filters.projectID == nil) || s.projectID == filters.projectID
            let matchesPerson: Bool = {
                guard let pid = filters.personID else { return true }
                return s.peopleIDs.contains(pid)
            }()
            return matchesRoom && matchesClient && matchesQuery && sameDay && matchesProject && matchesPerson
        }
    }

    private var filteredSessionsAllDays: [Session] {
        store.sessions.filter { s in
            let matchesRoom    = (filters.room == "All Rooms") || s.room == filters.room
            let matchesClient  = (filters.client == "All Clients") || s.client == filters.client
            let matchesQuery   = filters.query.isEmpty ||
                s.title.localizedCaseInsensitiveContains(filters.query) ||
                s.client.localizedCaseInsensitiveContains(filters.query) ||
                s.room.localizedCaseInsensitiveContains(filters.query) ||
                s.notes.localizedCaseInsensitiveContains(filters.query)
            let matchesProject = (filters.projectID == nil) || s.projectID == filters.projectID
            let matchesPerson: Bool = {
                guard let pid = filters.personID else { return true }
                return s.peopleIDs.contains(pid)
            }()
            return matchesRoom && matchesClient && matchesQuery && matchesProject && matchesPerson
        }
    }

    private var weekStart: Date {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: filters.day)
        return cal.date(from: comps) ?? filters.day
    }

    private func projectName(for id: UUID?) -> String {
        guard let id, let p = projects.projects.first(where: { $0.id == id }) else { return "–" }
        switch p.status {
        case .active:    return p.name
        case .completed: return "\(p.name) (Completed)"
        case .inactive, .cancelled:  return "\(p.name) (Cancelled)"
        }
    }

    private func peopleNames(for ids: [UUID]) -> String {
        let map = Dictionary(uniqueKeysWithValues: people.people.map { ($0.id, $0.name) })
        let names = ids.compactMap { map[$0] }
        if names.isEmpty { return "–" }
        let joined = names.joined(separator: ", ")
        if joined.count <= 28 { return joined }
        let compact = names.map { name in
            name.split(separator: " ").prefix(3).compactMap { $0.first }.map(String.init).joined().uppercased()
        }
        return compact.joined(separator: ", ")
    }
}

// MARK: - Session Card

private struct SessionCard: View {
    let session: Session
    let projectName: String
    let peopleNames: String
    let isSelected: Bool
    let onTap: () -> Void
    let onDoubleTap: () -> Void

    private var roomColor: Color {
        let hex = session.room.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return Color(hue: Double(hex % 360) / 360.0, saturation: 0.55, brightness: 0.80)
    }

    private var duration: String {
        let h = Double(session.durationMinutes) / 60.0
        return String(format: "%.1f h", h).replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ".")
    }

    private var timeRange: String {
        "\(session.start.formatted(date: .omitted, time: .shortened)) – \(session.end.formatted(date: .omitted, time: .shortened))"
    }

    var body: some View {
        HStack(spacing: 0) {

            // Colour bar
            Rectangle()
                .fill(roomColor)
                .frame(width: 5)
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: 10, bottomLeadingRadius: 10,
                    bottomTrailingRadius: 0, topTrailingRadius: 0
                ))

            VStack(alignment: .leading, spacing: 0) {

                // Top row: time + room
                HStack(alignment: .center, spacing: 8) {
                    Text(timeRange).textSelection(.enabled)
                        .font(.system(.callout, design: .monospaced).weight(.semibold))
                        .foregroundColor(.primary)

                    Spacer()

                    Text(session.room).textSelection(.enabled)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(roomColor)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(roomColor.opacity(0.12), in: Capsule())
                }
                .padding(.horizontal, 14).padding(.top, 12)

                // Middle: title + project
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.title3).bold()
                        .lineLimit(1)
                    if projectName != "–" {
                        Text(projectName)
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 14).padding(.top, 6)

                // Bottom row: people + duration + revenue
                HStack(spacing: 12) {
                    if peopleNames != "–" {
                        Label(peopleNames, systemImage: "person.2")
                            .font(.caption).foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(duration)
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)

                    if let rev = session.revenue, rev > 0 {
                        Text("€ \(String(format: "%.2f", rev))")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.primary)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? roomColor.opacity(0.08) : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? roomColor.opacity(0.5) : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onDoubleTap() }
        .onTapGesture(count: 1) { onTap() }
    }
}
