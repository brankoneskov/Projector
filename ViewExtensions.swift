//
// ViewExtensions.swift
// Projector
//

import SwiftUI

// MARK: - Compatibility: onChange for macOS 13.5 and 14+

extension View {
    /// Use this instead of `.onChange(of:)` to support macOS 13.5 and avoid the 14.0 deprecation warning.
    @ViewBuilder
    func onChangeCompat<V: Equatable>(_ value: V, perform action: @escaping (V) -> Void) -> some View {
        if #available(macOS 14.0, *) {
            self.onChange(of: value) { _, newValue in
                action(newValue)
            }
        } else {
            self.onChange(of: value, perform: action)
        }
    }
}

// MARK: - CSV Export

enum CSVBuilder {
    static func makeCSV(from sessions: [Session]) -> String {
        var rows: [String] = []
        rows.append(["Start","End","Title","Client","Room","Project","People","Duration(min)","Rate(/h)","Revenue","Notes"].joined(separator: ","))
        let df = DateFormatter(); df.dateStyle = .short; df.timeStyle = .short
        for s in sessions {
            let fields: [String] = [
                df.string(from: s.start),
                df.string(from: s.end),
                s.title.replacingOccurrences(of: ",", with: " "),
                s.client.replacingOccurrences(of: ",", with: " "),
                s.room.replacingOccurrences(of: ",", with: " "),
                s.projectID?.uuidString ?? "",
                s.peopleIDs.map { $0.uuidString }.joined(separator: "|"),
                String(s.durationMinutes),
                s.ratePerHour != nil ? String(format: "%.2f", s.ratePerHour!) : "",
                s.revenue != nil ? String(format: "%.2f", s.revenue!) : "",
                s.notes.replacingOccurrences(of: ",", with: " ")
            ]
            rows.append(fields.joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }
}
