//
//  BillingAggregator.swift
//  Projector
//
//  Created by Branko Neskov on 06/11/2025.
//


import Foundation

struct BillingSummary: Hashable {
    var count: Int = 0
    var hours: Double = 0
    var amount: Double = 0
    // Optional: month -> summary (e.g., "2025-11")
    var byMonth: [String: BillingSummary] = [:]
}

enum BillingCutoff {
    case today // bill sessions that have fully ended before today (default)
    case date(Date)
}

struct BillingAggregator {

    /// Produce a billable summary for a project.
    /// Billable = sessions with end < cutoff AND recurrence == .none
    /// (i.e., single sessions and detached/materialized recurrences)
    static func summarizeProject(
        projectID: UUID,
        sessions: [Session],
        roomCategories: [RoomCategory],
        personCategories: [PersonCategory],
        cutoff: BillingCutoff = .today
    ) -> BillingSummary {
        let cal = Calendar.current
        let cutoffDate: Date = {
            switch cutoff {
            case .today: return cal.startOfDay(for: Date())
            case .date(let d): return d
            }
        }()

        // Index categories for fast lookup
        let roomRates: [UUID: Double] = Dictionary(uniqueKeysWithValues: roomCategories.map { ($0.id, $0.sellRatePerHour) })
        let personRates: [UUID: Double] = Dictionary(uniqueKeysWithValues: personCategories.map { ($0.id, $0.sellRatePerHour) })

        func effectiveRate(for s: Session) -> Double {
            if let explicit = s.ratePerHour, explicit > 0 { return explicit }
            let roomPart = s.roomCategoryID.flatMap { roomRates[$0] } ?? 0
            let peoplePart = s.peopleRoles.values.reduce(0.0) { sum, cid in sum + (personRates[cid] ?? 0) }
            return roomPart + peoplePart
        }

        func monthKey(_ d: Date) -> String {
            let comps = cal.dateComponents([.year, .month], from: d)
            let y = comps.year ?? 0, m = comps.month ?? 0
            return String(format: "%04d-%02d", y, m)
        }

        var total = BillingSummary()

        // Filter: project, ended before cutoff, not recurring (real entries only)
        let billable = sessions.filter { s in
            s.projectID == projectID &&
            s.end < cutoffDate &&
            s.recurrence == .none
        }

        for s in billable {
            let hrs = max(0, s.billableHours)
            let rate = effectiveRate(for: s)
            let amt = hrs * rate
            total.count += 1
            total.hours += hrs
            total.amount += amt

            // monthly bucket by session start
            let key = monthKey(s.start)
            var bucket = total.byMonth[key] ?? BillingSummary()
            bucket.count += 1
            bucket.hours += hrs
            bucket.amount += amt
            total.byMonth[key] = bucket
        }

        return total
    }
}

