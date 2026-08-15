//
//  Session.swift
//  Projector
//
//  Created by Branko Neskov on 02/11/2025.
//
import Foundation

// MARK: - Recurrence

enum RecurrenceRule: Codable, Equatable, Hashable {
    case none
    case daily(every: Int, until: Date?)
    case weekly(every: Int, weekdays: Set<Int>, until: Date?) // 1=Sun ... 7=Sat
}

// MARK: - Model

struct Session: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var client: String
    var room: String
    var start: Date
    var durationMinutes: Int
    var breakMinutes: Int = 0        // ← NEW
    var confirmed: Bool = false
    var ratePerHour: Double?
    var notes: String
    var projectID: UUID?
    var peopleIDs: [UUID] = []
    var recurrence: RecurrenceRule = .none
    // Link to a recurrence series when an occurrence is materialized (hybrid)
    var seriesID: UUID? = nil

    // Specific dates to skip when expanding a recurring session (virtual + hybrid)
    var exceptions: Set<Date> = []

    // NEW: category selections used for THIS booking
    var roomCategoryID: UUID? = nil             // chosen category for the booked room
    var peopleRoles: [UUID: UUID] = [:]         // personID -> chosen categoryID

    /// End of the booked session on the calendar (full duration)
    var end: Date {
        start.addingTimeInterval(TimeInterval(durationMinutes * 60))
    }

    /// Effective billable minutes after subtracting unpaid break.
    /// Break is clamped between 0 and the total duration.
    var billableMinutes: Int {
        let clampedBreak = max(0, min(breakMinutes, durationMinutes))
        return durationMinutes - clampedBreak
    }

    /// Effective billable hours as Double.
    var billableHours: Double {
        Double(billableMinutes) / 60.0
    }

    /// Revenue based on billable hours (duration minus break).
    var revenue: Double? {
        guard let rate = ratePerHour else { return nil }
        return billableHours * rate
    }

}

// MARK: - Recurrence Expansion

extension Session {
    func baseInterval() -> DateInterval { DateInterval(start: start, end: end) }

    func occurrences(in window: DateInterval, calendar: Calendar = .current) -> [DateInterval] {
        switch recurrence {
        case .none:
            let di = baseInterval()
            return di.intersects(window) ? [di] : []

        case .daily(let every, let until):
            return expandDaily(every: every, until: until, window: window, calendar: calendar)

        case .weekly(let every, let weekdays, let until):
            return expandWeekly(every: every, weekdays: weekdays, until: until, window: window, calendar: calendar)
        }
    }

    private func duration() -> TimeInterval { end.timeIntervalSince(start) }

    private func expandDaily(every: Int, until: Date?, window: DateInterval, calendar: Calendar) -> [DateInterval] {
        guard every > 0 else { return [] }
        let limit = until ?? window.end
        var out: [DateInterval] = []
        var cursor = start
        while let prev = calendar.date(byAdding: .day, value: -every, to: cursor),
              prev >= max(start, window.start.addingTimeInterval(-duration())) {
            cursor = prev
        }
        while cursor <= limit {
            let di = DateInterval(start: cursor, duration: duration())
            if di.start >= start, di.intersects(window) { out.append(di) }   // ⬅️ guard lower bound
            guard let next = calendar.date(byAdding: .day, value: every, to: cursor) else { break }
            cursor = next
        }
        return out
    }

    private func expandWeekly(every: Int, weekdays: Set<Int>, until: Date?, window: DateInterval, calendar: Calendar) -> [DateInterval] {
        guard every > 0, !weekdays.isEmpty else { return [] }
        let limit = until ?? window.end
        var out: [DateInterval] = []
        let startWeek = calendar.dateInterval(of: .weekOfYear, for: start)!.start
        var weekStart = startWeek
        while let prev = calendar.date(byAdding: .weekOfYear, value: -every, to: weekStart),
              prev >= max(startWeek, window.start.addingTimeInterval(-7 * 24 * 3600)) {
            weekStart = prev
        }
        while weekStart <= limit {
            let deltaWeeks = calendar.dateComponents([.weekOfYear], from: startWeek, to: weekStart).weekOfYear ?? 0
            if deltaWeeks % every == 0 {
                for wd in weekdays {
                    var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekStart)
                    comps.weekday = wd
                    if let day = calendar.date(from: comps),
                       let st = calendar.date(bySettingHour: calendar.component(.hour, from: start),
                                              minute: calendar.component(.minute, from: start),
                                              second: 0, of: day) {
                        let di = DateInterval(start: st, duration: duration())
                        if di.start >= start, di.intersects(window) { out.append(di) }   // ⬅️ guard lower bound
                    }
                }
            }
            guard let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) else { break }
            weekStart = nextWeek
        }
        return out.sorted { $0.start < $1.start }
    }
}
// MARK: - Codable (manual, for forward/backward JSON compatibility)

