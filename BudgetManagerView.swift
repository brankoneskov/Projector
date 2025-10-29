import SwiftUI

// MARK: - Budget Manager (project-scoped)
struct BudgetManagerView: View {
    @EnvironmentObject private var budgets: BudgetStore
    @EnvironmentObject private var projects: ProjectStore
    @EnvironmentObject private var roomCats: RoomCategoryStore
    @EnvironmentObject private var personCats: PersonCategoryStore

    let projectID: UUID
    @State private var selectedBudgetID: UUID? = nil
    @State private var newBudgetTitle = ""

    @State private var showDeleteConfirm = false
    @State private var pendingDeleteID: UUID? = nil

    private var project: Project? {
        projects.projects.first(where: { $0.id == projectID })
    }

    private var budgetsForProject: [ProjectBudget] {
        budgets.budgets(for: projectID).sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Budgets — \(project?.name ?? "Project")")
                    .font(.title2).bold()
                Spacer()

                // Show "Create" ONLY when no budget is opened
                if selectedBudgetID == nil, let proj = project {
                    TextField("New budget title (optional)", text: $newBudgetTitle)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)

                    Button("Create") {
                        let title = newBudgetTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        let b = budgets.createBudget(project: proj, title: title.isEmpty ? nil : title)
                        selectedBudgetID = b.id
                        newBudgetTitle = ""
                    }
                    .keyboardShortcut(.return)
                }
            }
            .padding(12)

            Divider()

            if let selectedID = selectedBudgetID,
               let budget = budgets.budgets.first(where: { $0.id == selectedID }) {
                // EDITOR
                BudgetEditor(
                    budget: budget,
                    isReadOnly: budget.state == .activeLocked,
                    onDuplicateLine: { line in
                        var copy = line; copy.id = UUID()
                        var b = budget
                        b.upsert(copy)
                        budgets.upsert(b)
                    }
                )
                .environmentObject(budgets)
                .environmentObject(roomCats)
                .environmentObject(personCats)
                .toolbar {
                    ToolbarItemGroup {
                        Button("Set as Quote") { budgets.markAsQuote(budget.id) }
                            .disabled(budget.state == .quote || budget.state == .activeLocked)

                        Button("Set Active (Lock)") { budgets.markAsActive(budget.id) }
                            .disabled(budget.state == .activeLocked)

                        if budget.state == .activeLocked {
                            Button("Unlock") { budgets.unlock(budget.id) }
                        }

                        Divider()

                        Button("Close") { selectedBudgetID = nil }
                            .keyboardShortcut(.cancelAction)
                    }
                }

            } else {
                // LIST
                List {
                    ForEach(budgetsForProject) { b in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(b.title).bold()
                                    StateBadge(state: b.state)
                                }
                                Text(b.updatedAt.formatted())
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()

                            Button("Open") { selectedBudgetID = b.id }

                            Menu("•••") {
                                Button("Set as Quote") { budgets.markAsQuote(b.id) }
                                    .disabled(b.state == .quote || b.state == .activeLocked)

                                Button("Set Active (Lock)") { budgets.markAsActive(b.id) }
                                    .disabled(b.state == .activeLocked)

                                if b.state == .activeLocked {
                                    Button("Unlock") { budgets.unlock(b.id) }
                                }

                                Divider()

                                Button("Delete", role: .destructive) {
                                    pendingDeleteID = b.id
                                    showDeleteConfirm = true
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.inset)
            }
        }
        .alert("Delete Budget", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let id = pendingDeleteID,
                   let b = budgets.budgets.first(where: { $0.id == id }) {
                    budgets.delete(b)
                }
                pendingDeleteID = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteID = nil }
        } message: {
            Text("Deleting is undoable. Are you sure?")
        }
    }
}

// MARK: - State badge (uses BudgetState from models)
private struct StateBadge: View {
    let state: BudgetState
    var body: some View {
        switch state {
        case .draft:
            Text("DRAFT").font(.caption2)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.gray.opacity(0.2), in: Capsule())
        case .quote:
            Text("QUOTE").font(.caption2)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.blue.opacity(0.2), in: Capsule())
        case .activeLocked:
            Text("ACTIVE").font(.caption2)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.green.opacity(0.25), in: Capsule())
        }
    }
}

// MARK: - Editor
private struct BudgetEditor: View {
    @EnvironmentObject private var budgets: BudgetStore
    @EnvironmentObject private var roomCats: RoomCategoryStore
    @EnvironmentObject private var personCats: PersonCategoryStore

    @State var budget: ProjectBudget
    let isReadOnly: Bool
    let onDuplicateLine: (BudgetLine) -> Void

    @State private var discountText: String = ""
    @State private var contingencyText: String = ""
    // Build index groups for each section (stable order = enum order)
    private var linesBySection: [(BudgetSection, [Int])] {
        BudgetSection.allCases.map { sec in
            let idxs = budget.lines.indices.filter { budget.lines[$0].section == sec }
            return (sec, idxs)
        }
    }

