//
//  ServiceStore.swift
//  Projector
//
//  Created by Branko Neskov on 02/11/2025.
//
//
//  ServiceStore.swift
//  Projector
//
//  Central store for:
//  - Service catalog (definitions)
//  - Service bookings on specific dates
//

import Foundation
import Combine

@MainActor
final class ServiceStore: ObservableObject {
    // MARK: - Published state

    /// Catalog of services (things you sell: DCP encode, audio restoration, etc.)
    @Published var services: [Service] = [] {
        didSet { if !isLoading { saveServices() } }
    }

    @Published var bookings: [ServiceBooking] = [] {
        didSet { if !isLoading { saveBookings() } }
    }

    // Singleton instance used across the app
    static let shared = ServiceStore()
    private var isLoading = false
    private init() {
        load()
    }

    // MARK: - File URLs (V2: per-record folders)

    /// Services/ → one file per Service
    private var servicesFolderURL: URL {
        DataPaths.folder("Services")
    }

    /// ServiceBookings/ → one file per ServiceBooking
    private var bookingsFolderURL: URL {
        DataPaths.folder("ServiceBookings")
    }

    /// Legacy single-file formats (migration only)
    private var legacyServicesURL: URL { DataPaths.file("services.json") }
    private var legacyBookingsURL: URL { DataPaths.file("serviceBookings.json") }

    private func serviceFileURL(_ id: UUID) -> URL {
        servicesFolderURL.appendingPathComponent("\(id.uuidString).json")
    }

    private func bookingFileURL(_ id: UUID) -> URL {
        bookingsFolderURL.appendingPathComponent("\(id.uuidString).json")
    }

    // MARK: - Load / Save

    /// Reload both services and bookings from disk
    func reload() {
        load()
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }

        let fm = FileManager.default

        // -------------------------
        // 1) SERVICES (Catalog)
        // -------------------------
        do {
            let items = try fm.contentsOfDirectory(at: servicesFolderURL, includingPropertiesForKeys: nil)
            let jsonFiles = items.filter { $0.pathExtension.lowercased() == "json" }

            // Migration: if folder empty but legacy services.json exists
            if jsonFiles.isEmpty, fm.fileExists(atPath: legacyServicesURL.path) {
                let data = try Data(contentsOf: legacyServicesURL)
                if !data.isEmpty {
                    let decoded = try JSONDecoder().decode([Service].self, from: data)
                    for s in decoded {
                        let out = try JSONEncoder().encode(s)
                        try out.write(to: serviceFileURL(s.id), options: [.atomic])
                    }
                    services = decoded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                } else {
                    services = []
                }
            } else {
                var loaded: [Service] = []
                loaded.reserveCapacity(jsonFiles.count)
                for url in jsonFiles {
                    do {
                        let data = try Data(contentsOf: url)
                        let s = try JSONDecoder().decode(Service.self, from: data)
                        loaded.append(s)
                    } catch {
                        print("⚠️ Skipping corrupt Service file \(url.lastPathComponent): \(error)")
                    }
                }
                services = loaded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
        } catch {
            print("⚠️ Failed to load Services folder: \(error)")
            // keep existing services (defensive)
        }

        // -------------------------
        // 2) BOOKINGS
        // -------------------------
        do {
            let items = try fm.contentsOfDirectory(at: bookingsFolderURL, includingPropertiesForKeys: nil)
            let jsonFiles = items.filter { $0.pathExtension.lowercased() == "json" }

            // Migration: if folder empty but legacy serviceBookings.json exists
            if jsonFiles.isEmpty, fm.fileExists(atPath: legacyBookingsURL.path) {
                let data = try Data(contentsOf: legacyBookingsURL)
                if !data.isEmpty {
                    let decoded = try JSONDecoder().decode([ServiceBooking].self, from: data)
                    for b in decoded {
                        let out = try JSONEncoder().encode(b)
                        try out.write(to: bookingFileURL(b.id), options: [.atomic])
                    }
                    bookings = decoded
                } else {
                    bookings = []
                }
            } else {
                var loaded: [ServiceBooking] = []
                loaded.reserveCapacity(jsonFiles.count)
                for url in jsonFiles {
                    do {
                        let data = try Data(contentsOf: url)
                        let b = try JSONDecoder().decode(ServiceBooking.self, from: data)
                        loaded.append(b)
                    } catch {
                        print("⚠️ Skipping corrupt ServiceBooking file \(url.lastPathComponent): \(error)")
                    }
                }
                bookings = loaded
            }
        } catch {
            print("⚠️ Failed to load ServiceBookings folder: \(error)")
            // keep existing bookings (defensive)
        }
    }



