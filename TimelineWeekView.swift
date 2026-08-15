//
// TimelineWeekView.swift
// Projector
//

import SwiftUI

// MARK: - Week View

struct TimelineWeekView: View {
    let weekStart: Date
    let sessions: [Session]
    let rooms: [String]
    let zoom: Double
    var lightMode: Bool = false

    @Binding var selectedDay: Date

    var onSelect: (Session, SessionOccurrence?) -> Void
    var onCreate: (_ room: String, _ start: Date, _ end: Date) -> Void = { _,_,_ in }

    private var days: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private static let weekDayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return df
    }()

    private func holidayName(for date: Date) -> String? {
        let cal = Calendar.current
        guard cal.isPublicHoliday(date) else { return nil }
        let comps = cal.dateComponents([.month, .day], from: date)
        guard let m = comps.month, let d = comps.day else { return nil }
        // Fixed Portuguese holidays
        switch (m, d) {
        case (1,  1):  return "New Year"
        case (4,  25): return "Freedom Day"
        case (5,  1):  return "Labour Day"
        case (6,  10): return "Portugal Day"
        case (8,  15): return "Assumption"
        case (10, 5):  return "Republic Day"
        case (11, 1):  return "All Saints"
        case (12, 1):  return "Independence"
        case (12, 8):  return "Imm. Conception"
        case (12, 25): return "Christmas"
        default: break
        }
        // Easter-based holidays
        let year = cal.component(.year, from: date)
        let easter = easterSunday(year: year)
        let diff = cal.dateComponents([.day], from: easter, to: date).day ?? 0
        switch diff {
        case -2: return "Good Friday"
        case  0: return "Easter"
        case 60: return "Corpus Christi"
        default: return "Holiday"
        }
    }

    @ViewBuilder
    private func weekDayHeader(for date: Date) -> some View {
        let cal = Calendar.current
        let today = cal.isDateInToday(date)
        let holiday = holidayName(for: date)
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Text(Self.weekDayFormatter.string(from: date))
                    .font(.headline)
                    .foregroundColor(today ? Color(red: 0.25, green: 0.72, blue: 0.34) : .primary)
                if today {
                    Text("today")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(red: 0.25, green: 0.72, blue: 0.34))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color(red: 0.25, green: 0.72, blue: 0.34).opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            if let name = holiday {
                Text(name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(red: 0.80, green: 0.60, blue: 0.15))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color(red: 0.80, green: 0.60, blue: 0.15).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(spacing: 8) {
                ForEach(days, id: \.self) { day in
                    VStack(spacing: 4) {
                        weekDayHeader(for: day)

                        TimelineDayView(
                            day: day,
                            sessions: sessions,
                            rooms: rooms,
                            zoom: zoom,
                            lightMode: lightMode,
                            onSelect: { s in
                                selectedDay = s.start
                                onSelect(s, nil)
                            },
                            condensed: true,
                            onPrevDay: {},
                            onNextDay: {},
                            onCreate: { room, start, end in
                                selectedDay = start
                                onCreate(room, start, end)
                            }
                        )
                    }
                    .frame(minWidth: 220)
                }
            }
            .padding(8)
        }
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar").font(.system(size: 48)).padding(.bottom, 2)
            Text("No sessions").font(.title3).bold()
            Text("Click New to add your first session.").foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
