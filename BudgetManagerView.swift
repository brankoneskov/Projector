import SwiftUI
import AppKit

// MARK: - Budget Manager (project-scoped)
struct BudgetManagerView: View {
    @EnvironmentObject private var budgets: BudgetStore
    @EnvironmentObject private var projects: ProjectStore
    @EnvironmentObject private var roomCats: RoomCategoryStore
    @EnvironmentObject private var personCats: PersonCategoryStore
    
    @ObservedObject private var templateStore = QuoteTemplateStore.shared
    @AppStorage("ProjectorUserInitials") private var userInitials: String = ""
    let projectID: UUID
    @State private var selectedBudgetID: UUID? = nil
    @State private var newBudgetTitle = ""
    @State private var showDeleteConfirm = false
    @State private var pendingDeleteID: UUID? = nil
    @State private var showTemplatePicker = false
    @State private var newBudgetAttentionTo = ""
    @State private var showFinalizeQuoteSheet = false
    @State private var finalizeBudgetID: UUID? = nil
    @State private var finalizePreviewNumber: String = ""
    @State private var finalizeErrorMessage: String? = nil
    @State private var finalizeInitialsDraft: String = ""
    @State private var heldEditLockBudgetID: UUID? = nil
    @State private var forceReadOnlyBecauseLocked: Bool = false

    @State private var pendingOpenBudgetID: UUID? = nil
    @State private var pendingLockInfo: BudgetEditLockInfo? = nil
    @State private var showLockWarning: Bool = false
    @State private var showNewBudgetSheet: Bool = false

    private var project: Project? {
        projects.projects.first(where: { $0.id == projectID })
    }
    
    private var budgetsForProject: [ProjectBudget] {
        budgets.budgets(for: projectID).sorted { $0.updatedAt > $1.updatedAt }
    }
    private var showFinalizeErrorAlert: Binding<Bool> {
        Binding<Bool>(
            get: { finalizeErrorMessage != nil },
            set: { newValue in
                if newValue == false { finalizeErrorMessage = nil }
            }
        )
    }
    private var currentDeviceName: String {
        Host.current().localizedName ?? "Unknown Mac"
    }

    private func openBudgetForEditing(_ budget: ProjectBudget) {
        // Release lock on whatever budget is currently open
        if let held = heldEditLockBudgetID, held != budget.id {
            BudgetEditLock.release(for: held)
            heldEditLockBudgetID = nil
        }

        // If a lock exists on the target budget, check who owns it
        if let info = BudgetEditLock.readLockInfo(for: budget.id) {
            if info.deviceName == currentDeviceName {
                // Same device — stale lock from a previous session, clear it silently
                BudgetEditLock.release(for: budget.id)
            } else {
                // Different device — warn the user
                pendingOpenBudgetID = budget.id
                pendingLockInfo = info
                showLockWarning = true
                return
            }
        }

        // Acquire lock and open
        let ok = BudgetEditLock.acquire(for: budget.id, initials: userInitials)
        if ok {
            heldEditLockBudgetID = budget.id
            forceReadOnlyBecauseLocked = false
            // Force SwiftUI to re-render by clearing first
            selectedBudgetID = nil
            DispatchQueue.main.async {
                selectedBudgetID = budget.id
            }
        } else {
            // Lock reappeared from another device between check and acquire
            let info = BudgetEditLock.readLockInfo(for: budget.id)
            pendingOpenBudgetID = budget.id
            pendingLockInfo = info
            showLockWarning = true
        }
    }

    private func openBudgetReadOnly(_ budgetID: UUID) {
        // Do not acquire lock
        forceReadOnlyBecauseLocked = true
        selectedBudgetID = budgetID
    }

    private func closeBudgetEditor() {
        if let held = heldEditLockBudgetID {
            BudgetEditLock.release(for: held)
            heldEditLockBudgetID = nil
        }
        forceReadOnlyBecauseLocked = false
        selectedBudgetID = nil
    }

    @ViewBuilder
    private func finalizeQuoteSheetView() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Finalize as Quote")
                .font(.headline)

