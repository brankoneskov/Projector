//
// CategoryManagerViews.swift
// Projector
//

import SwiftUI

// MARK: - Person Categories Window

struct ManagePersonCategoriesView: View {
    @EnvironmentObject private var store: PersonCategoryStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var sellText: String = ""
    @State private var buyText: String = ""
    @State private var translationEntryID: UUID? = nil
    @State private var unitTranslationEntryID: UUID? = nil
    @State private var defaultBudgetSection: BudgetSection = .others

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Person Categories").font(.title2).bold()
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .keyboardShortcut("w", modifiers: [.command])
            }
            .padding(12)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    TextField("New category name", text: $name)
                    TextField("Sell €/h", text: $sellText).frame(width: 90).multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder)
                    TextField("Buy €/h", text: $buyText).frame(width: 90).multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder)
                    Button("Add") {
                        let nm   = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let sell = Double(sellText.replacingOccurrences(of: ",", with: ".")) ?? 0
                        let buy  = Double(buyText.replacingOccurrences(of: ",", with: ".")) ?? 0
                        guard !nm.isEmpty else { return }
                        addPersonCategory(name: nm, sell: sell, buy: buy)
                    }
                    .keyboardShortcut(.return)
                }

                HStack(alignment: .bottom, spacing: 12) {
                    TranslationLinkPicker(
                        title: "Name translation",
                        sourceText: name,
                        selection: $translationEntryID
                    )
                    TranslationLinkPicker(
                        title: "Unit translation (h)",
                        sourceText: "h",
                        selection: $unitTranslationEntryID
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Default quote section")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("", selection: $defaultBudgetSection) {
                            ForEach(BudgetSection.allCases, id: \.self) { section in
                                Text(section.label).tag(section)
                            }
                        }
                        .labelsHidden()
                    }
                }

                List {
                    Section("Active") {
                        ForEach(store.categories.filter { $0.isActive }) { c in PersonCategoryRowWindow(category: c) }
                    }
                    Section("Inactive") {
                        ForEach(store.categories.filter { !$0.isActive }) { c in PersonCategoryRowWindow(category: c) }
                    }
                }
            }
            .padding(16)
        }
    }

    private func addPersonCategory(name nm: String, sell: Double, buy: Double) {
        let c = PersonCategory(
            name: nm,
            sellRatePerHour: sell,
            buyCostPerHour: buy,
            isActive: true,
            translationEntryID: translationEntryID,
            unitTranslationEntryID: unitTranslationEntryID,
            defaultBudgetSection: defaultBudgetSection
        )
        store.add(c)
        name = ""; sellText = ""; buyText = ""
        translationEntryID = nil
        unitTranslationEntryID = nil
        defaultBudgetSection = .others
    }
}

// Row used by ManagePersonCategoriesView (window version)
private struct PersonCategoryRowWindow: View {
    @EnvironmentObject private var store: PersonCategoryStore
    @ObservedObject private var translations = TranslationStore.shared
    @State var category: PersonCategory
    @State private var editingName = false
    @State private var sellText: String
    @State private var buyText: String

    init(category: PersonCategory) {
        _category = State(initialValue: category)
        _sellText = State(initialValue: category.sellRatePerHour == 0 ? "" : String(format: "%.2f", category.sellRatePerHour))
        _buyText  = State(initialValue: category.buyCostPerHour  == 0 ? "" : String(format: "%.2f", category.buyCostPerHour))
    }

    var body: some View {
        HStack(spacing: 12) {
            if editingName {
                TextField("Name", text: $category.name).textFieldStyle(.roundedBorder).frame(minWidth: 220)
            } else {
                Text(category.name).bold().frame(minWidth: 220, alignment: .leading)
            }

            HStack(spacing: 6) {
                Text("Sell €/h").foregroundColor(.secondary)
                TextField("0", text: $sellText).frame(width: 80).multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder)
                    .onChangeCompat(sellText) { _ in persist() }
            }

            HStack(spacing: 6) {
                Text("Buy €/h").foregroundColor(.secondary)
                TextField("0", text: $buyText).frame(width: 80).multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder)
                    .onChangeCompat(buyText) { _ in persist() }
            }

            Spacer()

            Toggle("Active", isOn: Binding(
                get: { category.isActive },
                set: { v in category.isActive = v; persist() }
            )).labelsHidden()

