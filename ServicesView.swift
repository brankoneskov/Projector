//
//  ServicesView.swift
//  Projector
//
//  Created by Branko Neskov on 02/11/2025.
//

import SwiftUI
import UniformTypeIdentifiers // Added to support UTType.text used in onDrop
// Currency formatters that work for both Double and Decimal
private func formatEUR(_ value: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "EUR"
    f.maximumFractionDigits = 2
    return f.string(from: NSNumber(value: value)) ?? "€\(value)"
}

private func formatEUR(_ value: Decimal) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "EUR"
    f.maximumFractionDigits = 2
    return f.string(from: value as NSDecimalNumber) ?? "€\(NSDecimalNumber(decimal: value).doubleValue)"
}
private struct EditorSectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .fontWeight(.semibold)
            .foregroundStyle(.primary)
            .padding(.bottom, 2)
    }
}
// MARK: - 1) Models

struct ServiceCatalogItem: Identifiable, Hashable {
    let id: UUID
    var name: String
    var category: String // e.g., "Delivery", "Audio", "Color"
    var unitPrice: Decimal
    var taxable: Bool
    var variableUnitName: String?
}
// MARK: - Services View (container)
struct ServicesView: View {
    @EnvironmentObject var services: ServiceStore

    @State private var search = ""
    @State private var selectedID: UUID? = nil
    @State private var selectedCategory: String = "All"
    @State private var servicePendingDeletion: Service? = nil

    // Simple, compiler-friendly categories computation
    private var categories: [String] {
        let raw = services.services.compactMap { svc -> String? in
            let t = svc.category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return t.isEmpty ? nil : t
        }
        let uniq = Array(Set(raw)).sorted()
        return ["All", "(Uncategorized)"] + uniq
    }

    // Filtered rows with clear steps
    private var filtered: [Service] {
        // Filter by category
        let base = services.services.filter { svc in
            switch selectedCategory {
            case "All":
                return true
            case "(Uncategorized)":
                return (svc.category?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            default:
                return svc.category?.caseInsensitiveCompare(selectedCategory) == .orderedSame
            }
        }
        // Search (if any)
        guard !search.isEmpty else { return base.sorted { $0.name < $1.name } }
        let needle = search.lowercased()
        return base.filter {
            $0.name.lowercased().contains(needle)
            || ($0.category ?? "").lowercased().contains(needle)
            || $0.notes.lowercased().contains(needle)
        }
        .sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationSplitView {
            ServicesSidebar(
                search: $search,
                selectedID: $selectedID,
                selectedCategory: $selectedCategory,
                categories: categories,
                rows: filtered
            )
        } detail: {
            ServicesDetail(selectedID: $selectedID)
        }
        .navigationTitle("Services")
        .persistWindowFrame("servicesWindow")
    }
}

// MARK: - Sidebar (list + toolbar)
private struct ServicesSidebar: View {
    @EnvironmentObject var services: ServiceStore
    @Binding var search: String
    @Binding var selectedID: UUID?
    @Binding var selectedCategory: String

    let categories: [String]
    let rows: [Service]
    // MARK: - Delete confirmation
    @State private var showDeleteConfirm = false
    @State private var pendingDeleteIDs: Set<UUID> = []
    @State private var pendingDeleteLabel: String = ""

    private func requestDelete(ids: Set<UUID>, label: String) {
        pendingDeleteIDs = ids
        pendingDeleteLabel = label
        showDeleteConfirm = true
    }

