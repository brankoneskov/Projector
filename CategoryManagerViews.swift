//
// CategoryManagerViews.swift
// Projector
//

import SwiftUI

// MARK: - Non-English name detection

/// Returns true if the string contains characters outside the basic Latin range,
/// suggesting it may be a non-English word (e.g. accented characters in French,
/// German umlauts, Spanish tildes, etc.).
/// Used to warn users that category names should be in English to support
/// multilingual budget exports via the Translations dictionary.
private func looksNonEnglish(_ text: String) -> Bool {
    text.unicodeScalars.contains { scalar in
        // Allow basic Latin, digits, common punctuation and symbols
        // Flag anything outside this range as potentially non-English
        !(scalar.value < 128) // outside ASCII
    }
}

private let nonEnglishWarning = """
Category names are used as source keys for the translation system. \
For multilingual budget exports to work correctly, names should be in English.

You can add translations for other languages in Setup → Translations.

Do you want to save this name anyway?
"""

// MARK: - Person Categories Window

struct ManagePersonCategoriesView: View {
    @EnvironmentObject private var store: PersonCategoryStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var sellText: String = ""
    @State private var buyText: String = ""
    @State private var showNonEnglishWarning = false
    @State private var pendingName = ""
    @State private var pendingSell = 0.0
    @State private var pendingBuy  = 0.0

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
                        if looksNonEnglish(nm) {
                            pendingName = nm; pendingSell = sell; pendingBuy = buy
                            showNonEnglishWarning = true
                        } else {
                            addPersonCategory(name: nm, sell: sell, buy: buy)
                        }
                    }
                    .keyboardShortcut(.return)
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
        .alert("Non-English Category Name", isPresented: $showNonEnglishWarning) {
            Button("Save Anyway") { addPersonCategory(name: pendingName, sell: pendingSell, buy: pendingBuy) }
            Button("Go Back", role: .cancel) { name = pendingName }
        } message: { Text(nonEnglishWarning) }
    }

    private func addPersonCategory(name nm: String, sell: Double, buy: Double) {
        let c = PersonCategory(name: nm, sellRatePerHour: sell, buyCostPerHour: buy, isActive: true)
        store.add(c)
        name = ""; sellText = ""; buyText = ""
    }
}

// Row used by ManagePersonCategoriesView (window version)
private struct PersonCategoryRowWindow: View {
    @EnvironmentObject private var store: PersonCategoryStore
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
    @State private var showNonEnglishWarning = false
    @State private var pendingName = ""
    @State private var pendingSell = 0.0
    @State private var pendingBuy  = 0.0

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
                    if looksNonEnglish(nm) {
                        pendingName = nm; pendingSell = sv; pendingBuy = bv
                        showNonEnglishWarning = true
                    } else {
                        addRoomCategory(name: nm, sell: sv, buy: bv)
                    }
                }
                .keyboardShortcut(.return)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
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
        .alert("Non-English Category Name", isPresented: $showNonEnglishWarning) {
            Button("Save Anyway") { addRoomCategory(name: pendingName, sell: pendingSell, buy: pendingBuy) }
            Button("Go Back", role: .cancel) { name = pendingName }
        } message: { Text(nonEnglishWarning) }
    }

    private func addRoomCategory(name nm: String, sell: Double, buy: Double) {
        store.add(RoomCategory(name: nm, sellRatePerHour: sell, buyCostPerHour: buy, isActive: true))
        name = ""; self.sell = ""; self.buy = ""
    }
}

// MARK: - Room Categories Window

struct ManageRoomCategoriesView: View {
    @EnvironmentObject private var roomCategoryStore: RoomCategoryStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var sellText: String = ""
    @State private var buyText: String = ""
    @State private var showNonEnglishWarning = false
    @State private var pendingName = ""
    @State private var pendingSell = 0.0
    @State private var pendingBuy  = 0.0

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
                    if looksNonEnglish(nm) {
                        pendingName = nm; pendingSell = sell; pendingBuy = buy
                        showNonEnglishWarning = true
                    } else {
                        addRoomCat(name: nm, sell: sell, buy: buy)
                    }
                }
                .keyboardShortcut(.return)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

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
        .frame(minWidth: 620, minHeight: 420)
        .alert("Non-English Category Name", isPresented: $showNonEnglishWarning) {
            Button("Save Anyway") { addRoomCat(name: pendingName, sell: pendingSell, buy: pendingBuy) }
            Button("Go Back", role: .cancel) { name = pendingName }
        } message: { Text(nonEnglishWarning) }
    }

    private func addRoomCat(name nm: String, sell: Double, buy: Double) {
        roomCategoryStore.add(RoomCategory(name: nm, sellRatePerHour: sell, buyCostPerHour: buy, isActive: true))
        name = ""; sellText = ""; buyText = ""
    }
}

// MARK: - Room Category Row

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
