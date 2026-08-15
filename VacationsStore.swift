//
//  VacationsLane.swift
//  Projector
//
//  Created by Branko Neskov on 12/11/2025.
//
//
//  Vacations.swift
//  Projector
//

import SwiftUI
import Combine

// MARK: - Vacation Models

enum VacationStatus: String, Codable, CaseIterable, Identifiable {
    case planned
    case approved
    case canceled
    var id: String { rawValue }
}

struct VacationEntry: Identifiable, Hashable, Codable {
    let id: UUID
    var personId: UUID
    var date: Date   // date-only semantics
    var status: VacationStatus
    var notes: String = ""
}

// MARK: - Vacations Store

@MainActor
final class VacationsStore: ObservableObject {
    static let shared = VacationsStore()

    @Published private(set) var vacations: [VacationEntry] = []

    // V2 per-record folder
    private let folderURL: URL = DataPaths.folder("Vacations")
    private var isLoading = false

    private init() {
        load()
    }

    private func fileURL(for id: UUID) -> URL {
        folderURL.appendingPathComponent("\(id.uuidString).json")
    }

    // MARK: - Load / Save

    func load() {
        let fm = FileManager.default
        isLoading = true
        defer { isLoading = false }

        do {
            // Ensure folder exists
            _ = folderURL

            let jsonFiles = try fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "json" }

            var loaded: [VacationEntry] = []
            loaded.reserveCapacity(jsonFiles.count)

            for url in jsonFiles {
                do {
                    let data = try Data(contentsOf: url)
                    let v = try JSONDecoder().decode(VacationEntry.self, from: data)
                    loaded.append(v)
                } catch {
                    // Skip corrupt file; never wipe all data
                    print("⚠️ Skipping corrupt vacation file \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }

            // Sort: by date, then person (stable-ish)
            loaded.sort {
                if $0.date != $1.date { return $0.date < $1.date }
                return $0.personId.uuidString < $1.personId.uuidString
            }

            self.vacations = loaded
        } catch {
            print("⚠️ Failed to load Vacations/ folder: \(error.localizedDescription)")
            // keep existing self.vacations as-is
        }
    }

    private func writeOne(_ entry: VacationEntry) {
        guard !isLoading else { return }
        do {
            let data = try JSONEncoder().encode(entry)
            try data.write(to: fileURL(for: entry.id), options: [.atomic])
        } catch {
            print("⚠️ Failed to write vacation \(entry.id): \(error.localizedDescription)")
        }
    }

    private func deleteOneFile(_ id: UUID) {
        guard !isLoading else { return }
        let url = fileURL(for: id)
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Mutations

    func add(
        personIds: [UUID],
        startDate: Date,
        endDate: Date,
        status: VacationStatus = .planned,
        note: String = ""
    ) {
        guard let range = Calendar.current.datesBetween(
            start: startDate.stripTimeToNoon(),
            end: endDate.stripTimeToNoon()
        ) else { return }

        var newOnes: [VacationEntry] = []
        newOnes.reserveCapacity(personIds.count * range.count)

        for pid in personIds {
            for d in range {
                let entry = VacationEntry(
                    id: UUID(),
                    personId: pid,
                    date: d,
                    status: status,
                    notes: note
                )
                newOnes.append(entry)
                writeOne(entry) // ✅ per-record write
            }
        }

        vacations.append(contentsOf: newOnes)
        vacations.sort {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.personId.uuidString < $1.personId.uuidString
        }
    }

    func setStatus(_ id: UUID, _ status: VacationStatus) {
        if let idx = vacations.firstIndex(where: { $0.id == id }) {
            vacations[idx].status = status
            writeOne(vacations[idx]) // ✅ update one file
        }
    }

    func move(_ id: UUID, to newDate: Date) {
        if let idx = vacations.firstIndex(where: { $0.id == id }) {
            vacations[idx].date = newDate.stripTimeToNoon()
            writeOne(vacations[idx]) // ✅ update one file
        }
    }

    func delete(_ ids: Set<UUID>) {
        for id in ids {
            deleteOneFile(id) // ✅ delete only those files
        }
        vacations.removeAll { ids.contains($0.id) }
    }
}


// MARK: - Date helper for ranges

extension Calendar {
    func datesBetween(start: Date, end: Date) -> [Date]? {
        guard start <= end else { return nil }

        var dates: [Date] = []
        var d = start
        while d <= end {
            dates.append(d)
            d = self.date(byAdding: .day, value: 1, to: d)!
                .stripTimeToNoon()
        }
        return dates
    }
}
struct VacationQuickCreateSheet: View {
    @Environment(\.dismiss) private var dismiss

    let initialDate: Date
    let peopleById: [UUID: Person]
    let onCreate: (_ start: Date, _ end: Date, _ personIds: [UUID], _ status: VacationStatus) -> Void

    @State private var startDate: Date
    @State private var endDate: Date
    @State private var selectedPeople: Set<UUID> = []
    @State private var status: VacationStatus = .planned

    init(
        initialDate: Date,
        peopleById: [UUID: Person],
        onCreate: @escaping (_ start: Date, _ end: Date, _ personIds: [UUID], _ status: VacationStatus) -> Void
    ) {
        let normalized = initialDate.stripTimeToNoon()
        self.initialDate = normalized
        self.peopleById = peopleById
        self.onCreate = onCreate
        _startDate = State(initialValue: normalized)
        _endDate   = State(initialValue: normalized)
    }

    private var sortedPeople: [Person] {
        peopleById.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Vacation")
                .font(.headline)

            HStack {
                DatePicker("Start", selection: $startDate, displayedComponents: .date)
                DatePicker("End", selection: $endDate, displayedComponents: .date)
            }

            Text("People")
                .font(.subheadline)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(sortedPeople) { person in
                        Toggle(
                            isOn: Binding(
                                get: { selectedPeople.contains(person.id) },
                                set: { isOn in
                                    if isOn {
                                        selectedPeople.insert(person.id)
                                    } else {
                                        selectedPeople.remove(person.id)
                                    }
                                }
                            )
                        ) {
                            Text(person.name)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 200)

            Picker("Status", selection: $status) {
                ForEach(VacationStatus.allCases) { s in
                    Text(s.rawValue.capitalized).tag(s)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") {
                    guard !selectedPeople.isEmpty else { return }

                    let start = min(startDate, endDate).stripTimeToNoon()
                    let end   = max(startDate, endDate).stripTimeToNoon()

                    onCreate(start, end, Array(selectedPeople), status)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 360, minHeight: 260)
    }
}