    var body: some View {
        VStack(spacing: 8) {
            Picker("Category", selection: $selectedCategory) {
                ForEach(categories, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            Text("Sidebar services count: \(rows.count)")
                .foregroundStyle(.secondary)
            List(selection: $selectedID) {
                ForEach(rows) { svc in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(svc.name).font(.headline)
                        HStack(spacing: 8) {
                            Text((svc.category?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                                 ? "(Uncategorized)"
                                 : (svc.category ?? ""))
                                .foregroundStyle(.secondary)
                            Text("\(svc.unitName) @ \(formatEUR(svc.unitPriceEUR)) / cost \(formatEUR(svc.unitCostEUR))")
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                    .tag(svc.id)
                    .contextMenu {
                        Button("Duplicate") {
                            var dup = svc
                            dup.id = UUID()
                            dup.name += " (copy)"
                            services.upsert(dup)
                        }
                        Button("Delete", role: .destructive) {
                            requestDelete(ids: Set([svc.id]), label: svc.name)
                        }

                    }
                }
                .onDelete { indexSet in
                    let ids = Set(indexSet.map { rows[$0].id })
                    requestDelete(ids: ids, label: "\(ids.count) service(s)")
                }

            }
        }
        .padding([.horizontal, .top])
        .searchable(text: $search)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    // Always create new services as Uncategorized, and ensure it’s visible
                    search = ""
                    selectedCategory = "(Uncategorized)"

                    let s = Service(name: "New Service", category: nil, unitName: "unit", variableUnitName: nil, unitPriceEUR: 0, notes: "")
                    services.upsert(s)
                    selectedID = s.id
                } label: {
                    Label("Add", systemImage: "plus")
                }


                Button {
                    guard let id = selectedID,
                          let svc = services.services.first(where: { $0.id == id }) else { return }
                    requestDelete(ids: Set([id]), label: svc.name)
                } label: {
                    Label("Delete", systemImage: "trash")
                }

                .disabled(selectedID == nil)
            }
            
        }
        .confirmationDialog(
            "Delete service?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                let ids = pendingDeleteIDs
                services.delete(ids)

                if let sid = selectedID, ids.contains(sid) {
                    selectedID = nil
                }

                pendingDeleteIDs = []
                pendingDeleteLabel = ""
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteIDs = []
                pendingDeleteLabel = ""
            }
        } message: {
            Text("This will permanently delete \(pendingDeleteLabel). This can’t be undone.")
        }

    }
    
}

// MARK: - Detail (editor placeholder)
private struct ServicesDetail: View {
    @EnvironmentObject var services: ServiceStore
    @Binding var selectedID: UUID?

    var body: some View {
        if let id = selectedID, let svc = services.services.first(where: { $0.id == id }) {
            ServiceEditor(
                service: svc,
                onDone: { selectedID = nil }   // 👈 closes editor (back to main)
            )
            .id(svc.id)
        } else {
            ZStack {
                Color(NSColor.controlBackgroundColor).opacity(0.35)
                ContentUnavailableView("Select a service", systemImage: "wrench.and.screwdriver")
            }
        }

    }
}

// MARK: - Editor
private struct ServiceEditor: View {
    @EnvironmentObject var services: ServiceStore
    @State var service: Service
    var onDone: () -> Void = {}

    private var suggestedCategories: [String] {
        let raw = services.services.compactMap { $0.category?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(raw)).sorted()
    }

