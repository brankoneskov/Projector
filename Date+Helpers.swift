//
//  Date+Helpers.swift
//  Projector
//
//  Created by Branko Neskov on 11/11/2025.
//
// MARK: - 6) Helpers
import Foundation

extension Date {
    func stripTimeToNoon() -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day], from: self)
        return cal.date(from: DateComponents(year: comps.year, month: comps.month, day: comps.day, hour: 12)) ?? self
    }
    func isSameDay(as other: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: other)
    }
    func weekdayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: self)
    }
}