extension Session {
    enum CodingKeys: String, CodingKey {
        case id, title, client, room, start, durationMinutes, breakMinutes,
             confirmed, ratePerHour, notes, projectID, peopleIDs,
             recurrence, seriesID, exceptions, roomCategoryID, peopleRoles
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decodeIfPresent(UUID.self,   forKey: .id)              ?? UUID()
        title           = try c.decodeIfPresent(String.self, forKey: .title)           ?? ""
        client          = try c.decodeIfPresent(String.self, forKey: .client)          ?? ""
        room            = try c.decodeIfPresent(String.self, forKey: .room)            ?? ""
        start           = try c.decode(Date.self,            forKey: .start)
        durationMinutes = try c.decodeIfPresent(Int.self,    forKey: .durationMinutes) ?? 120
        breakMinutes    = try c.decodeIfPresent(Int.self,    forKey: .breakMinutes)    ?? 0
        confirmed       = try c.decodeIfPresent(Bool.self,   forKey: .confirmed)       ?? false
        ratePerHour     = try c.decodeIfPresent(Double.self, forKey: .ratePerHour)
        notes           = try c.decodeIfPresent(String.self, forKey: .notes)           ?? ""
        projectID       = try c.decodeIfPresent(UUID.self,   forKey: .projectID)
        peopleIDs       = try c.decodeIfPresent([UUID].self, forKey: .peopleIDs)       ?? []
        recurrence      = try c.decodeIfPresent(RecurrenceRule.self, forKey: .recurrence) ?? .none
        seriesID        = try c.decodeIfPresent(UUID.self,   forKey: .seriesID)
        exceptions      = try c.decodeIfPresent(Set<Date>.self, forKey: .exceptions)  ?? []
        roomCategoryID  = try c.decodeIfPresent(UUID.self,   forKey: .roomCategoryID)

        // peopleRoles was stored as [UUID] array in old files, [String:UUID] dict in new ones
        if let dictRaw = try? c.decodeIfPresent([String: UUID].self, forKey: .peopleRoles) {
            peopleRoles = Dictionary(uniqueKeysWithValues: dictRaw.compactMap { k, v in
                UUID(uuidString: k).map { ($0, v) }
            })
        } else if let arr = try? c.decodeIfPresent([UUID].self, forKey: .peopleRoles) {
            _ = arr
            peopleRoles = [:]
        } else {
            peopleRoles = [:]
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,              forKey: .id)
        try c.encode(title,           forKey: .title)
        try c.encode(client,          forKey: .client)
        try c.encode(room,            forKey: .room)
        try c.encode(start,           forKey: .start)
        try c.encode(durationMinutes, forKey: .durationMinutes)
        try c.encode(breakMinutes,    forKey: .breakMinutes)
        try c.encode(confirmed,       forKey: .confirmed)
        try c.encodeIfPresent(ratePerHour,    forKey: .ratePerHour)
        try c.encode(notes,           forKey: .notes)
        try c.encodeIfPresent(projectID,      forKey: .projectID)
        try c.encode(peopleIDs,       forKey: .peopleIDs)
        try c.encode(recurrence,      forKey: .recurrence)
        try c.encodeIfPresent(seriesID,       forKey: .seriesID)
        try c.encode(exceptions,      forKey: .exceptions)
        try c.encodeIfPresent(roomCategoryID, forKey: .roomCategoryID)
        let rawRoles = Dictionary(uniqueKeysWithValues: peopleRoles.map { ($0.key.uuidString, $0.value) })
        try c.encode(rawRoles,        forKey: .peopleRoles)
    }
}
