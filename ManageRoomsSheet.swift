//
// ManageRoomsSheet.swift
// Projector
//

import SwiftUI

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
                Button("Manage Categories…") { openWindow(id: "roomCategories") }
                    .buttonStyle(.bordered)
            }
            .padding(12)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TextField("New room name", text: $name)
                    TextField("Sell €/h", text: $sell)
                        .frame(width: 90).multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder)
                    TextField("Buy €/h", text: $buy)
                        .frame(width: 90).multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder)
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
                        ForEach(rooms.rooms.filter { $0.isActive }) { r in RoomRowView(room: r) }
                    }
                    Section("Inactive") {
                        ForEach(rooms.rooms.filter { !$0.isActive }) { r in RoomRowView(room: r) }
                    }
                }
            }
            .padding(16)
        }
    }
}

// MARK: - Room Row

struct RoomRowView: View {
    @EnvironmentObject private var rooms: RoomStore
    @EnvironmentObject private var roomCategoryStore: RoomCategoryStore
    @State var room: Room
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: 12) {
            TextField("Name", text: $room.name)
                .textFieldStyle(.roundedBorder).frame(minWidth: 180)
                .onSubmit { persist() }
                .onChangeCompat(room.name) { _ in persist() }

            Menu {
                ForEach(roomCategoryStore.categories) { c in
                    if c.isActive {
                        let isOn = room.categoryIDs.contains(c.id)
                        Button {
                            if isOn { room.categoryIDs.removeAll { $0 == c.id } }
                            else if !room.categoryIDs.contains(c.id) { room.categoryIDs.append(c.id) }
                            persist()
                        } label: {
                            Label(c.name, systemImage: isOn ? "checkmark" : "")
                        }
                    }
                }
                if !room.categoryIDs.isEmpty {
                    Divider()
                    Button("Clear All", role: .destructive) { room.categoryIDs.removeAll(); persist() }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selectedCategoryNames.isEmpty ? "No Categories" : selectedCategoryNames.joined(separator: ", ")).lineLimit(1)
                    Image(systemName: "chevron.down").foregroundColor(.secondary)
                }
            }
            .frame(minWidth: 220)

            let firstCat: RoomCategory? = room.categoryIDs
                .compactMap { cid in roomCategoryStore.categories.first { $0.id == cid } }
                .first

            let effectiveSell = firstCat?.sellRatePerHour ?? room.sellRatePerHour
            let effectiveBuy  = firstCat?.buyCostPerHour  ?? room.buyCostPerHour

            Text("Sell €/h: \(String(format: "%.2f", effectiveSell))").foregroundColor(.secondary).frame(minWidth: 120, alignment: .leading)
            Text("Buy €/h: \(String(format: "%.2f", effectiveBuy))").foregroundColor(.secondary).frame(minWidth: 110, alignment: .leading)

            Spacer()

            Toggle("Active", isOn: Binding(
                get: { room.isActive },
                set: { v in room.isActive = v; persist() }
            )).labelsHidden()

            Menu("•••") {
                Button("Delete", role: .destructive) { showDeleteConfirm = true }
            }
        }
        .padding(.vertical, 4)
        .confirmationDialog("Delete Room?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { rooms.delete(room) }
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