    private var currentCategoryLabel: String {
        let t = service.category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? "(Uncategorized)" : t
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {

                VStack(alignment: .leading, spacing: 10) {
                    EditorSectionTitle(text: "Basics")

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name")
                            .foregroundStyle(.secondary)
                        TextField("Name", text: $service.name)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Category")
                            .foregroundStyle(.secondary)

                        Picker(
                            "",
                            selection: Binding(
                                get: { currentCategoryLabel },
                                set: { newValue in
                                    service.category = (newValue == "(Uncategorized)") ? nil : newValue
                                }
                            )
                        ) {
                            Text("(Uncategorized)").tag("(Uncategorized)")
                            ForEach(suggestedCategories, id: \.self) { cat in
                                Text(cat).tag(cat)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Or type a new category")
                            .foregroundStyle(.secondary)
                        TextField(
                            "New category",
                            text: Binding(
                                get: { service.category ?? "" },
                                set: { service.category = $0.isEmpty ? nil : $0 }
                            )
                        )
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    EditorSectionTitle(text: "Quote & Translation")

                    Text("Names may be entered in any language. Link them to your user-configured Translation dictionary for multilingual quotes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TranslationLinkPicker(
                        title: "Service name translation",
                        sourceText: service.name,
                        selection: $service.translationEntryID
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Default quote section")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("", selection: Binding(
                            get: { service.defaultBudgetSection ?? .others },
                            set: { service.defaultBudgetSection = $0 }
                        )) {
                            ForEach(BudgetSection.allCases, id: \.self) { section in
                                Text(section.label).tag(section)
                            }
                        }
                        .labelsHidden()
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    EditorSectionTitle(text: "Pricing")

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Unit name")
                            .foregroundStyle(.secondary)
                        TextField("e.g. pass, encode, file, master", text: $service.unitName)
                        TranslationLinkPicker(
                            title: "Unit translation",
                            sourceText: service.unitName,
                            selection: $service.unitTranslationEntryID
                        )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Variable unit (optional)")
                            .foregroundStyle(.secondary)
                        TextField(
                            "e.g. minute, TB, GB",
                            text: Binding(
                                get: { service.variableUnitName ?? "" },
                                set: {
                                    let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                                    service.variableUnitName = trimmed.isEmpty ? nil : trimmed
                                    if trimmed.isEmpty {
                                        service.variableUnitTranslationEntryID = nil
                                    }
                                }
                            )
                        )

                        if service.variableUnitName != nil {
                            TranslationLinkPicker(
                                title: "Variable unit translation",
                                sourceText: service.variableUnitName ?? "",
                                selection: $service.variableUnitTranslationEntryID
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Sell price (€)")
                                .foregroundStyle(.secondary)
                            TextField("0", value: $service.unitPriceEUR, format: .number)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Buy price (€)")
                                .foregroundStyle(.secondary)
                            TextField("0", value: $service.unitCostEUR, format: .number)
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    EditorSectionTitle(text: "Notes")

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes")
                            .foregroundStyle(.secondary)

                        TextField("Notes on this service", text: $service.notes, axis: .vertical)
                            .lineLimit(5, reservesSpace: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: 560, alignment: .leading)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.7))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(20)
        }
        .navigationTitle(service.name.isEmpty ? "New Service" : service.name)
        .toolbar {
            Button("Save") {
                service.name = service.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !service.name.isEmpty else { return }
                services.upsert(service)
                onDone()
            }
            .keyboardShortcut(.defaultAction)
        }
        .onDisappear {
            guard services.services.contains(where: { $0.id == service.id }) else { return }
            services.upsert(service)
        }
    }
}
struct ServicesLaneView: View {
    // Inputs
    let visibleDates: [Date] // day/week dates in order
    let catalog: [UUID: ServiceCatalogItem]
    let projects: [UUID: ProjectSummary]
    let dayColumnWidth: CGFloat
    
    // Bindings / callbacks
    @ObservedObject var store: ServiceStore
    var onRequestQuickCreate: (Date) -> Void
    
    // UI state
    @State private var expandedKeys: Set<CollapsedKey> = []
    @State private var selection: Set<UUID> = []
    
    // Collapsed grouping key: (serviceId, projectId, date)
    struct CollapsedKey: Hashable {
        var serviceId: UUID
        var projectId: UUID?
        var date: Date
    }
    
    private func nameForService(_ id: UUID) -> String {
        catalog[id]?.name ?? "Service"
    }
    private func nameForProject(_ id: UUID?) -> String {
        guard let id = id, let p = projects[id] else { return "Unassigned" }
        return p.name
    }
    
    private func grouped(for date: Date) -> [(CollapsedKey, [ServiceBooking])] {
        let day = date.stripTimeToNoon()
        let items = store.bookings.filter { $0.date.isSameDay(as: day) }
        let dict = Dictionary(grouping: items, by: { CollapsedKey(serviceId: $0.serviceId, projectId: $0.projectId, date: day) })
        return dict.map { ($0.key, $0.value) }.sorted { a, b in
            // Sort by service name then project name
            let an = nameForService(a.0.serviceId) + "\u{0000}" + nameForProject(a.0.projectId)
            let bn = nameForService(b.0.serviceId) + "\u{0000}" + nameForProject(b.0.projectId)
            return an.localizedCaseInsensitiveCompare(bn) == .orderedAscending
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Services")
                .font(DesignSystem.Fonts.sectionHeader)
                .foregroundColor(DesignSystem.Colors.accentText)
                .padding(.leading, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(visibleDates, id: \.self) { date in
                        VStack(alignment: .leading, spacing: 6) {
                            dateHeader(date)
                            dateDropArea(date)
                            let groups = grouped(for: date)
                            ForEach(groups, id: \.0) { key, bookings in
                                if bookings.count > 1 && !expandedKeys.contains(key) {
                                    collapsedChip(key: key, count: bookings.count)
                                } else {
                                    ForEach(bookings) { b in
                                        bookingChip(b)
                                    }
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(width: dayColumnWidth)
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .padding(.vertical, 6)
        .background(DesignSystem.Colors.servicesBackground)
    }

    
    // MARK: UI pieces
    private func dateHeader(_ date: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(date, style: .date)
                .font(DesignSystem.Fonts.sessionTitle)
                .bold()
            Text(date.formatted(date: .abbreviated, time: .omitted))
                .font(DesignSystem.Fonts.meta)
                .foregroundColor(DesignSystem.Colors.quietText)
        }
    }
    private func dateDropArea(_ date: Date) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.secondary.opacity(0.06))
            .frame(height: 30)
            .overlay(
                Button(action: { onRequestQuickCreate(date) }) {
                    Label("Add service", systemImage: "plus")
                        .labelStyle(.iconOnly)
                        .padding(6)
                }
                .buttonStyle(.borderless)
            )
    }
    
    private func chipBackground(for serviceId: UUID) -> Color {
        // Simple category color stub; replace with your theme or category mapping
        if let cat = catalog[serviceId]?.category.lowercased() {
            switch cat {
            case "delivery": return .blue.opacity(0.18)
            case "audio": return .green.opacity(0.18)
            case "color": return .orange.opacity(0.18)
            default: return .gray.opacity(0.16)
            }
        }
        return .gray.opacity(0.16)
    }
    
    private func statusBorder(_ status: ServiceStatus) -> some View {
        switch status {
        case .scheduled: return AnyView(RoundedRectangle(cornerRadius: 10).stroke(style: StrokeStyle(lineWidth: 1, dash: [4])).foregroundStyle(Color.secondary.opacity(0.6)))
        case .completed: return AnyView(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary, lineWidth: 1))
        case .canceled: return AnyView(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.8), lineWidth: 1))
        }
    }
    
    private func collapsedChip(key: CollapsedKey, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(nameForService(key.serviceId)).bold()
            Text("•")
            Text(nameForProject(key.projectId))
            Spacer()
            Text("×\(count)").bold()
        }
        .font(DesignSystem.Fonts.sessionSubtitle)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(DesignSystem.Colors.chipBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Layout.chipCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.chipCornerRadius)
                .stroke(Color.secondary.opacity(0.25))
        )
    }

