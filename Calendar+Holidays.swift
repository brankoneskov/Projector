//
//  Calendar+Holidays.swift
//  Projector
//
import Foundation

// MARK: - Fixed Portuguese public holidays

private let fixedHolidaysPT: [(month: Int, day: Int)] = [
    (1,  1),   // New Year
    (4,  25),  // Freedom Day
    (5,  1),   // Labour Day
    (6,  10),  // Portugal Day
    (8,  15),  // Assumption
    (10, 5),   // Republic Day
    (11, 1),   // All Saints
    (12, 1),   // Restoration of Independence
    (12, 8),   // Immaculate Conception
    (12, 25),  // Christmas
]

// MARK: - Easter calculation (Anonymous Gregorian algorithm)

/// Returns Easter Sunday for a given year.
func easterSunday(year: Int) -> Date {
    let a = year % 19
    let b = year / 100
    let c = year % 100
    let d = b / 4
    let e = b % 4
    let f = (b + 8) / 25
    let g = (b - f + 1) / 3
    let h = (19 * a + b - d - g + 15) % 30
    let i = c / 4
    let k = c % 4
    let l = (32 + 2 * e + 2 * i - h - k) % 7
    let m = (a + 11 * h + 22 * l) / 451
    let month = (h + l - 7 * m + 114) / 31
    let day = ((h + l - 7 * m + 114) % 31) + 1

    var comps = DateComponents()
    comps.year = year
    comps.month = month
    comps.day = day
    return Calendar.current.date(from: comps) ?? Date()
}

/// Returns all Easter-based Portuguese public holidays for a given year.
func easterHolidays(year: Int) -> Set<String> {
    let cal = Calendar.current
    let easter = easterSunday(year: year)
    let formatter = DateFormatter()
    formatter.dateFormat = "MM-dd"

    var dates: Set<String> = []

    // Good Friday — 2 days before Easter
    if let goodFriday = cal.date(byAdding: .day, value: -2, to: easter) {
        dates.insert(formatter.string(from: goodFriday))
    }
    // Easter Sunday itself
    dates.insert(formatter.string(from: easter))

    // Corpus Christi — 60 days after Easter
    if let corpusChristi = cal.date(byAdding: .day, value: 60, to: easter) {
        dates.insert(formatter.string(from: corpusChristi))
    }

    return dates
}

// MARK: - Calendar extension

extension Calendar {
    func isPublicHoliday(_ date: Date) -> Bool {
        let comps = dateComponents([.year, .month, .day], from: date)
        guard let m = comps.month, let d = comps.day, let y = comps.year else { return false }

        // Fixed holidays
        if fixedHolidaysPT.contains(where: { $0.month == m && $0.day == d }) { return true }

        // Easter-based holidays
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        let key = formatter.string(from: date)
        if easterHolidays(year: y).contains(key) { return true }

        return false
    }
}

// MARK: - Tinted day check

/// Returns true if the day should be tinted in the timeline (weekend or public holiday).
func isTintedDay(_ date: Date) -> Bool {
    let cal = Calendar.current
    if cal.isDateInWeekend(date) { return true }
    if cal.isPublicHoliday(date) { return true }
    return false
}
