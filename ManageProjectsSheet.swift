//
// ManageProjectsSheet.swift
// Projector
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - Projects Manager

struct ManageProjectsSheet: View {
    @EnvironmentObject private var projects: ProjectStore
    @EnvironmentObject private var roomsStore: RoomStore
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var clientsStore: ClientsStore
    @Environment(\.openWindow) private var openWindow

    @State private var searchText: String = ""
    @State private var statusFilter: ProjectStatus? = .active

    private func filtered(_ status: ProjectStatus) -> [Project] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = projects.projects
            .filter { $0.status == status }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !q.isEmpty else { return base }
        return base.filter { p in p.name.lowercased().contains(q) || p.client.lowercased().contains(q) }
    }

    private var visibleProjects: [Project] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base: [Project]
        if let f = statusFilter {
            base = projects.projects.filter { $0.status == f }
        } else {
            base = projects.projects
        }
        let sorted = base.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !q.isEmpty else { return sorted }
        return sorted.filter { p in p.name.lowercased().contains(q) || p.client.lowercased().contains(q) }
    }

    @FocusState private var searchFocused: Bool
    @State private var showNewProject = false

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ───────────────────────────────────────────────────────
            HStack {
                Text("Projects").font(.title2).bold()
                Spacer()
                Button(action: { showNewProject = true }) {
                    Label("New Project", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("n", modifiers: [.command])

                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .keyboardShortcut("w", modifiers: [.command])
            }
            .padding(12)

            Divider()

            // ── Filter bar ───────────────────────────────────────────────────
            HStack(spacing: 12) {
                Text("Show:").font(.callout).foregroundColor(.secondary)
                Picker("", selection: $statusFilter) {
                    Text("Active").tag(ProjectStatus?.some(.active))
                    Text("Completed").tag(ProjectStatus?.some(.completed))
                    Text("Cancelled").tag(ProjectStatus?.some(.inactive))
                    Text("All").tag(ProjectStatus?.none)
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            // ── Project list ──────────────────────────────────────────────────
            List {
                if statusFilter == nil {
                    // Show all, grouped by status
                    ForEach(ProjectStatus.allCases, id: \.self) { s in
                        let items = filtered(s)
                        if !items.isEmpty {
                            Section(s.label) {
                                ForEach(items) { p in ProjectRow(project: p) }
                            }
                        }
                    }
                } else {
                    ForEach(visibleProjects) { p in ProjectRow(project: p) }
                }
            }
            .searchable(text: $searchText, prompt: "Search projects (name or client)")
        }
        .sheet(isPresented: $showNewProject) {
            NewProjectSheet(clientsStore: clientsStore) { nm, clientName, clientAddress, clientEmail, clientPhone in
                projects.add(Project(name: nm, client: clientName, status: .active,
                                     notes: "", address: clientAddress,
                                     email: clientEmail, phone: clientPhone))
            }
            .environmentObject(clientsStore)
        }
    }
}

// MARK: - New Project Sheet

struct NewProjectSheet: View {
    let clientsStore: ClientsStore
    let onAdd: (String, String, String?, String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var clientsStoreEnv: ClientsStore

    @State private var name: String = ""
    @State private var selectedClientID: UUID? = nil
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("New Project").font(.title2).bold()

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Project name").foregroundColor(.secondary).font(.callout)
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .focused($nameFocused)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Client").foregroundColor(.secondary).font(.callout)
                    HStack {
                        Picker("", selection: $selectedClientID) {
                            Text("Choose…").tag(UUID?.none)
                            ForEach(clientsStore.clients.filter { $0.isActive }) { c in
                                Text(c.name).tag(UUID?.some(c.id))
                            }
                        }
                        .labelsHidden()
                        .frame(minWidth: 200)

                        Button("Manage Clients…") { openWindow(id: "clients") }
                            .buttonStyle(.bordered)
                    }
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add Project") {
                    let nm = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !nm.isEmpty else { return }
                    var clientName = ""; var clientAddress: String? = nil
                    var clientEmail = ""; var clientPhone = ""
                    if let id = selectedClientID,
                       let c = clientsStore.clients.first(where: { $0.id == id }) {
                        clientName = c.name; clientAddress = c.address
                        clientEmail = c.email; clientPhone = c.phone
                    }
                    onAdd(nm, clientName, clientAddress, clientEmail, clientPhone)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
        .onAppear { nameFocused = true }
    }
}

// MARK: - Project Dashboard

struct ProjectDashboardView: View {
    let project: Project

    @EnvironmentObject private var sessions: SessionStore
    @EnvironmentObject private var projects: ProjectStore
    @EnvironmentObject private var people: PeopleStore
    @EnvironmentObject private var rooms: RoomStore
    @EnvironmentObject private var services: ServiceStore
    @EnvironmentObject private var roomCategoryStore: RoomCategoryStore
    @EnvironmentObject private var personCategoryStore: PersonCategoryStore
    @EnvironmentObject private var clientsStore: ClientsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    @State private var useDateFilter = false
    @State private var rangeStart: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var rangeEnd: Date = Date()
    @State private var discountText: String = ""
    @State private var editing: Session? = nil
    @State private var showEditor = false
    @State private var errorText: String? = nil
    @State private var selectedTab: DashTab = .sessions
    @State private var selectedSessionID: Session.ID? = nil
    @State private var editingClient = false
    @State private var clientDraft = ""

    enum DashTab: String, CaseIterable {
        case sessions = "Sessions"
        case services = "Services"
        case breakdown = "Breakdown"
    }

    // MARK: - Category rows

    struct CategoryRowPublic: Identifiable, Hashable {
        let id: UUID; let name: String
        var hours: Double; var revenue: Double; var cost: Double
        var profit: Double { revenue - cost }
    }

    private typealias CategoryRow = CategoryRowPublic

    private func roomRates(for session: Session) -> (sell: Double, buy: Double, categoryID: UUID?) {
        guard let room = rooms.rooms.first(where: { $0.name.caseInsensitiveCompare(session.room) == .orderedSame }) else { return (0, 0, nil) }
        let idToUse = session.roomCategoryID ?? room.categoryIDs.first
        if let id = idToUse, let cat = roomCategoryStore.categories.first(where: { $0.id == id }) {
            return (cat.sellRatePerHour, cat.buyCostPerHour, id)
        }
        return (room.sellRatePerHour, room.buyCostPerHour, nil)
    }

    private func personRates(for session: Session, personID: UUID) -> (sell: Double, buy: Double, categoryID: UUID?) {
        guard let person = people.people.first(where: { $0.id == personID }) else { return (0, 0, nil) }
        let chosenCategoryID = session.peopleRoles[personID] ?? person.categoryIDs.first
        if let id = chosenCategoryID, let cat = personCategoryStore.categories.first(where: { $0.id == id }) {
            return (cat.sellRatePerHour, cat.buyCostPerHour, id)
        }
        return (0, 0, nil)
    }

    private var roomCategoryRows: [CategoryRow] {
        var map: [UUID: CategoryRow] = [:]
        for s in filteredSessions {
            let hours = s.billableHours; guard hours > 0 else { continue }
            let (sell, buy, maybeCatID) = roomRates(for: s)
            guard sell != 0 || buy != 0 else { continue }
            if let catID = maybeCatID, let cat = roomCategoryStore.categories.first(where: { $0.id == catID }) {
                var row = map[catID] ?? CategoryRow(id: catID, name: cat.name, hours: 0, revenue: 0, cost: 0)
                row.hours += hours; row.revenue += hours * sell; row.cost += hours * buy
                map[catID] = row
            }
        }
        return map.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var personCategoryRows: [CategoryRow] {
        var map: [UUID: CategoryRow] = [:]
        for s in filteredSessions {
            let hours = s.billableHours; guard hours > 0 else { continue }
            for personID in s.peopleIDs {
                let (sell, buy, maybeCatID) = personRates(for: s, personID: personID)
                guard sell != 0 || buy != 0 else { continue }
                if let catID = maybeCatID, let cat = personCategoryStore.categories.first(where: { $0.id == catID }) {
                    var row = map[catID] ?? CategoryRow(id: catID, name: cat.name, hours: 0, revenue: 0, cost: 0)
                    row.hours += hours; row.revenue += hours * sell; row.cost += hours * buy
                    map[catID] = row
                }
            }
        }
        return map.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Filtered data

    private var filteredSessions: [Session] {
        sessions.sessions
            .filter { $0.projectID == project.id }
            .filter { s in guard useDateFilter else { return true }; return s.start >= rangeStart && s.start < rangeEnd }
            .sorted { $0.start < $1.start }
    }

    private var filteredServiceBookings: [ServiceBooking] {
        ServiceStore.shared.bookings
            .filter { $0.projectId == project.id }
            .filter { $0.status == .completed }
            .filter { b in guard useDateFilter else { return true }; return b.date >= rangeStart && b.date < rangeEnd }
    }

    // MARK: - Totals

    private var totalHours: Double { Double(filteredSessions.reduce(0) { $0 + $1.billableMinutes }) / 60.0 }

    private var sessionsRevenue: Double { filteredSessions.reduce(0) { $0 + Finance.sessionRevenue($1, rooms: rooms.rooms, people: people.people) } }
    private var sessionsCost: Double    { filteredSessions.reduce(0) { $0 + Finance.sessionCost($1,    rooms: rooms.rooms, people: people.people) } }
    private var sessionsProfit: Double  { sessionsRevenue - sessionsCost }

    private var totalServiceRevenue: Double { filteredServiceBookings.reduce(0) { $0 + Finance.serviceRevenue($1, catalog: services.services) } }
    private var totalServiceCost: Double    { filteredServiceBookings.reduce(0) { $0 + Finance.serviceCost($1,    catalog: services.services) } }
    private var servicesProfit: Double  { totalServiceRevenue - totalServiceCost }
    private var totalServiceUnits: Int  { filteredServiceBookings.count }

    private var currentProject: Project { projects.projects.first(where: { $0.id == project.id }) ?? project }
    private var totalRevenue: Double { sessionsRevenue + totalServiceRevenue }
    private var totalCost: Double    { sessionsCost + totalServiceCost }
    private var totalProfit: Double  { totalRevenue - totalCost }

    private var effectiveDiscountPercent: Double {
        let raw = currentProject.discountPercent ?? 0
        return raw.isFinite ? max(0, min(100, raw)) : 0
    }
    private var discountAmount: Double { totalRevenue * (effectiveDiscountPercent / 100.0) }
    private var finalRevenue: Double   { totalRevenue - discountAmount }
    private var finalProfit: Double    { finalRevenue - totalCost }
    private var hasDiscount: Bool      { effectiveDiscountPercent > 0.0001 }

    // MARK: - Discount

    private func applyProjectDiscount() {
        let raw = discountText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        if let value = Double(raw), value.isFinite {
            let clamped = max(0, min(100, value))
            var updated = currentProject; updated.discountPercent = clamped
            projects.update(updated)
            discountText = String(format: "%.2f", clamped)
        } else {
            var updated = currentProject; updated.discountPercent = nil
            projects.update(updated); discountText = ""
        }
    }

    // MARK: - CSV Export

    private func exportInvoiceCSV() {
        var lines = ["LineType,Description,Quantity,Unit,DiscountPercent,NetAmountEUR"]
        func fmt(_ v: Double) -> String { String(format: "%.2f", v) }
        func esc(_ s: String) -> String {
            s.contains(",") || s.contains("\"") || s.contains("\n")
                ? "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" : s
        }
        func net(_ gross: Double) -> Double { hasDiscount ? gross * (1 - effectiveDiscountPercent / 100) : gross }

        if sessionsRevenue > 0 {
            lines.append(["Sessions", esc("Studio time – \(project.name)"),
                          fmt(totalHours), "h",
                          hasDiscount ? fmt(effectiveDiscountPercent) : "0",
                          fmt(net(sessionsRevenue))].joined(separator: ","))
        }
        if totalServiceRevenue > 0 {
            lines.append(["Services", esc("Services – \(project.name)"),
                          fmt(Double(totalServiceUnits)), "unit",
                          hasDiscount ? fmt(effectiveDiscountPercent) : "0",
                          fmt(net(totalServiceRevenue))].joined(separator: ","))
        }
        let csv = lines.joined(separator: "\n")
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType.commaSeparatedText]
        panel.nameFieldStringValue = "\(project.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-"))-invoice.csv"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? csv.data(using: .utf8)?.write(to: url)
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ───────────────────────────────────────────────────────
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Project").font(.caption).foregroundColor(.secondary).textCase(.uppercase)
                    }
                    Text(currentProject.name).font(.title2).bold()

                    HStack(spacing: 6) {
                        Text("Client").font(.caption).foregroundColor(.secondary).textCase(.uppercase)
                    }
                    if editingClient {
                        HStack(spacing: 6) {
                            Picker("", selection: $clientDraft) {
                                Text("— No client —").tag("")
                                ForEach(clientsStore.clients.filter { $0.isActive }) { c in
                                    Text(c.name).tag(c.name)
                                }
                            }
                            .frame(minWidth: 180)
                            Button("Apply") {
                                if let c = clientsStore.clients.first(where: { $0.name == clientDraft }) {
                                    var updated = currentProject
                                    updated.client  = c.name
                                    updated.email   = c.email
                                    updated.phone   = c.phone
                                    updated.address = c.address
                                    projects.update(updated)
                                } else if clientDraft.isEmpty {
                                    var updated = currentProject
                                    updated.client = ""
                                    projects.update(updated)
                                }
                                editingClient = false
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            Button("Cancel") { editingClient = false }
                                .controlSize(.small)
                        }
                    } else {
                        HStack(spacing: 6) {
                            Text(currentProject.client.isEmpty ? "No client" : currentProject.client)
                                .font(.title3).fontWeight(.semibold)
                                .foregroundColor(currentProject.client.isEmpty ? .secondary : .primary)
                            Button {
                                clientDraft = currentProject.client
                                editingClient = true
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Change client")
                        }
                    }

                    HStack(spacing: 16) {
                        if !currentProject.email.isEmpty {
                            Label(currentProject.email, systemImage: "envelope")
                                .font(.callout).foregroundColor(.secondary)
                        }
                        if !currentProject.phone.isEmpty {
                            Label(currentProject.phone, systemImage: "phone")
                                .font(.callout).foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 1)
                }

                Spacer()

                // Date filter
                HStack(spacing: 8) {
                    Toggle("", isOn: $useDateFilter)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    Text("Filter by date").foregroundColor(.secondary).font(.callout)
                    if useDateFilter {
                        DatePicker("From", selection: $rangeStart, displayedComponents: [.date])
                            .labelsHidden()
                        Text("→").foregroundColor(.secondary)
                        DatePicker("To", selection: $rangeEnd, displayedComponents: [.date])
                            .labelsHidden()
                    }
                }

                Divider().frame(height: 24)

                Button("Budget…") { openWindow(id: "budget", value: project.id) }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // ── Main layout: sidebar + content ───────────────────────────────
            HStack(spacing: 0) {

                // ── Sidebar ──────────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 12) {

                    // KPI cards
                    DashKPI(label: "HOURS", value: String(format: "%.1f h", totalHours), icon: "clock")
                    DashKPI(label: "REVENUE", value: "€ \(Finance.currency(totalRevenue))", icon: "arrow.up.circle", color: .green)
                    DashKPI(label: "COST",    value: "€ \(Finance.currency(totalCost))",    icon: "arrow.down.circle", color: .orange)
                    DashKPI(label: "PROFIT",  value: "€ \(Finance.currency(totalProfit))",  icon: "chart.line.uptrend.xyaxis",
                            color: totalProfit >= 0 ? .green : .red)

                    Divider()

                    // Discount
                    VStack(alignment: .leading, spacing: 6) {
                        Text("DISCOUNT")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .kerning(0.5)

                        HStack(spacing: 6) {
                            TextField("0", text: $discountText)
                                .frame(width: 52)
                                .multilineTextAlignment(.trailing)
                                .textFieldStyle(.roundedBorder)
                            Text("%").foregroundColor(.secondary)
                            Button("Apply") { applyProjectDiscount() }
                                .controlSize(.small)
                        }

                        if hasDiscount {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("– € \(Finance.currency(discountAmount))")
                                    .font(.callout).foregroundColor(.orange)
                                Text("Final: € \(Finance.currency(finalRevenue))")
                                    .font(.callout.weight(.semibold))
                                Text("Profit: € \(Finance.currency(finalProfit))")
                                    .font(.callout)
                                    .foregroundColor(finalProfit >= 0 ? .green : .red)
                            }
                            .padding(.top, 2)
                        }
                    }

                    Divider()

                    // Export
                    Button(action: exportInvoiceCSV) {
                        Label("Export CSV…", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Divider()

                    // Notes
                    VStack(alignment: .leading, spacing: 6) {
                        Text("NOTES")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .kerning(0.5)
                        TextEditor(text: Binding(
                            get: { currentProject.notes },
                            set: { newValue in
                                var p = currentProject
                                p.notes = newValue
                                projects.update(p)
                            }
                        ))
                        .font(.callout)
                        .frame(maxHeight: .infinity)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
                    }

                }
                .padding(16)
                .frame(width: 200)
                .background(Color.primary.opacity(0.03))

                Divider()

                // ── Tab content ───────────────────────────────────────────────
                VStack(spacing: 0) {
                    // Tab picker
                    HStack {
                        Picker("", selection: $selectedTab) {
                            ForEach(DashTab.allCases, id: \.self) { tab in
                                Text(tab.rawValue).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 320)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    Divider()

                    // Tab views
                    switch selectedTab {
                    case .sessions:   sessionsTab
                    case .services:   servicesTab
                    case .breakdown:  breakdownTab
                    }
                }
            }
        }
        .frame(minWidth: 820, minHeight: 540)
        .sheet(isPresented: $showEditor) {
            EditSessionSheet(
                existing: editing,
                rooms: ["All Rooms"] + rooms.rooms.map { $0.name }.sorted(),
                clients: Array(Set(sessions.sessions.map { $0.client })).sorted().withPrefix("All Clients"),
                projects: projects.projects,
                people: people.people
            ) { result in
                if case .save(let s) = result {
                    if sessions.sessions.contains(where: { $0.id == s.id }) { try? sessions.update(s) }
                    else { try? sessions.add(s) }
                }
            }
            .environmentObject(rooms)
            .environmentObject(people)
            .environmentObject(RoomCategoryStore.shared)
            .environmentObject(PersonCategoryStore.shared)
        }
        .alert("Can't update", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
        .onAppear {
            if let pct = currentProject.discountPercent, pct > 0 {
                discountText = String(format: "%.2f", pct)
            }
        }
    }

    // MARK: - Sessions Tab

    private func roomCategoryName(for session: Session) -> String {
        let idToUse = session.roomCategoryID
            ?? rooms.rooms.first(where: { $0.name.caseInsensitiveCompare(session.room) == .orderedSame })?.categoryIDs.first
        guard let id = idToUse,
              let cat = roomCategoryStore.categories.first(where: { $0.id == id }) else { return session.room }
        return cat.name
    }

    private func peopleCategoryNames(for session: Session) -> String {
        let names: [String] = session.peopleIDs.compactMap { pid in
            let chosenCatID = session.peopleRoles[pid]
                ?? people.people.first(where: { $0.id == pid })?.categoryIDs.first
            guard let id = chosenCatID,
                  let cat = personCategoryStore.categories.first(where: { $0.id == id }) else { return nil }
            return cat.name
        }
        let unique = Array(NSOrderedSet(array: names)) as? [String] ?? names
        return unique.isEmpty ? "–" : unique.joined(separator: ", ")
    }

    private var sessionsTab: some View {
        VStack(spacing: 0) {
            if filteredSessions.isEmpty {
                emptyState(icon: "calendar.badge.exclamationmark", message: "No sessions for this project")
            } else {
                Table(filteredSessions, selection: $selectedSessionID) {
                    TableColumn("Date") { s in
                        Text(s.start.formatted(date: .abbreviated, time: .omitted))
                            .contextMenu {
                                Button {
                                    NotificationCenter.default.post(
                                        name: .init("projector.jumpToSession"),
                                        object: nil,
                                        userInfo: ["date": s.start]
                                    )
                                } label: {
                                    Label("Show in Timeline", systemImage: "calendar")
                                }
                            }
                    }
                    .width(min: 90, ideal: 100)
                    TableColumn("Start") { s in
                        Text(s.start.formatted(date: .omitted, time: .shortened))
                    }
                    .width(min: 50, ideal: 60)
                    TableColumn("End") { s in
                        Text(s.end.formatted(date: .omitted, time: .shortened))
                    }
                    .width(min: 50, ideal: 60)
                    TableColumn("Title", value: \.title)
                    TableColumn("Room Cat.") { s in
                        Text(roomCategoryName(for: s))
                    }
                    .width(min: 80, ideal: 100)
                    TableColumn("People Cat.") { s in
                        Text(peopleCategoryNames(for: s))
                    }
                    .width(min: 80, ideal: 110)
                    TableColumn("h") { s in
                        Text(String(format: "%.2f", s.billableHours))
                    }
                    .width(min: 40, ideal: 48)
                    TableColumn("Revenue") { s in
                        Text("€ " + Finance.currency(Finance.sessionRevenue(s, rooms: rooms.rooms, people: people.people)))
                    }
                    .width(min: 70, ideal: 80)
                    TableColumn("Cost") { s in
                        Text("€ " + Finance.currency(Finance.sessionCost(s, rooms: rooms.rooms, people: people.people)))
                    }
                    .width(min: 70, ideal: 80)
                }
                .onTapGesture(count: 2) {
                    if let id = selectedSessionID,
                       let s = filteredSessions.first(where: { $0.id == id }) {
                        NotificationCenter.default.post(
                            name: .init("projector.jumpToSession"),
                            object: nil,
                            userInfo: ["date": s.start]
                        )
                    }
                }
                .alternatingRowBackgrounds(.disabled)

                Divider()

                // Totals footer
                HStack(spacing: 20) {
                    Spacer()
                    TotalsChip(label: "Hours",   value: String(format: "%.2f", totalHours))
                    TotalsChip(label: "Revenue", value: "€ \(Finance.currency(sessionsRevenue))")
                    TotalsChip(label: "Cost",    value: "€ \(Finance.currency(sessionsCost))")
                    TotalsChip(label: "Profit",  value: "€ \(Finance.currency(sessionsProfit))",
                               color: sessionsProfit >= 0 ? .green : .red)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.03))
            }
        }
    }

    // MARK: - Services Tab

    private var servicesTab: some View {
        VStack(spacing: 0) {
            if filteredServiceBookings.isEmpty {
                emptyState(icon: "wrench.and.screwdriver", message: "No completed services for this project")
            } else {
                Table(filteredServiceBookings) {
                    TableColumn("Date") { b in
                        Text(b.date.formatted(date: .abbreviated, time: .omitted))
                    }
                    .width(min: 90, ideal: 100)
                    TableColumn("Service") { b in
                        Text(services.services.first(where: { $0.id == b.serviceId })?.name ?? "–")
                    }
                    TableColumn("Notes") { b in
                        Text(b.notes.isEmpty ? "–" : b.notes)
                    }
                    TableColumn("Units") { _ in Text("1") }
                        .width(min: 36, ideal: 44)
                    TableColumn("Revenue") { b in
                        Text("€ " + Finance.currency(Finance.serviceRevenue(b, catalog: services.services)))
                    }
                    .width(min: 70, ideal: 80)
                    TableColumn("Cost") { b in
                        Text("€ " + Finance.currency(Finance.serviceCost(b, catalog: services.services)))
                    }
                    .width(min: 70, ideal: 80)
                }
                .alternatingRowBackgrounds(.disabled)

                Divider()

                HStack(spacing: 20) {
                    Spacer()
                    TotalsChip(label: "Units",   value: "\(totalServiceUnits)")
                    TotalsChip(label: "Revenue", value: "€ \(Finance.currency(totalServiceRevenue))")
                    TotalsChip(label: "Cost",    value: "€ \(Finance.currency(totalServiceCost))")
                    TotalsChip(label: "Profit",  value: "€ \(Finance.currency(servicesProfit))",
                               color: servicesProfit >= 0 ? .green : .red)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.03))
            }
        }
    }

    // MARK: - Breakdown Tab

    private var breakdownTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // Room categories
                BreakdownSection(title: "Room Categories", icon: "building.2") {
                    if roomCategoryRows.isEmpty {
                        Text("No room-category data in this range.")
                            .foregroundColor(.secondary).font(.callout)
                    } else {
                        BreakdownTable(rows: roomCategoryRows)
                    }
                }

                // People categories
                BreakdownSection(title: "People Categories", icon: "person.2") {
                    if personCategoryRows.isEmpty {
                        Text("No people-category data in this range.")
                            .foregroundColor(.secondary).font(.callout)
                    } else {
                        BreakdownTable(rows: personCategoryRows)
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 40)).foregroundColor(.secondary)
            Text(message).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func peopleNames(for ids: [UUID]) -> String {
        let dict = Dictionary(uniqueKeysWithValues: people.people.map { ($0.id, $0.name) })
        let list = ids.compactMap { dict[$0] }
        if list.isEmpty { return "–" }
        let joined = list.joined(separator: ", ")
        if joined.count <= 32 { return joined }
        return list.map { $0.split(separator: " ").prefix(3).compactMap { $0.first }.map(String.init).joined().uppercased() }.joined(separator: ", ")
    }
}

// MARK: - Sidebar KPI card

private struct DashKPI: View {
    let label: String
    let value: String
    let icon: String
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption).foregroundColor(.secondary)
                Text(label).font(.caption.weight(.semibold)).foregroundColor(.secondary).kerning(0.5)
            }
            Text(value).font(.title3).bold().foregroundColor(color)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Totals footer chip