            Menu("•••") {
                Button(editingName ? "Stop Editing Name" : "Edit Name") {
                    editingName.toggle(); if !editingName { persist() }
                }
                if category.translationEntryID == nil,
                   let suggested = translations.entry(matching: category.name) {
                    Button("Use suggested name: \(suggested.key)") {
                        category.translationEntryID = suggested.id
                        persist()
                    }
                }
                if category.unitTranslationEntryID == nil,
                   let suggested = translations.entry(matching: "h") {
                    Button("Use suggested unit: \(suggested.key)") {
                        category.unitTranslationEntryID = suggested.id
                        persist()
                    }
                }
                Picker("Name translation", selection: Binding(
                    get: { category.translationEntryID },
                    set: { category.translationEntryID = $0; persist() }
                )) {
                    Text("Not linked").tag(nil as UUID?)
                    ForEach(translations.entries) { entry in
                        Text(entry.key).tag(entry.id as UUID?)
                    }
                }
                Picker("Unit translation", selection: Binding(
                    get: { category.unitTranslationEntryID },
                    set: { category.unitTranslationEntryID = $0; persist() }
                )) {
                    Text("Not linked").tag(nil as UUID?)
                    ForEach(translations.entries) { entry in
                        Text(entry.key).tag(entry.id as UUID?)
                    }
                }
                Picker("Default quote section", selection: Binding(
                    get: { category.defaultBudgetSection ?? .others },
                    set: { category.defaultBudgetSection = $0; persist() }
                )) {
                    ForEach(BudgetSection.allCases, id: \.self) { section in
                        Text(section.label).tag(section)
                    }
                }
                Divider()
                ConfirmingDestructiveButton("Delete", title: "Delete Category", onConfirm: { store.delete(category) })
            }
        }
        .padding(.vertical, 4)
    }

    private func persist() {
        let sell = Double(sellText.replacingOccurrences(of: ",", with: ".")) ?? category.sellRatePerHour
        let buy  = Double(buyText.replacingOccurrences(of: ",", with: ".")) ?? category.buyCostPerHour
        var c = category; c.sellRatePerHour = sell; c.buyCostPerHour = buy
        store.update(c); category = c
    }
}

// MARK: - Room Categories Sheet

struct ManageRoomCategoriesSheet: View {
    @EnvironmentObject private var store: RoomCategoryStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var sell: String = ""
    @State private var buy: String = ""
    @State private var translationEntryID: UUID? = nil
    @State private var unitTranslationEntryID: UUID? = nil
    @State private var defaultBudgetSection: BudgetSection = .others

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Room Categories").font(.title3).bold()
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            Divider()

            HStack(spacing: 8) {
                TextField("New category name", text: $name)
                TextField("Sell €/h", text: $sell).frame(width: 90).multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder)
                TextField("Buy €/h", text: $buy).frame(width: 90).multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder)
                Button("Add") {
                    let nm = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !nm.isEmpty else { return }
                    let sv = Double(sell.replacingOccurrences(of: ",", with: ".")) ?? 0
                    let bv = Double(buy.replacingOccurrences(of: ",", with: ".")) ?? 0
                    addRoomCategory(name: nm, sell: sv, buy: bv)
                }
                .keyboardShortcut(.return)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .controlSize(.small)

            HStack(alignment: .bottom, spacing: 12) {
                TranslationLinkPicker(
                    title: "Name translation",
                    sourceText: name,
                    selection: $translationEntryID
                )
                TranslationLinkPicker(
                    title: "Unit translation (h)",
                    sourceText: "h",
                    selection: $unitTranslationEntryID
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text("Default quote section")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $defaultBudgetSection) {
                        ForEach(BudgetSection.allCases, id: \.self) { section in
                            Text(section.label).tag(section)
                        }
                    }
                    .labelsHidden()
                }
            }
            .padding(.horizontal, 12).padding(.bottom, 8)
            .controlSize(.small)

            Divider()

            List {
                Section("Active") {
                    ForEach(store.categories.filter { $0.isActive }) { c in
                        RoomCategoryRow(category: c).environmentObject(store)
                    }
                }
                Section("Inactive") {
                    ForEach(store.categories.filter { !$0.isActive }) { c in
                        RoomCategoryRow(category: c).environmentObject(store)
                    }
                }
            }
            .listStyle(.inset)
            .environment(\.defaultMinListRowHeight, 28)
        }
    }

    private func addRoomCategory(name nm: String, sell: Double, buy: Double) {
        store.add(RoomCategory(
            name: nm,
            sellRatePerHour: sell,
            buyCostPerHour: buy,
            isActive: true,
            translationEntryID: translationEntryID,
            unitTranslationEntryID: unitTranslationEntryID,
            defaultBudgetSection: defaultBudgetSection
        ))
        name = ""; self.sell = ""; self.buy = ""
        translationEntryID = nil
        unitTranslationEntryID = nil
        defaultBudgetSection = .others
    }
}

// MARK: - Room Categories Window