    private func bookingChip(_ b: ServiceBooking) -> some View {
        HStack(spacing: 6) {
            statusIcon(b.status)
            Text(nameForService(b.serviceId)).bold()
            Text("•")
            Text(nameForProject(b.projectId)).lineLimit(1)
            Spacer(minLength: 4)
        }
        .font(DesignSystem.Fonts.sessionSubtitle)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(chipBackground(for: b.serviceId).opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Layout.chipCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.chipCornerRadius)
                .stroke(Color.secondary.opacity(0.25))
        )
        .contextMenu {
            contextMenuForBooking(b)
        }


        .onDrag {
            NSItemProvider(object: b.id.uuidString as NSString)
        }
        .onDrop(of: [.text], isTargeted: nil) { providers in
            // Allow moving via dropping onto another chip date area if needed later
            return false
        }
    }
    
    private func statusIcon(_ status: ServiceStatus) -> some View {
        switch status {
        case .scheduled: return AnyView(Image(systemName: "circle.dotted"))
        case .completed: return AnyView(Image(systemName: "checkmark.circle"))
        case .canceled: return AnyView(Image(systemName: "xmark.circle"))
        }
    }
    
    // MARK: Context Menus
    private func contextMenuForBooking(_ b: ServiceBooking) -> some View {
        Group {
            Button("Mark Completed", systemImage: "checkmark.circle") { store.setStatus(b.id, .completed) }
                .disabled(b.projectId == nil)
            Button("Mark Scheduled", systemImage: "circle") { store.setStatus(b.id, .scheduled) }
            Button("Cancel", systemImage: "xmark.circle") { store.setStatus(b.id, .canceled) }
            Divider()
            Menu("Assign Project") {
                ForEach(projects.values.sorted(by: { $0.name < $1.name })) { p in
                    Button(p.name) { store.assignProject(b.id, projectId: p.id) }
                }
                Button("Clear Project") { store.assignProject(b.id, projectId: nil) }
            }
            Menu("Change Service") {
                ForEach(catalog.values.sorted(by: { $0.name < $1.name })) { s in
                    Button(s.name) { store.changeService(b.id, to: s.id) }
                }
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { store.deleteBookings(Set([b.id])) }
        }
    }
    
    private func contextMenuForCollapsed(key: CollapsedKey) -> some View {
        let ids: Set<UUID> = Set(store.bookings.filter { $0.date.isSameDay(as: key.date) && $0.serviceId == key.serviceId && $0.projectId == key.projectId }.map { $0.id })
        return Group {
            Button("Expand") { expandedKeys.insert(key) }
            Button("Mark Completed (all)", systemImage: "checkmark.circle") {
                for id in ids { if store.bookings.first(where: { $0.id == id })?.projectId != nil { store.setStatus(id, .completed) } }
            }
            Button("Mark Scheduled (all)", systemImage: "circle") { for id in ids { store.setStatus(id, .scheduled) } }
            Button("Cancel (all)", systemImage: "xmark.circle") { for id in ids { store.setStatus(id, .canceled) } }
            Divider()
            Button("Delete (all)", systemImage: "trash", role: .destructive) { store.deleteBookings(ids) }
        }
    }
}

// MARK: - 5) Quick Create Sheet (date + service + project + quantity)

struct ServiceQuickCreateSheet: View {
    @ObservedObject var store: ServiceStore
    @Environment(\.dismiss) private var dismiss

