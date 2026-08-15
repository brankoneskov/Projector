//
// ManagePeopleSheet.swift
// Projector
//

import SwiftUI
import AppKit

// MARK: - People Manager

struct ManagePeopleSheet: View {
    @EnvironmentObject private var people: PeopleStore
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var personCategoryStore: PersonCategoryStore
    @Environment(\.openWindow) private var openWindow

    @State private var name: String = ""
    @State private var role: String = ""
    @State private var email: String = ""

    private func isValidEmail(_ s: String) -> Bool {
        let pattern = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        return NSPredicate(format: "SELF MATCHES %@", pattern).evaluate(with: s)
    }

    var body: some View {
        VStack(spacing: 0) {
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
                    people.add(p)
                    name = ""; role = ""; email = ""
                }
                .keyboardShortcut(.return)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .controlSize(.small)

            Divider()

            List {
                Section("Active") {
                    ForEach($people.people) { $p in
                        if p.isActive { PersonRow(person: $p) }
                    }
                }
                Section("Inactive") {
                    ForEach($people.people) { $p in
                        if !p.isActive { PersonRow(person: $p) }
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

// MARK: - Person Row

struct PersonRow: View {
    @EnvironmentObject private var people: PeopleStore
    @EnvironmentObject private var personCategoryStore: PersonCategoryStore
    @Binding var person: Person

    var body: some View {
        HStack(spacing: 10) {
            TextField("Name", text: $person.name)
                .textFieldStyle(.roundedBorder).frame(minWidth: 220)
                .onSubmit { persist() }
                .onChangeCompat(person.name) { _ in persist() }

            TextField("Role", text: $person.role)
                .textFieldStyle(.roundedBorder).frame(minWidth: 140)
                .onSubmit { persist() }
                .onChangeCompat(person.role) { _ in persist() }

            HStack(spacing: 8) {
                TextField("Email", text: $person.email)
                    .textFieldStyle(.roundedBorder).frame(minWidth: 220)
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

            Menu {
                ForEach(personCategoryStore.categories) { c in
                    if c.isActive {
                        let isOn = person.categoryIDs.contains(c.id)
                        Button {
                            if isOn { person.categoryIDs.removeAll { $0 == c.id } }
                            else { if !person.categoryIDs.contains(c.id) { person.categoryIDs.append(c.id) } }
                            persist()
                        } label: {
                            Label(c.name, systemImage: isOn ? "checkmark" : "")
                        }
                    }
                }
                if !person.categoryIDs.isEmpty {
                    Divider()
                    Button("Clear All", role: .destructive) { person.categoryIDs.removeAll(); persist() }
                }
            } label: {
                HStack(spacing: 6) {
                    let names = personCategoryStore.categories
                        .filter { person.categoryIDs.contains($0.id) }
                        .map { $0.name }
                        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                    Text(names.isEmpty ? "No Categories" : names.joined(separator: ", ")).lineLimit(1)
                    Image(systemName: "chevron.down").foregroundColor(.secondary)
                }
            }
            .frame(minWidth: 220)

            let firstCat: PersonCategory? = person.categoryIDs
                .compactMap { cid in personCategoryStore.categories.first { $0.id == cid } }
                .first

            Text("Sell €/h: \(String(format: "%.2f", firstCat?.sellRatePerHour ?? 0))")
                .foregroundColor(.secondary).frame(minWidth: 120, alignment: .leading)
            Text("Buy €/h: \(String(format: "%.2f", firstCat?.buyCostPerHour ?? 0))")
                .foregroundColor(.secondary).frame(minWidth: 110, alignment: .leading)

            Spacer()

            Toggle("Active", isOn: $person.isActive)
                .labelsHidden()
                .toggleStyle(.switch)
                .onChange(of: person.isActive) { _, _ in withAnimation { persist() } }
        }
        .padding(.vertical, 4)
    }

    private func persist() { people.update(person) }
}

// MARK: - Manage Person Categories Sheet

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
                        PersonCategoryRow(category: c).environmentObject(store)
                    }
                }
                Section("Inactive") {
                    ForEach(store.categories.filter { !$0.isActive }) { c in
                        PersonCategoryRow(category: c).environmentObject(store)
                    }
                }
            }
            .listStyle(.inset)
            .environment(\.defaultMinListRowHeight, 28)
        }
    }
}

// MARK: - Person Category Row

private struct PersonCategoryRow: View {
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
                    editingName.toggle()
                    if !editingName { persist() }
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