struct ManageRoomCategoriesView: View {
    @EnvironmentObject private var roomCategoryStore: RoomCategoryStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var sellText: String = ""
    @State private var buyText: String = ""
    @State private var translationEntryID: UUID? = nil
    @State private var unitTranslationEntryID: UUID? = nil
    @State private var defaultBudgetSection: BudgetSection = .others

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Room Categories").font(.title2).bold()
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .keyboardShortcut("w", modifiers: [.command])
            }
            .padding(12)

            Divider()

            HStack(spacing: 8) {
                TextField("New category name", text: $name)
                TextField("Sell €/h", text: $sellText).frame(width: 100).multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder)
                TextField("Buy €/h", text: $buyText).frame(width: 100).multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder)
                Button("Add") {
                    let nm = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !nm.isEmpty else { return }
                    let sell = Double(sellText.replacingOccurrences(of: ",", with: ".")) ?? 0
                    let buy  = Double(buyText.replacingOccurrences(of: ",", with: ".")) ?? 0
                    addRoomCat(name: nm, sell: sell, buy: buy)
                }
                .keyboardShortcut(.return)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            HStack(alignment: .bottom, spacing: 12) {
                TranslationLinkPicker(
                    title: "Name translation",
                    sourceText: name,
                    selection: $translationEntryID
                )
                TranslationLinkPicker(
                    title: "Unit translation (h)",
                    sourceText: "h",
                    selection: $unitTranslationEntryID
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text("Default quote section")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $defaultBudgetSection) {
                        ForEach(BudgetSection.allCases, id: \.self) { section in
                            Text(section.label).tag(section)
                        }
                    }
                    .labelsHidden()
                }
            }
            .padding(.horizontal, 12).padding(.bottom, 8)

            Divider()

            List {
                Section("Active") {
                    ForEach(roomCategoryStore.categories.filter { $0.isActive }) { c in RoomCategoryRow(category: c) }
                }
                Section("Inactive") {
                    ForEach(roomCategoryStore.categories.filter { !$0.isActive }) { c in RoomCategoryRow(category: c) }
                }
            }
            .listStyle(.inset)
            .environment(\.defaultMinListRowHeight, 28)
            .padding(.bottom, 8)
        }
        .frame(minWidth: 760, minHeight: 460)
    }

    private func addRoomCat(name nm: String, sell: Double, buy: Double) {
        roomCategoryStore.add(RoomCategory(
            name: nm,
            sellRatePerHour: sell,
            buyCostPerHour: buy,
            isActive: true,
            translationEntryID: translationEntryID,
            unitTranslationEntryID: unitTranslationEntryID,
            defaultBudgetSection: defaultBudgetSection
        ))
        name = ""; sellText = ""; buyText = ""
        translationEntryID = nil
        unitTranslationEntryID = nil
        defaultBudgetSection = .others
    }
}

// MARK: - Room Category Row

private struct RoomCategoryRow: View {
    @EnvironmentObject private var roomCategoryStore: RoomCategoryStore
    @ObservedObject private var translations = TranslationStore.shared
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
                    .textFieldStyle(.roundedBorder).frame(minWidth: 220)
                    .onSubmit { persist() }
                    .onChangeCompat(category.name) { _ in persist() }
            } else {
                Text(category.name).bold().frame(minWidth: 220, alignment: .leading)
            }

            HStack(spacing: 6) {
                Text("Sell €/h").foregroundColor(.secondary)
                TextField("0", text: $sellText).frame(width: 90).multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder)
                    .onSubmit { persist() }.onChangeCompat(sellText) { _ in persist() }
            }

            HStack(spacing: 6) {
                Text("Buy €/h").foregroundColor(.secondary)
                TextField("0", text: $buyText).frame(width: 90).multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder)
                    .onSubmit { persist() }.onChangeCompat(buyText) { _ in persist() }
            }

            Spacer()

            Toggle("Active", isOn: Binding(
                get: { category.isActive },
                set: { v in category.isActive = v; persist() }
            )).labelsHidden()

            Menu("•••") {
                Button(editingName ? "Stop Editing Name" : "Edit Name") {
                    editingName.toggle(); if !editingName { persist() }
                }
                if category.translationEntryID == nil,
                   let suggested = translations.entry(matching: category.name) {
                    Button("Use suggested name: \(suggested.key)") {
                        category.translationEntryID = suggested.id
                        persist()
                    }
                }
                if category.unitTranslationEntryID == nil,
                   let suggested = translations.entry(matching: "h") {
                    Button("Use suggested unit: \(suggested.key)") {
                        category.unitTranslationEntryID = suggested.id
                        persist()
                    }
                }
                Picker("Name translation", selection: Binding(
                    get: { category.translationEntryID },
                    set: { category.translationEntryID = $0; persist() }
                )) {
                    Text("Not linked").tag(nil as UUID?)
                    ForEach(translations.entries) { entry in
                        Text(entry.key).tag(entry.id as UUID?)
                    }
                }
                Picker("Unit translation", selection: Binding(
                    get: { category.unitTranslationEntryID },
                    set: { category.unitTranslationEntryID = $0; persist() }
                )) {
                    Text("Not linked").tag(nil as UUID?)
                    ForEach(translations.entries) { entry in
                        Text(entry.key).tag(entry.id as UUID?)
                    }
                }
                Picker("Default quote section", selection: Binding(
                    get: { category.defaultBudgetSection ?? .others },
                    set: { category.defaultBudgetSection = $0; persist() }
                )) {
                    ForEach(BudgetSection.allCases, id: \.self) { section in
                        Text(section.label).tag(section)
                    }
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
        let sell = Double(sellText.replacingOccurrences(of: ",", with: ".")) ?? category.sellRatePerHour
        let buy  = Double(buyText.replacingOccurrences(of: ",", with: ".")) ?? category.buyCostPerHour
        category.sellRatePerHour = sell; category.buyCostPerHour = buy
        roomCategoryStore.update(category)
    }
}