    private var services: [Service] {
        store.services
    }

    let initialDate: Date
    let projects: [UUID: ProjectSummary]
    let onCreate: (_ date: Date, _ serviceId: UUID, _ projectId: UUID?, _ quantity: Int, _ variableQuantity: Decimal?, _ note: String) -> Void
    @State private var date: Date
    @State private var selectedServiceId: UUID?
    @State private var selectedProjectId: UUID?
    @State private var quantity: Int = 1
    @State private var variableQuantity: Decimal = 0
    @State private var note: String = ""
    
    init(store: ServiceStore, initialDate: Date, projects: [UUID: ProjectSummary], onCreate: @escaping (_ date: Date, _ serviceId: UUID, _ projectId: UUID?, _ quantity: Int, _ variableQuantity: Decimal?, _ note: String) -> Void) {        self.store = store
        self.initialDate = initialDate.stripTimeToNoon()
        self.projects = projects
        self.onCreate = onCreate
        _date = State(initialValue: initialDate.stripTimeToNoon())
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Service Unit").font(.title3).bold()
            DatePicker("Date", selection: $date, displayedComponents: .date)
            Picker("Service", selection: $selectedServiceId) {
                Text("Select service").tag(nil as UUID?)
                ForEach(services.sorted(by: { $0.name < $1.name })) { svc in
                    Text(svc.name).tag(svc.id as UUID?)
                }
            }
            Picker("Project", selection: $selectedProjectId) {
                Text("Unassigned").tag(nil as UUID?)
                ForEach(projects.values.sorted(by: { $0.name < $1.name })) { p in
                    Text(p.name).tag(p.id as UUID?)
                }
            }
            Stepper(value: $quantity, in: 1...999) { Text("Quantity: \(quantity)") }

            if let sid = selectedServiceId,
               let svc = store.services.first(where: { $0.id == sid }),
               let unit = svc.variableUnitName,
               !unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                TextField("Quantity", value: $variableQuantity, format: .number)
                    .frame(maxWidth: 120)
            }
            TextField("Notes (optional)", text: $note)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") {
                    guard let sid = selectedServiceId else { return }