    // Optional: subtotal per section (active lines only)
    private func sectionSubtotal(_ sec: BudgetSection) -> Double {
        budget.lines.filter { $0.section == sec && $0.isActive }.reduce(0) { $0 + $1.amountSell }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Controls row
            HStack(spacing: 12) {
                AddLineMenu { addRoomLine($0) } addPerson: { addPersonLine($0) } addMisc: { addMiscLine() }
                    .disabled(isReadOnly)
                Spacer()

                HStack(spacing: 10) {
                    Text("Discount %").foregroundColor(.secondary)
                    TextField("0", text: Binding(
                        get: { discountText },
                        set: {
                            discountText = $0
                            if !isReadOnly, let v = Double($0.replacingOccurrences(of: ",", with: ".")) {
                                budget.discountPercent = max(0, v); persist()
                            }
                        }
                    ))
                    .frame(width: 60).multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isReadOnly)

                    Text("Contingency %").foregroundColor(.secondary)
                    TextField("0", text: Binding(
                        get: { contingencyText },
                        set: {
                            contingencyText = $0
                            if !isReadOnly, let v = Double($0.replacingOccurrences(of: ",", with: ".")) {
                                budget.contingencyPercent = max(0, v); persist()
                            }
                        }
                    ))
                    .frame(width: 60).multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isReadOnly)
                }
            }
            .padding(12)

            // Lines
            List {
                ForEach(linesBySection, id: \.0) { (sec, idxs) in
                    if !idxs.isEmpty {
                        Section {
                            ForEach(idxs, id: \.self) { i in
                                BudgetLineRow(
                                    line: $budget.lines[i],
                                    isReadOnly: isReadOnly,
                                    onDelete: { deleteLine(budget.lines[i].id) },
                                    onDuplicate: { onDuplicateLine(budget.lines[i]) },
                                    onChangeSection: { newSec in
                                        budget.lines[i].section = newSec
                                        persist()
                                    }
                                )
                            }
                            .onMove { from, to in
                                guard !isReadOnly else { return }
                                // Reorder within the section: map local indices back to global indices
                                var local = idxs
                                local.move(fromOffsets: from, toOffset: to)
                                // Rebuild the section ordering in the master array
                                var newLines = budget.lines
                                // Extract lines of this section in current order
                                _ = idxs.map { budget.lines[$0] }
                                // Apply local move order
                                let reordered = local.map { budget.lines[$0] }
                                // Now write them back into their original positions
                                for (pos, globalIdx) in idxs.enumerated() {
                                    newLines[globalIdx] = reordered[pos]
                                }
                                budget.lines = newLines
                                persist()
                            }
                        } header: {
                            HStack {
                                Text(sec.label).font(.headline)
                                Spacer()
                                Text("€ " + String(format: "%.2f", sectionSubtotal(sec)))
                                    .font(.subheadline).foregroundColor(.secondary)
                                
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
            .environment(\.defaultMinListRowHeight, 30)

            // Totals
            TotalsBar(budget: budget)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .overlay {
            if isReadOnly {
                Text("This budget is ACTIVE and locked.")
                    .font(.callout).foregroundColor(.secondary)
                    .padding(6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .onAppear {
            discountText = budget.discountPercent == 0 ? "" : String(format: "%.2f", budget.discountPercent)
            contingencyText = budget.contingencyPercent == 0 ? "" : String(format: "%.2f", budget.contingencyPercent)
        }
    }

    // MARK: Actions
    private func persist() { budgets.upsert(budget) }

    private func addRoomLine(_ c: RoomCategory) {
        guard !isReadOnly else { return }
        budget.upsert(.from(roomCategory: c, hours: 8)); persist()
    }
    private func addPersonLine(_ c: PersonCategory) {
        guard !isReadOnly else { return }
        budget.upsert(.from(personCategory: c, hours: 8)); persist()
    }
    private func addMiscLine() {
        guard !isReadOnly else { return }
        let line = BudgetLine(kind: .misc, name: "Misc", unit: "h", quantity: 8, rateSell: 0, rateBuy: 0, isActive: true, notes: "")
        budget.upsert(line); persist()
    }
    private func deleteLine(_ id: UUID) {
        guard !isReadOnly else { return }
        budget.removeLine(id); persist()
    }
}

// MARK: - Add Line Menu
private struct AddLineMenu: View {
    @EnvironmentObject private var roomCats: RoomCategoryStore
    @EnvironmentObject private var personCats: PersonCategoryStore

    var addRoom: (RoomCategory) -> Void
    var addPerson: (PersonCategory) -> Void
    var addMisc: () -> Void

    var body: some View {
        Menu {
            Section("Room Categories") {
                ForEach(roomCats.categories.filter { $0.isActive }.sorted { $0.name < $1.name }) { c in
                    Button(c.name) { addRoom(c) }
                }
            }
            Section("Person Categories") {
                ForEach(personCats.categories.filter { $0.isActive }.sorted { $0.name < $1.name }) { c in
                    Button(c.name) { addPerson(c) }
                }
            }
            Divider()
            Button("Misc Line") { addMisc() }
        } label: {
            Label("Add Line", systemImage: "plus.circle")
        }
    }
}

// MARK: - Line Row
private struct BudgetLineRow: View {
    @Binding var line: BudgetLine
    let isReadOnly: Bool
    var onDelete: () -> Void
    var onDuplicate: () -> Void
    var onChangeSection: (BudgetSection) -> Void

    @State private var qtyText: String = ""
    @State private var sellText: String = ""
    @State private var buyText: String = ""
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName(for: line.kind))
                .foregroundColor(.secondary)
                .frame(width: 16)

            if line.kind == .misc {
                TextField("Name", text: $line.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 160)
                    .disabled(isReadOnly)
            } else {
                Text(line.name).bold().frame(minWidth: 160, alignment: .leading)
            }

            TextField("Unit", text: $line.unit)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                .disabled(isReadOnly)

            TextField("Qty", text: Binding(
                get: { qtyText },
                set: { qtyText = $0; if let v = Double($0.replacingOccurrences(of: ",", with: ".")) { line.quantity = max(0, v) } }
            ))
            .frame(width: 60)
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.roundedBorder)
            .onAppear { qtyText  = line.quantity == 0 ? "" : String(format: "%.2f", line.quantity) }
            .disabled(isReadOnly)

            TextField("Sell €/\(line.unit)", text: Binding(
                get: { sellText },
                set: { sellText = $0; if let v = Double($0.replacingOccurrences(of: ",", with: ".")) { line.rateSell = max(0, v) } }
            ))
            .frame(width: 90)
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.roundedBorder)
            .onAppear { sellText = line.rateSell == 0 ? "" : String(format: "%.2f", line.rateSell) }
            .disabled(isReadOnly)

            TextField("Buy €/\(line.unit)", text: Binding(
                get: { buyText },
                set: { buyText = $0; if let v = Double($0.replacingOccurrences(of: ",", with: ".")) { line.rateBuy = max(0, v) } }
            ))
            .frame(width: 90)
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.roundedBorder)
            .onAppear { buyText = line.rateBuy == 0 ? "" : String(format: "%.2f", line.rateBuy) }
            .disabled(isReadOnly)

            Text("€ " + String(format: "%.2f", line.amountSell))
                .frame(width: 100, alignment: .trailing)
            Text("€ " + String(format: "%.2f", line.amountCost))
                .frame(width: 100, alignment: .trailing)
                .foregroundColor(.secondary)

            Spacer()

            Toggle("Active", isOn: $line.isActive).labelsHidden()
                .disabled(isReadOnly)

            Menu("•••") {
                Button("Duplicate") { onDuplicate() }.disabled(isReadOnly)
                Menu("Move to") {
                    ForEach(BudgetSection.allCases, id: \.self) { sec in
                        Button {
                            onChangeSection(sec)
                        } label: {
                            Label(sec.label, systemImage: line.section == sec ? "checkmark" : "")
                        }
                    }
                }
                Divider()
                Button("Delete", role: .destructive) { showDeleteConfirm = true }.disabled(isReadOnly)
            }
            .alert("Delete Item", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) { onDelete() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Deleting is undoable. Are you sure?")
            }
            .background(line.isActive ? Color.white : Color.gray.opacity(0.05))
            .listRowBackground(line.isActive ? Color.white : Color.gray.opacity(0.05))
        }
        .padding(.vertical, 4)
    }

    private func iconName(for kind: BudgetLineKind) -> String {
        switch kind {
        case .roomCategory:   return "building.2"
        case .personCategory: return "person.fill"
        case .misc:           return "doc.text"
        }
    }
}

// MARK: - Totals
private struct TotalsBar: View {
    let budget: ProjectBudget
    var body: some View {
        HStack(spacing: 18) {
            Group {
                CapsuleStat(title: "Subtotal Sell", value: budget.subtotalSell)
                CapsuleStat(title: "Subtotal Cost", value: budget.subtotalCost)
                CapsuleStat(title: "Discount", value: -budget.discountValue)
                CapsuleStat(title: "Contingency", value: budget.contingencyValue)
            }
            Spacer()
            Group {
                CapsuleStat(title: "Total Sell", value: budget.totalSell, emphasize: true)
                CapsuleStat(title: "Margin", value: budget.margin)
                Text(String(format: "Margin %%: %.1f", budget.marginPercent))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

private struct CapsuleStat: View {
    let title: String
    let value: Double
    var emphasize: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text("€ " + String(format: "%.2f", value))
                .font(emphasize ? .title3.bold() : .callout.bold())
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
