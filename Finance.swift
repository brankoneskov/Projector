//
// Finance.swift
// Projector
//

import Foundation
import AppKit

// MARK: - Finance

struct Finance {
    static func sessionRevenue(
        _ s: Session,
        rooms: [Room],
        people: [Person],
        roomCategories: [RoomCategory] = RoomCategoryStore.shared.categories,
        personCategories: [PersonCategory] = PersonCategoryStore.shared.categories
    ) -> Double {
        let roomRate = rateForRoomSelection(roomName: s.room,
                                            chosenCategoryID: s.roomCategoryID,
                                            rooms: rooms,
                                            roomCategories: roomCategories,
                                            kind: .sell)
        let peopleRate = people
            .filter { s.peopleIDs.contains($0.id) }
            .reduce(0.0) { sum, p in
                let chosen = s.peopleRoles[p.id]
                return sum + rateForPersonSelection(person: p,
                                                    chosenCategoryID: chosen,
                                                    personCategories: personCategories,
                                                    kind: .sell)
            }
        let hours = s.billableHours
        return hours * (roomRate + peopleRate)
    }

    static func sessionCost(
        _ s: Session,
        rooms: [Room],
        people: [Person],
        roomCategories: [RoomCategory] = RoomCategoryStore.shared.categories,
        personCategories: [PersonCategory] = PersonCategoryStore.shared.categories
    ) -> Double {
        let roomCost = rateForRoomSelection(roomName: s.room,
                                            chosenCategoryID: s.roomCategoryID,
                                            rooms: rooms,
                                            roomCategories: roomCategories,
                                            kind: .buy)
        let peopleCost = people
            .filter { s.peopleIDs.contains($0.id) }
            .reduce(0.0) { sum, p in
                let chosen = s.peopleRoles[p.id]
                return sum + rateForPersonSelection(person: p,
                                                    chosenCategoryID: chosen,
                                                    personCategories: personCategories,
                                                    kind: .buy)
            }
        let hours = s.billableHours
        return hours * (roomCost + peopleCost)
    }

    static func serviceRevenue(_ booking: ServiceBooking, catalog: [Service]) -> Double {
        guard let svc = catalog.first(where: { $0.id == booking.serviceId }) else { return 0 }
        let unitPrice = NSDecimalNumber(decimal: svc.unitPriceEUR).doubleValue
        if let q = booking.variableQuantity {
            return NSDecimalNumber(decimal: q).doubleValue * unitPrice
        }
        return unitPrice
    }

    static func serviceCost(_ booking: ServiceBooking, catalog: [Service]) -> Double {
        guard let svc = catalog.first(where: { $0.id == booking.serviceId }) else { return 0 }
        let unitCost = NSDecimalNumber(decimal: svc.unitCostEUR).doubleValue
        if let q = booking.variableQuantity {
            return NSDecimalNumber(decimal: q).doubleValue * unitCost
        }
        return unitCost
    }

    private enum RateKind { case sell, buy }

    private static func rateForRoomSelection(
        roomName: String,
        chosenCategoryID: UUID?,
        rooms: [Room],
        roomCategories: [RoomCategory],
        kind: RateKind
    ) -> Double {
        guard let r = rooms.first(where: { $0.name.caseInsensitiveCompare(roomName) == .orderedSame }) else { return 0 }
        let idToUse = chosenCategoryID ?? r.categoryIDs.first
        if let id = idToUse, let cat = roomCategories.first(where: { $0.id == id }) {
            return (kind == .sell) ? cat.sellRatePerHour : cat.buyCostPerHour
        }
        return (kind == .sell) ? r.sellRatePerHour : r.buyCostPerHour
    }

    private static func rateForPersonSelection(
        person: Person,
        chosenCategoryID: UUID?,
        personCategories: [PersonCategory],
        kind: RateKind
    ) -> Double {
        let idToUse = chosenCategoryID ?? person.categoryIDs.first
        guard let id = idToUse, let cat = personCategories.first(where: { $0.id == id }) else { return 0 }
        return (kind == .sell) ? cat.sellRatePerHour : cat.buyCostPerHour
    }

    static func currency(_ v: Double) -> String { String(format: "%.2f", v) }
}

// MARK: - ICSBuilder

enum ICSBuilder {
    private static func utc(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.string(from: date)
    }

    static func makeICS(
        summary: String,
        start: Date,
        end: Date,
        location: String,
        description: String,
        attendees: [(name: String, email: String)] = []
    ) -> Data {
        let now = Date()
        let uid = UUID().uuidString + "@studioscheduler"
        var lines: [String] = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//StudioScheduler People//EN",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH",
            "BEGIN:VEVENT",
            "UID:\(uid)",
            "DTSTAMP:\(utc(now))",
            "DTSTART:\(utc(start))",
            "DTEND:\(utc(end))",
            "SUMMARY:\(summary)",
        ]
        if !location.isEmpty { lines.append("LOCATION:\(location)") }
        if !description.isEmpty { lines.append("DESCRIPTION:\(description.replacingOccurrences(of: "\n", with: "\\n"))") }
        for a in attendees where !a.email.isEmpty {
            let cn = a.name.isEmpty ? a.email : a.name
            lines.append("ATTENDEE;CN=\(cn):mailto:\(a.email)")
        }
        lines.append(contentsOf: ["END:VEVENT", "END:VCALENDAR"])
        return lines.joined(separator: "\n").data(using: .utf8) ?? Data()
    }

    static func writeTempICS(filename: String, data: Data) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }
}