private struct TotalsChip: View {
    let label: String
    let value: String
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(label).font(.subheadline).foregroundColor(.secondary)
            Text(value).font(.title3).bold().foregroundColor(color)
        }
    }
}

// MARK: - Breakdown section

private struct BreakdownSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.subheadline.weight(.semibold)).foregroundColor(.secondary)
                Text(title).font(.subheadline.weight(.semibold)).foregroundColor(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        }
    }
}

// MARK: - Breakdown table

private struct BreakdownTable: View {
    let rows: [ProjectDashboardView.CategoryRowPublic]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Category").frame(maxWidth: .infinity, alignment: .leading)
                Text("Hours").frame(width: 70, alignment: .trailing)
                Text("Revenue").frame(width: 100, alignment: .trailing)
                Text("Cost").frame(width: 100, alignment: .trailing)
                Text("Profit").frame(width: 100, alignment: .trailing)
            }
            .font(.caption).foregroundColor(.secondary)
            .padding(.bottom, 4)

            Divider()

            ForEach(rows) { row in
                HStack {
                    Text(row.name).frame(maxWidth: .infinity, alignment: .leading)
                    Text(String(format: "%.1f", row.hours)
                        .replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? "."))
                        .frame(width: 70, alignment: .trailing)
                    Text("€ \(Finance.currency(row.revenue))").frame(width: 100, alignment: .trailing)
                    Text("€ \(Finance.currency(row.cost))").frame(width: 100, alignment: .trailing)
                    Text("€ \(Finance.currency(row.profit))")
                        .frame(width: 100, alignment: .trailing)
                        .foregroundColor(row.profit >= 0 ? .green : .red)
                }
                .font(.callout)
                .padding(.vertical, 3)

                Divider().opacity(0.5)
            }
        }
    }
}

