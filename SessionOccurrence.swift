//
//  SessionOccurrences.swift
//  Projector
//
//  Created by Branko Neskov on 02/11/2025.
//
// SessionOccurrence.swift (new small helper)
import Foundation

struct SessionOccurrence: Identifiable, Hashable {
    let session: Session
    let interval: DateInterval

    // Stable id per session occurrence (sessionID + start timestamp)
    var id: String {
        "\(session.id.uuidString)-\(Int(interval.start.timeIntervalSince1970))"
    }

    var start: Date { interval.start }
    var end: Date { interval.end }
}
/// One visible occurrence of a session (used for recurring sessions)
/// Expand all sessions into visible occurrences within a given time window
func occurrencesForDisplay(
    sessions: [Session],
    visibleWindow: DateInterval
) -> [SessionOccurrence] {
    var out: [SessionOccurrence] = []
    for s in sessions {
        for occ in s.occurrences(in: visibleWindow) {
            out.append(SessionOccurrence(session: s, interval: occ))
        }
    }
    return out.sorted { $0.start < $1.start }
}