                    let enteredVariableQuantity: Decimal?
                    if let svc = store.services.first(where: { $0.id == sid }),
                       let unit = svc.variableUnitName,
                       !unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        enteredVariableQuantity = max(Decimal(1), variableQuantity)
                    } else {
                        enteredVariableQuantity = nil
                    }

                    onCreate(date, sid, selectedProjectId, quantity, enteredVariableQuantity, note)
                    dismiss()                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedServiceId == nil)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
// Temporary simple project type for the picker, if you don’t already have one:
struct ProjectSummary: Identifiable, Hashable {
    let id: UUID
    var name: String
}

struct ServicesLaneHost: View {
    // Shared store so we see the same service bookings everywhere
    @EnvironmentObject private var store: ServiceStore
    @EnvironmentObject private var projectStore: ProjectStore

    /// Start day of the lane (e.g. selected day or week start)
    let startDate: Date
    /// How many days to show (1 for Day view, 7 for Week view, etc.)
    let spanDays: Int
    let zoom: Double
    /// Dates to display in the lane, based on startDate + spanDays
    private var visibleDates: [Date] {
        let cal = Calendar.current
        let start = startDate.stripTimeToNoon()
        return (0..<spanDays).compactMap { offset in
            cal.date(byAdding: .day, value: offset, to: start)
        }
    }
    private var dayColumnWidth: CGFloat {
            max(120, 270 * CGFloat(zoom))
        }
    // Convert your [Project] into the lane’s dictionary format.
    private var projectsById: [UUID: ProjectSummary] {
        let items = projectStore.projects
            .sorted { (a, b) in
                // active first, then by name
                if a.isActive != b.isActive { return a.isActive && !b.isActive }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        return Dictionary(uniqueKeysWithValues: items.map { p in
            (p.id, ProjectSummary(id: p.id, name: p.name))
        })
    }

    private var servicesById: [UUID: ServiceCatalogItem] {
        Dictionary(uniqueKeysWithValues: store.services.map { s in
            (s.id,
             ServiceCatalogItem(
                 id: s.id,
                 name: s.name,
                 category: s.category ?? "Uncategorized",
                 unitPrice: s.unitPriceEUR,
                 taxable: true,
                 variableUnitName: s.variableUnitName
             ))
        })
    }

    // 👇 everything below (your body: some View, etc.) stays exactly as it is now
    @State private var showCreate = false
    @State private var createDate = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ServicesLaneView(
                visibleDates: visibleDates,
                catalog: servicesById,
                projects: projectsById,
                dayColumnWidth: dayColumnWidth,
                store: store,
                onRequestQuickCreate: { date in
                    createDate = date
                    showCreate = true
                }
            )
        }
        .sheet(isPresented: $showCreate) {
            ServiceQuickCreateSheet(
                store: store,
                initialDate: createDate,
                projects: projectsById
            ) { date, serviceId, projectId, quantity, variableQuantity, note in
                store.createBookings(
                    serviceId: serviceId,
                    projectId: projectId,
                    date: date,
                    quantity: quantity,
                    variableQuantity: variableQuantity,
                    note: note
                )
            }
        }
        .padding()
    }
}