// MARK: - Supporting types

private extension Array where Element == String {
    func withPrefix(_ p: String) -> [String] { [p] + self }
}

// MARK: - Project Row

struct ProjectRow: View {
    @EnvironmentObject private var projects: ProjectStore
    @State var project: Project
    @State private var showDeleteConfirm = false
    @State private var showNotes = false
    @Environment(\.openWindow) private var openWindow

    private var statusColor: Color {
        switch project.status {
        case .active:              return .green
        case .completed:           return .blue
        case .inactive, .cancelled: return .secondary
        }
    }

    private func setStatus(_ s: ProjectStatus) {
        var p = project; p.status = s; projects.update(p); project = p
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 12) {
            Text(project.name).bold().frame(minWidth: 180, alignment: .leading)
                .onTapGesture(count: 2) {
                    openWindow(id: "projectDashboard", value: project.id)
                }

            Text(project.client).foregroundColor(.secondary).frame(minWidth: 160, alignment: .leading)

            Spacer()

            Button("Open…")    { openWindow(id: "projectDashboard", value: project.id) }
            Button("Budgets…") { openWindow(id: "budget", value: project.id) }

            Menu(project.status.label) {
                Button("Set Active")    { setStatus(.active) }
                Button("Set Completed") { setStatus(.completed) }
                Button("Set Cancelled") { setStatus(.inactive) }
            }
            .menuStyle(.borderlessButton)
            .frame(width: 90)
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(statusColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            .foregroundColor(statusColor)

            Button {
                showNotes.toggle()
            } label: {
                Image(systemName: project.notes.isEmpty ? "note.text" : "note.text.badge.plus")
                    .foregroundColor(showNotes ? .accentColor : (project.notes.isEmpty ? .secondary : .primary))
            }
            .buttonStyle(.plain)
            .help(showNotes ? "Hide notes" : (project.notes.isEmpty ? "Add notes" : "Show notes"))

            Menu("•••") {
                Button("Delete", role: .destructive) { showDeleteConfirm = true }
            }
        }
        .padding(.vertical, 4)
        .confirmationDialog("Delete Project?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { projects.delete(project) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deleting is undoable. Are you sure?")
        }

        if showNotes {
            TextEditor(text: Binding(
                get: { project.notes },
                set: { project.notes = $0; projects.update(project) }
            ))
            .font(.callout)
            .frame(height: 80)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
            .padding(.leading, 4)
            .padding(.bottom, 6)
        }

        } // end VStack
    }
}