            Text("This will create quote:")

            if finalizePreviewNumber.isEmpty {
                Text("Enter initials to preview the number.")
                    .foregroundColor(.secondary)
            } else {
                Text(finalizePreviewNumber).textSelection(.enabled)
                    .font(.system(.body, design: .monospaced))
            }

            Text("and lock the budget. You won’t be able to edit it afterwards.")

            HStack {
                Text("Initials:")
                TextField("MM", text: $finalizeInitialsDraft)
                    .frame(width: 80)
                    .onChange(of: finalizeInitialsDraft) { _, _ in
                        updateFinalizePreviewNumber()
                    }
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") {
                    showFinalizeQuoteSheet = false
                }
                Button("Create Quote") {
                    commitFinalizeAsQuote()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(finalizePreviewNumber.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 520)
        .onAppear {
            if finalizeInitialsDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                finalizeInitialsDraft = userInitials
            }
            updateFinalizePreviewNumber()
        }
    }

    
    var body: some View {
        HSplitView {

            // ── Left sidebar: budget list ─────────────────────────────────
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PROJECT")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .kerning(0.5)
                        Text(project?.name ?? "").textSelection(.enabled)
                            .font(.title3).bold()
                            .lineLimit(2)
                    }
                    Spacer()
                    Button { showNewBudgetSheet = true } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .keyboardShortcut("n", modifiers: [.command])
                    .help("New Budget (⌘N)")
                }
                .padding(.horizontal, 12).padding(.vertical, 10)

                Divider()

                if budgetsForProject.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "doc.text").font(.system(size: 32)).foregroundColor(.secondary)
                        Text("No budgets yet").foregroundColor(.secondary).font(.callout)
                        Button("Create First Budget") { showNewBudgetSheet = true }
                            .buttonStyle(.borderedProminent).padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(budgetsForProject) { b in
                            BudgetListRow(
                                budget: b,
                                isSelected: selectedBudgetID == b.id,
                                onOpen:      { openBudgetForEditing(b) },
                                onFinalize:  { beginFinalizeAsQuote(for: b) },
                                onMarkActive:{ budgets.markAsActive(b.id) },
                                onUnlock:    { budgets.unlock(b.id) },
                                onDuplicate: {
                                    if let nb = budgets.duplicateAsDraft(b.id) { openBudgetForEditing(nb) }
                                },
                                onDelete: { pendingDeleteID = b.id; showDeleteConfirm = true }
                            )
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)

            // ── Right panel ───────────────────────────────────────────────
            Group {
                if let selectedID = selectedBudgetID,
                   let budget = budgets.budgets.first(where: { $0.id == selectedID }) {
                    BudgetEditor(
                        budget: budget,
                        isReadOnly: (budget.state != .draft) || forceReadOnlyBecauseLocked
                    )
                    .environmentObject(budgets)
                    .environmentObject(roomCats)
                    .environmentObject(personCats)
                    .environmentObject(ServiceStore.shared)
                    .toolbar {
                        ToolbarItemGroup {
                            Button("Set as Quote") { beginFinalizeAsQuote(for: budget) }
                                .disabled(budget.state != .draft || forceReadOnlyBecauseLocked)
                            Button("Set Active (Lock)") { budgets.markAsActive(budget.id) }
                                .disabled(budget.state == .activeLocked)
                            if budget.state == .activeLocked {
                                Button("Unlock") { budgets.unlock(budget.id) }
                            }
                            Divider()
                            Button("Export PDF…") {
                                if let proj = project { try? PDFExporter.presentSaveAndExport(budget: budget, project: proj) }
                            }
                            Button("Print…") {
                                if let proj = project { PDFExporter.print(budget: budget, project: proj) }
                            }
                            Divider()
                            Button("Close") { closeBudgetEditor() }
                                .keyboardShortcut(.cancelAction)
                        }
                    }
                } else {
                    VStack(spacing: 16) {
                        if let nsImage = NSImage(named: "AppIcon") {
                            Image(nsImage: nsImage)
                                .resizable().scaledToFit()
                                .frame(width: 140).opacity(0.08)
                        }
                        Text("Select a budget to edit")
                            .font(.title3).foregroundColor(.secondary)
                        Text("or create a new one with the + button")
                            .font(.callout).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .sheet(isPresented: $showNewBudgetSheet) {
            NewBudgetSheet { title, attentionTo, fromTemplate in
                guard let proj = project else { return }
                if let template = fromTemplate {
                    var b = budgets.createBudget(project: proj, title: template.name)
                    b.lines = template.lines
                    b.discountPercent = template.discountPercent
                    b.contingencyPercent = template.contingencyPercent
                    b.exportLanguage = template.exportLanguage
                    if !attentionTo.isEmpty { b.attentionTo = attentionTo }
                    budgets.upsert(b); openBudgetForEditing(b)
                } else {
                    var b = budgets.createBudget(project: proj, title: title.isEmpty ? nil : title)
                    if !attentionTo.isEmpty { b.attentionTo = attentionTo; budgets.upsert(b) }
                    openBudgetForEditing(b)
                }
                newBudgetTitle = ""; newBudgetAttentionTo = ""
            }
            .environmentObject(templateStore)
        }
        .alert("Delete Budget", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let id = pendingDeleteID, let b = budgets.budgets.first(where: { $0.id == id }) { budgets.delete(b) }
                pendingDeleteID = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteID = nil }
        } message: { Text("Deleting is undoable. Are you sure?") }
        .sheet(isPresented: $showFinalizeQuoteSheet) { finalizeQuoteSheetView() }
        .alert("Quote Numbering", isPresented: showFinalizeErrorAlert) {
            Button("OK") { finalizeErrorMessage = nil }
        } message: { Text(finalizeErrorMessage ?? "") }
        .alert("Budget already open", isPresented: $showLockWarning) {
            Button("Open Read-Only") {
                if let id = pendingOpenBudgetID { openBudgetReadOnly(id) }
                pendingOpenBudgetID = nil; pendingLockInfo = nil
            }
            if let info = pendingLockInfo, info.deviceName == currentDeviceName {
                Button("Clear Lock and Open", role: .destructive) {
                    if let id = pendingOpenBudgetID {
                        BudgetEditLock.release(for: id)
                        let ok = BudgetEditLock.acquire(for: id, initials: userInitials)
                        if ok { heldEditLockBudgetID = id; forceReadOnlyBecauseLocked = false; selectedBudgetID = id }
                        else { pendingLockInfo = BudgetEditLock.readLockInfo(for: id); showLockWarning = true }
                    }
                    pendingOpenBudgetID = nil; pendingLockInfo = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingOpenBudgetID = nil; pendingLockInfo = nil }
        } message: {
            if let info = pendingLockInfo { Text("This budget is already open on \(info.deviceName). Open read-only?") }
            else { Text("This budget is already open on another system. Open read-only?") }
        }
        .onDisappear {
            if let held = heldEditLockBudgetID { BudgetEditLock.release(for: held); heldEditLockBudgetID = nil }
        }
    }

    // MARK: - Budget List Row

    private struct BudgetListRow: View {
        let budget: ProjectBudget
        let isSelected: Bool
        let onOpen: () -> Void
        let onFinalize: () -> Void
        let onMarkActive: () -> Void
        let onUnlock: () -> Void
        let onDuplicate: () -> Void
        let onDelete: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(budget.title).lineLimit(1)
                    StateBadge(state: budget.state)
                    Spacer()
                    Menu("Open ▾") {
                        Button("Open") { onOpen() }
                        Divider()
                        Button("Duplicate as Draft") { onDuplicate() }
                        Divider()
                        Button("Delete", role: .destructive) { onDelete() }
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 72)
                }
                Text(budget.updatedAt.formatted(date: .abbreviated, time: .shortened)).textSelection(.enabled)
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture { onOpen() }
        }
    }

    // MARK: - New Budget Sheet

    private struct NewBudgetSheet: View {
        @Environment(\.dismiss) private var dismiss
        @EnvironmentObject private var templateStore: QuoteTemplateStore

        let onCreate: (String, String, QuoteTemplate?) -> Void

        @State private var title: String = ""
        @State private var attentionTo: String = ""
        @State private var selectedTemplate: QuoteTemplate? = nil
        @State private var useTemplate: Bool = false
        @State private var showManageTemplates = false
        @FocusState private var titleFocused: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 20) {
                Text("New Budget").font(.title2).bold()

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Title (optional)").foregroundColor(.secondary).font(.callout)
                        TextField("Budget title", text: $title)
                            .textFieldStyle(.roundedBorder)
                            .focused($titleFocused)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Attention (client contact)").foregroundColor(.secondary).font(.callout)
                        TextField("Person at client", text: $attentionTo)
                            .textFieldStyle(.roundedBorder)
                    }

                    if !templateStore.templates.isEmpty {
                        Divider()
                        Toggle("Start from template", isOn: $useTemplate)
                            .toggleStyle(.switch)
                        if useTemplate {
                            HStack {
                                Picker("Template", selection: $selectedTemplate) {
                                    Text("Choose…").tag(QuoteTemplate?.none)
                                    ForEach(templateStore.templates) { t in
                                        Text(t.name).tag(QuoteTemplate?.some(t))
                                    }
                                }
                                .pickerStyle(.menu)
                                Button {
                                    showManageTemplates = true
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Manage templates")
                            }
                            if let t = selectedTemplate {
                                Text("\(t.lines.count) lines · Discount \(String(format: "%.1f", t.discountPercent))% · Contingency \(String(format: "%.1f", t.contingencyPercent))%")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }

                HStack {
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Create Budget") {
                        onCreate(title, attentionTo, useTemplate ? selectedTemplate : nil)
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
            .frame(width: 400)
            .onAppear { titleFocused = true }
            .sheet(isPresented: $showManageTemplates) {
                ManageTemplatesSheet()
                    .environmentObject(templateStore)
            }
        }
    }

    // MARK: - Manage Templates sheet

    private struct ManageTemplatesSheet: View {
        @EnvironmentObject private var templateStore: QuoteTemplateStore
        @Environment(\.dismiss) private var dismiss
        @State private var templateToDelete: QuoteTemplate? = nil
        @State private var showDeleteConfirm = false

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Manage Templates").font(.title2).bold()
                    Spacer()
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                .padding(20)

                Divider()

                if templateStore.templates.isEmpty {
                    VStack {
                        Spacer()
                        Text("No templates saved yet.")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    List {
                        ForEach(templateStore.templates) { t in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.name).font(.body)
                                    Text("\(t.lines.count) lines · Discount \(String(format: "%.1f", t.discountPercent))%")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    templateToDelete = t
                                    showDeleteConfirm = true
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .frame(width: 360, height: 320)
            .confirmationDialog(
                "Delete \"\(templateToDelete?.name ?? "")\"?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let t = templateToDelete {
                        templateStore.delete(t)
                        templateToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) { templateToDelete = nil }
            } message: {
                Text("This template will be permanently removed.")
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
        @State private var showSaveTemplateSheet = false
        @State private var templateName: String = ""
        @State private var discountText: String = ""
        @State private var contingencyText: String = ""
        @State private var priceAgreementText: String = ""
        // Build index groups for each section (stable order = enum order)
        private var linesBySection: [(BudgetSection, [Int])] {
            BudgetSection.allCases.map { sec in
                let idxs = budget.lines.indices.filter { budget.lines[$0].section == sec }
                return (sec, idxs)
            }
        }
        private func bindingForLine(id: UUID) -> Binding<BudgetLine>? {
            guard let idx = budget.lines.firstIndex(where: { $0.id == id }) else { return nil }
            return $budget.lines[idx]
        }

        // Optional: subtotal per section (active lines only)
        private func sectionSubtotal(_ sec: BudgetSection) -> Double {
            budget.lines.filter { $0.section == sec && $0.isActive }.reduce(0) { $0 + $1.amountSell }
        }
        
        var body: some View {
            VStack(spacing: 0) {
                // Controls row
                HStack(spacing: 12) {
                    AddLineMenu(language: budget.exportLanguage) { addRoomLine($0) } addPerson: { addPersonLine($0) } addMisc: { addMiscLine() } addService: { addServiceLine($0) }
                        .disabled(isReadOnly)
                    
                    Spacer()
                    
                    // 🔹 New button here
                    Button("Save as Template…") {
                        // Pre-fill a suggested name (you can change this)
                        templateName = budget.title.isEmpty ? "New Template" : budget.title
                        showSaveTemplateSheet = true
                    }
                    .disabled(isReadOnly)
                    
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
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
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
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isReadOnly)
                    }

                    // Price agreement (internal, used to calculate discount %)
                    HStack(spacing: 10) {
                        Text("Price agreement (€)")
                            .foregroundColor(.secondary)

                        TextField("0", text: $priceAgreementText)
                            .frame(width: 120)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isReadOnly)

                        Button("Apply") {
                            guard !isReadOnly else { return }

                            let raw = priceAgreementText
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .replacingOccurrences(of: ",", with: ".")

                            // Empty field → clear stored price, do not change discount
                            guard !raw.isEmpty else {
                                budget.priceAgreement = nil
                                persist()
                                return
                            }

                            guard let agreed = Double(raw), agreed > 0 else {
                                return
                            }

                            budget.priceAgreement = agreed

                            let S = budget.subtotalSell
                            let C = budget.contingencyPercent
                            let baseWithContingency = S * (1.0 + C / 100.0)

                            if baseWithContingency > 0 {
                                var D = 100.0 * (1.0 - agreed / baseWithContingency)
                                if !D.isFinite { D = 0 }
                                // clamp discount between 0% and 100%
                                D = max(0, min(100, D))

                                // Round to 4dp to avoid floating point accumulation in per-line math
                                budget.discountPercent = (D * 10000).rounded() / 10000
                                discountText = String(format: "%.2f", D)
                            }

                            persist()
                        }
                        .disabled(isReadOnly)
                    }
                }
                .padding(12)

                // NEW: Editable budget title

                HStack(spacing: 8) {
                    Text("Budget title:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("Untitled budget", text: $budget.title, onCommit: {
                        // Save when the user finishes editing
                        if !isReadOnly {
                            persist()
                        }
                    })
                    .textFieldStyle(.roundedBorder)
                    .disabled(isReadOnly)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
                // NEW: Attention / person at client
                HStack(spacing: 8) {
                    Text("Attention:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField(
                        "Person at client",
                        text: Binding(
                            get: { budget.attentionTo ?? "" },
                            set: {
                                budget.attentionTo = $0
                                if !isReadOnly {
                                    persist()
                                }
                            }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .disabled(isReadOnly)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

                // NEW: General notes (shown on PDF/Print)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes (will appear on export):")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextEditor(text: Binding(
                        get: { budget.generalNotes },
                        set: { newValue in
                            budget.generalNotes = newValue
                            if !isReadOnly { persist() }
                        }
                    ))
                    .font(.system(size: 12))
                    .frame(height: 90)              // ~5 lines
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.25))
                    )
                    .disabled(isReadOnly)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

                HStack(spacing: 8) {
                    Text("Export language:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $budget.exportLanguage) {
                        ForEach(ExportLanguage.allCases) { lang in
                            Text(lang.label).tag(lang)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: CGFloat(ExportLanguage.allCases.count) * 40)
                    .onChange(of: budget.exportLanguage, initial: false) { _, _ in
                        if !isReadOnly {
                            persist()
                        }
                    }
                    .disabled(isReadOnly)

                }
                .padding(.vertical, 4)
                
                // Lines
                List {
                    // Column headers
                    HStack(spacing: 8) {
                        Color.clear.frame(width: 16)
                        Text("Description").frame(minWidth: 160, maxWidth: 220, alignment: .leading)
                        Text("Unit").frame(width: 60, alignment: .center)
                        Text("Qty").frame(width: 60, alignment: .trailing)
                        Text("Sell €/u").frame(width: 90, alignment: .trailing)
                        Text("Buy €/u").frame(width: 90, alignment: .trailing)
                        Text("Total sell").frame(width: 100, alignment: .trailing)
                        Text("Total cost").frame(width: 100, alignment: .trailing)
                        Text("After disc.").frame(width: 100, alignment: .trailing)
                        Spacer()
                        Color.clear.frame(width: 80)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    .listRowBackground(Color.secondary.opacity(0.07))
                    .listRowSeparator(.hidden)
                    ForEach(linesBySection, id: \.0) { (sec, idxs) in
                        if !idxs.isEmpty {
                            sectionView(sec: sec, idxs: idxs)
                        }
                    }
                }
                .listStyle(.inset)
                .environment(\.defaultMinListRowHeight, 30)
                .onChangeCompat(budget.lines) { _ in
                    // Autosave whenever any line changes (qty, unit, rate, notes, etc.)
                    persist()
                }
                .onDisappear {
                    // Safety net: only save when editable
                    if !isReadOnly {
                        persist()
                    }
                }
                
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

                if let agreed = budget.priceAgreement, agreed > 0 {
                    priceAgreementText = String(format: "%.2f", agreed)
                } else {
                    priceAgreementText = ""
                }
            }
            .sheet(isPresented: $showSaveTemplateSheet) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Save as Template")
                        .font(.headline)
                    
                    Text("This will save the current budget structure as a reusable quote template.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("Template name", text: $templateName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                    
                    HStack {
                        Spacer()
                        Button("Cancel") {
                            showSaveTemplateSheet = false
                        }
                        Button("Save") {
                            let trimmed = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            
                            let t = QuoteTemplate(
                                name: trimmed,
                                lines: budget.lines,
                                discountPercent: budget.discountPercent,
                                contingencyPercent: budget.contingencyPercent,
                                exportLanguage: budget.exportLanguage
                            )
                            
                            QuoteTemplateStore.shared.add(t)
                            showSaveTemplateSheet = false
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(20)
                .frame(width: 360)
            }
            
        }
        
        // MARK: - Section view helper (extracted to avoid type-checker timeouts)
        @ViewBuilder
        private func sectionView(sec: BudgetSection, idxs: [Int]) -> some View {
            let ids = idxs.map { budget.lines[$0].id }
            Section {
                ForEach(ids, id: \.self) { id in
                    if let lineBinding = bindingForLine(id: id) {
                        BudgetLineRow(
                            line: lineBinding,
                            discountPercent: budget.discountPercent,
                            isReadOnly: isReadOnly,
                            language: budget.exportLanguage,
                            onDelete: { deleteLine(id) },
                            onDuplicate: { duplicateLine(lineBinding.wrappedValue) },
                            onChangeSection: { newSec in
                                if let idx = budget.lines.firstIndex(where: { $0.id == id }) {
                                    budget.lines[idx].section = newSec
                                    persist()
                                }
                            }
                        )
                    }
                }
                .onMove { from, to in
                    guard !isReadOnly else { return }
                    var localIDs = ids
                    localIDs.move(fromOffsets: from, toOffset: to)
                    let snapshot = budget.lines
                    let reordered = localIDs.compactMap { movedID in
                        snapshot.first(where: { $0.id == movedID })
                    }
                    guard reordered.count == idxs.count else { return }
                    var newLines = snapshot
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
                        .font(.body.weight(.semibold))
                        .foregroundColor(.secondary)
                    Color.clear.frame(width: 280) // aligns with toggle + menu
                }
            }
        }

        // MARK: Actions
        private func persist() {
            guard !isReadOnly else { return }
            budgets.upsert(budget)
        }

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
        private func addServiceLine(_ s: Service) {
            guard !isReadOnly else { return }
            let line = BudgetLine.from(service: s, quantity: 1)
            budget.upsert(line)
            persist()
        }
        private func duplicateLine(_ line: BudgetLine) {
            guard !isReadOnly else { return }
            var copy = line
            copy.id = UUID()      // new ID so it’s a distinct line
            budget.upsert(copy)   // update local editor copy
            persist()             // save back to BudgetStore
        }
        
    }
    
    // MARK: - Add Line Menu
    private struct AddLineMenu: View {
        @EnvironmentObject private var roomCats: RoomCategoryStore
        @EnvironmentObject private var personCats: PersonCategoryStore
        @EnvironmentObject private var services: ServiceStore

        var language: ExportLanguage = .english
        var addRoom: (RoomCategory) -> Void
        var addPerson: (PersonCategory) -> Void
        var addMisc: () -> Void
        var addService: (Service) -> Void

        private func t(_ s: String) -> String {
            localizedExportLabel(s, language: language)
        }

        var body: some View {
            Menu {
                Section("Room Categories") {
                    ForEach(roomCats.categories.filter { $0.isActive }.sorted { $0.name < $1.name }) { c in
                        Button(t(c.name)) { addRoom(c) }
                    }
                }

                Section("Person Categories") {
                    ForEach(personCats.categories.filter { $0.isActive }.sorted { $0.name < $1.name }) { c in
                        Button(t(c.name)) { addPerson(c) }
                    }
                }

                if !services.services.isEmpty {
                    Section("Services") {
                        ForEach(services.services.sorted { $0.name < $1.name }) { s in
                            Button("\(t(s.name)) — \(s.unitName) @ €\((NSDecimalNumber(decimal: s.unitPriceEUR).doubleValue), specifier: "%.2f")") {
                                addService(s)
                            }
                        }
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
        let discountPercent: Double
        let isReadOnly: Bool
        let language: ExportLanguage
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
                
                // NAME + NOTES COLUMN
                VStack(alignment: .leading, spacing: 2) {
                    // Name
                    if line.kind == .misc {
                        if isReadOnly {
                            Text(line.name)
                                .bold()
                        } else {
                            TextField("Name", text: $line.name)
                                .textFieldStyle(.roundedBorder)
                        }
                    } else {
                        Text(localizedExportLabel(line.name, language: language))
                            .bold()
                    }
                    
                    // 🔹 NEW: Notes
                    if isReadOnly {
                        if !line.notes.isEmpty {
                            Text(line.notes)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        TextField("Notes", text: $line.notes)
                            .font(.footnote)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .frame(minWidth: 160, maxWidth: 220, alignment: .leading)
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
                Text("€ " + String(format: "%.2f", line.amountSell * (1 - discountPercent / 100)))
                    .frame(width: 100, alignment: .trailing)
                    .foregroundColor(.blue)
                
                Color.clear.frame(width: 26)
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
    private func beginFinalizeAsQuote(for budget: ProjectBudget) {
        finalizeBudgetID = budget.id
        finalizeInitialsDraft = userInitials
        finalizeErrorMessage = nil

        // Always show the sheet. If initials are missing, we just show no preview yet.
        showFinalizeQuoteSheet = true
        updateFinalizePreviewNumber()
        
    }
    private func updateFinalizePreviewNumber() {
        let initials = finalizeInitialsDraft.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !initials.isEmpty else {
            finalizePreviewNumber = ""
            return
        }

        let year = Calendar.current.component(.year, from: Date())
        do {
            finalizePreviewNumber = try QuoteNumbering.previewNextQuoteNumber(year: year, initials: initials)
        } catch {
            finalizePreviewNumber = ""
            finalizeErrorMessage = error.localizedDescription
        }
    }

    private func commitFinalizeAsQuote() {
        guard let id = finalizeBudgetID else { return }

        let initials = finalizeInitialsDraft
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard !initials.isEmpty else {
            finalizeErrorMessage = "Please enter initials."
            return
        }

        // Persist initials (editable in the dialog)
        userInitials = initials

        // Reserve number + promote
        budgets.markAsQuote(id, initials: initials)

        // Close dialog
        showFinalizeQuoteSheet = false
    }
}