    private func saveServices() {
        let fm = FileManager.default

        // Seatbelt: don't delete all files if services array is temporarily empty
        do {
            let existing = try fm.contentsOfDirectory(at: servicesFolderURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "json" }
            if services.isEmpty, !existing.isEmpty {
                print("🛑 Refusing to overwrite Services/ with 0 services.")
                return
            }
        } catch {
            print("⚠️ Could not inspect Services/ folder: \(error)")
            return
        }

        do {
            // Write/update each service file
            for s in services {
                let data = try JSONEncoder().encode(s)
                try data.write(to: serviceFileURL(s.id), options: [.atomic])
            }

            // Remove orphan files
            let keep = Set(services.map { "\($0.id.uuidString).json" })
            let existing = try fm.contentsOfDirectory(at: servicesFolderURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "json" }

            for url in existing where !keep.contains(url.lastPathComponent) {
                try? fm.removeItem(at: url)
            }
        } catch {
            print("⚠️ Failed to save Services folder: \(error)")
        }
    }


    private func saveBookings() {
        let fm = FileManager.default

        // Seatbelt: don't delete all files if bookings array is temporarily empty
        do {
            let existing = try fm.contentsOfDirectory(at: bookingsFolderURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "json" }
            if bookings.isEmpty, !existing.isEmpty {
                print("🛑 Refusing to overwrite ServiceBookings/ with 0 bookings.")
                return
            }
        } catch {
            print("⚠️ Could not inspect ServiceBookings/ folder: \(error)")
            return
        }

        do {
            // Write/update each booking file
            for b in bookings {
                let data = try JSONEncoder().encode(b)
                try data.write(to: bookingFileURL(b.id), options: [.atomic])
            }

            // Remove orphan files
            let keep = Set(bookings.map { "\($0.id.uuidString).json" })
            let existing = try fm.contentsOfDirectory(at: bookingsFolderURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "json" }

            for url in existing where !keep.contains(url.lastPathComponent) {
                try? fm.removeItem(at: url)
            }
        } catch {
            print("⚠️ Failed to save ServiceBookings folder: \(error)")
        }
    }



    // MARK: - Catalog operations (Service)

    /// Insert or update a service definition
    func upsert(_ s: Service) {
        if let idx = services.firstIndex(where: { $0.id == s.id }) {
            services[idx] = s
        } else {
            services.append(s)
        }
    }

    /// Delete one or more services from the catalog
    func delete(_ ids: Set<UUID>) {
        services.removeAll { ids.contains($0.id) }
    }

    // MARK: - Booking operations (ServiceBooking)

    /// Create N bookings of the same service/project on a given date
    func createBookings(
        serviceId: UUID,
        projectId: UUID?,
        date: Date,
        quantity: Int,
        variableQuantity: Decimal? = nil,
        note: String = ""
    ) {
        let day = date.stripTimeToNoon()
        guard quantity > 0 else { return }

        var newOnes: [ServiceBooking] = []
        for _ in 0..<quantity {
            newOnes.append(
                ServiceBooking(
                    id: UUID(),
                    serviceId: serviceId,
                    projectId: projectId,
                    date: day,
                    status: .scheduled,
                    variableQuantity: variableQuantity,
                    notes: note
                )
            )
        }
        bookings.append(contentsOf: newOnes)
        // didSet on `bookings` will save to disk
    }
    /// Move a booking to a different date
    func move(_ bookingId: UUID, to newDate: Date) {
        if let idx = bookings.firstIndex(where: { $0.id == bookingId }) {
            bookings[idx].date = newDate.stripTimeToNoon()
        }
    }

    /// Change status (scheduled / completed / canceled)
    func setStatus(_ bookingId: UUID, _ status: ServiceStatus) {
        if let idx = bookings.firstIndex(where: { $0.id == bookingId }) {
            bookings[idx].status = status
        }
    }

    /// Change just the project associated with a booking
    func assignProject(_ bookingId: UUID, projectId: UUID?) {
        if let idx = bookings.firstIndex(where: { $0.id == bookingId }) {
            bookings[idx].projectId = projectId
        }
    }

    /// Change the underlying service definition a booking refers to
    func changeService(_ bookingId: UUID, to serviceId: UUID) {
        if let idx = bookings.firstIndex(where: { $0.id == bookingId }) {
            bookings[idx].serviceId = serviceId
        }
    }

    /// Delete one or more bookings by their IDs
    func deleteBookings(_ ids: Set<UUID>) {
        bookings.removeAll { ids.contains($0.id) }
    }
    /// Convenience overload so callers can pass [UUID]
    func deleteBookings(_ ids: [UUID]) {
        deleteBookings(Set(ids))
    }

}

