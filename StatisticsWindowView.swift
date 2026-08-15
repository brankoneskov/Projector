//
//  StatisticsWindowView.swift
//  Projector
//
//  Occupancy model:
//  - Available hours  = Mon–Fri working hours only (configurable window)
//  - Booked hours     = ALL sessions, including weekends
//  - Occupancy > 100% is valid and means the room/person was used beyond normal capacity
//

import SwiftUI

// MARK: - Period Selector

enum StatsPeriod: String, CaseIterable, Identifiable {
    case currentMonth = "This Month"
    case last30       = "Last 30 Days"
    case last60       = "Last 60 Days"
    case last90       = "Last 90 Days"
    case thisYear     = "This Year"
    case lastYear     = "Last Year"
    case custom       = "Custom"

    var id: String { rawValue }
}

// MARK: - Stats tab

enum StatsTab: String, CaseIterable, Identifiable {
    case rooms            = "Rooms"
    case roomCategories   = "Room Categories"
    case people           = "People"
    case peopleCategories = "People Categories"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .rooms:            return "building.2"
        case .roomCategories:   return "tag"
        case .people:           return "person.2"
        case .peopleCategories: return "person.badge.key"
        }
    }
}

// MARK: - Shared stat entry type

private struct OccupancyStat: Identifiable {
    let id: String
    let name: String
    let bookedHours: Double
    let availableHours: Double
    var weekendHours: Double = 0
    var sessionCount: Int    = 0

    /// Can exceed 1.0 — weekend / after-hours work counts as booked but not as capacity
    var occupancy: Double {
        guard availableHours > 0 else { return 0 }
        return bookedHours / availableHours
    }
}

// MARK: - Main View

struct StatisticsWindowView: View {

    @ObservedObject private var sessionStore   = SessionStore.shared
    @ObservedObject private var roomStore      = RoomStore.shared
    @ObservedObject private var peopleStore    = PeopleStore.shared
    @ObservedObject private var roomCatStore   = RoomCategoryStore.shared
    @ObservedObject private var personCatStore = PersonCategoryStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var period: StatsPeriod = .currentMonth
    @State private var customStart: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customEnd: Date   = Date()
    @State private var workdayStartHour: Int = 9
    @State private var workdayEndHour: Int   = 19
    @State private var activeTab: StatsTab   = .rooms

    // MARK: - Date range

    private var dateRange: (start: Date, end: Date) {
        let cal = Calendar.current
        let now = Date()
        // For all relative periods, cap the end at now so future bookings
        // don't inflate the statistics. "This Month" = 1st Apr → today, not → Apr 30.
        // Last year is the only period that is entirely in the past and needs no cap.
        switch period {
        case .currentMonth:
            let s = cal.date(from: cal.dateComponents([.year, .month], from: now))!
            return (s, now)
        case .last30:
            return (cal.date(byAdding: .day, value: -30, to: now)!, now)
        case .last60:
            return (cal.date(byAdding: .day, value: -60, to: now)!, now)
        case .last90:
            return (cal.date(byAdding: .day, value: -90, to: now)!, now)
        case .thisYear:
            let s = cal.date(from: cal.dateComponents([.year], from: now))!
            return (s, now)
        case .lastYear:
            let thisYear = cal.date(from: cal.dateComponents([.year], from: now))!
            let s = cal.date(byAdding: .year, value: -1, to: thisYear)!
            return (s, thisYear)
        case .custom:
            return (customStart, customEnd)
        }
    }

    // MARK: - Sessions in range (ALL, including weekends)

    private var sessionsInRange: [Session] {
        let (start, end) = dateRange
        return sessionStore.sessions.filter { $0.start >= start && $0.start < end }
    }

    private var weekendSessionsInRange: [Session] {
        let cal = Calendar.current
        return sessionsInRange.filter {
            let wd = cal.component(.weekday, from: $0.start)
            return wd == 1 || wd == 7
        }
    }

    // MARK: - Available hours (Mon–Fri only — the capacity denominator)

    private func workingDays(from start: Date, to end: Date) -> Int {
        let cal = Calendar.current
        var count = 0
        var current = cal.startOfDay(for: start)
        let endDay  = cal.startOfDay(for: end)
        while current < endDay {
            let wd = cal.component(.weekday, from: current)
            if wd != 1 && wd != 7 { count += 1 }
            current = cal.date(byAdding: .day, value: 1, to: current)!
        }
        return count
    }

    private var hoursPerDay: Double { Double(max(0, workdayEndHour - workdayStartHour)) }

    private var totalAvailableHours: Double {
        let (start, end) = dateRange
        return Double(workingDays(from: start, to: end)) * hoursPerDay
    }

    // MARK: - Room stats

    private var roomStats: [OccupancyStat] {
        let cal = Calendar.current
        return roomStore.rooms.filter { $0.isActive }.map { room in
            let sessions = sessionsInRange.filter { $0.room == room.name }
            let booked   = sessions.reduce(0.0) { $0 + $1.billableHours }
            let weekend  = sessions.filter {
                let wd = cal.component(.weekday, from: $0.start); return wd == 1 || wd == 7
            }.reduce(0.0) { $0 + $1.billableHours }
            return OccupancyStat(
                id: room.name, name: room.name,
                bookedHours: booked, availableHours: totalAvailableHours,
                weekendHours: weekend, sessionCount: sessions.count
            )
        }.sorted { $0.occupancy > $1.occupancy }
    }

    // MARK: - Room category stats

    private var roomCategoryStats: [OccupancyStat] {
        let cal = Calendar.current
        return roomCatStore.categories.filter { $0.isActive }.map { cat in
            let sessions = sessionsInRange.filter { s in
                // Prefer the category chosen on the booking, fall back to the room's first category
                let resolved: UUID? = s.roomCategoryID
                    ?? roomStore.rooms
                        .first { $0.name.caseInsensitiveCompare(s.room) == .orderedSame }?
                        .categoryIDs.first
                return resolved == cat.id
            }
            let booked  = sessions.reduce(0.0) { $0 + $1.billableHours }
            let weekend = sessions.filter {
                let wd = cal.component(.weekday, from: $0.start); return wd == 1 || wd == 7
            }.reduce(0.0) { $0 + $1.billableHours }
            return OccupancyStat(
                id: cat.id.uuidString, name: cat.name,
                bookedHours: booked, availableHours: totalAvailableHours,
                weekendHours: weekend, sessionCount: sessions.count
            )
        }.sorted { $0.occupancy > $1.occupancy }
    }

    // MARK: - Person stats

    private var personStats: [OccupancyStat] {
        let cal = Calendar.current
        return peopleStore.people.filter { $0.isActive }.map { person in
            let sessions = sessionsInRange.filter { $0.peopleIDs.contains(person.id) }
            let booked   = sessions.reduce(0.0) { $0 + $1.billableHours }
            let weekend  = sessions.filter {
                let wd = cal.component(.weekday, from: $0.start); return wd == 1 || wd == 7
            }.reduce(0.0) { $0 + $1.billableHours }
            return OccupancyStat(
                id: person.id.uuidString, name: person.name,
                bookedHours: booked, availableHours: totalAvailableHours,
                weekendHours: weekend, sessionCount: sessions.count
            )
        }.sorted { $0.occupancy > $1.occupancy }
    }

    // MARK: - Person category stats

    private var personCategoryStats: [OccupancyStat] {
        let cal = Calendar.current
        return personCatStore.categories.filter { $0.isActive }.map { cat in
            // A session counts if at least one person is booked under this category
            let sessions = sessionsInRange.filter { $0.peopleRoles.values.contains(cat.id) }
            let booked  = sessions.reduce(0.0) { $0 + $1.billableHours }
            let weekend = sessions.filter {
                let wd = cal.component(.weekday, from: $0.start); return wd == 1 || wd == 7
            }.reduce(0.0) { $0 + $1.billableHours }
            return OccupancyStat(
                id: cat.id.uuidString, name: cat.name,
                bookedHours: booked, availableHours: totalAvailableHours,
                weekendHours: weekend, sessionCount: sessions.count
            )
        }.sorted { $0.occupancy > $1.occupancy }
    }

    // MARK: - KPI helpers

    private var totalBookedHours: Double { sessionsInRange.reduce(0) { $0 + $1.billableHours } }
    private var totalWeekendHours: Double { weekendSessionsInRange.reduce(0) { $0 + $1.billableHours } }

    private var overallOccupancy: Double {
        let active = roomStats.filter { $0.availableHours > 0 }
        guard !active.isEmpty else { return 0 }
        return active.reduce(0.0) { $0 + $1.occupancy } / Double(active.count)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Image(systemName: "chart.bar.xaxis")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Statistics")
                    .font(.title2).bold()
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .keyboardShortcut("w", modifiers: [.command])
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()
            controlsBar
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // KPI cards
                    kpiRow

                    // Tab switcher
                    Picker("", selection: $activeTab) {
                        ForEach(StatsTab.allCases) { tab in
                            Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)

                    // Tab content
                    Group {
                        switch activeTab {
                        case .rooms:
                            occupancySection(
                                title: "Room Occupancy",
                                subtitle: "Booked hours (all days incl. weekends) ÷ Mon–Fri capacity (\(workdayStartHour):00–\(workdayEndHour):00). Above 100% = weekend or extended use.",
                                stats: roomStats
                            )
                        case .roomCategories:
                            occupancySection(
                                title: "Room Category Occupancy",
                                subtitle: "Grouped by the room category assigned to each booking. Same Mon–Fri capacity denominator as rooms.",
                                stats: roomCategoryStats
                            )
                        case .people:
                            occupancySection(
                                title: "Tech Utilisation",
                                subtitle: "Billable hours per person across all sessions. Orange segment = weekend hours. Above 100% = worked beyond normal capacity.",
                                stats: personStats
                            )
                        case .peopleCategories:
                            occupancySection(
                                title: "People Category Utilisation",
                                subtitle: "Grouped by the role category assigned per booking. A session counts once per matching category. Same Mon–Fri capacity denominator.",
                                stats: personCategoryStats
                            )
                        }
                    }
                    .animation(.default, value: activeTab)
                }
                .padding(20)
            }
        }
        .frame(minWidth: 920, minHeight: 640)
    }

    // MARK: - Controls bar

    private var controlsBar: some View {
        HStack(spacing: 16) {
            Picker("Period", selection: $period) {
                ForEach(StatsPeriod.allCases) { p in
                    Text(p.rawValue).tag(p)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 160)

            if period == .custom {
                DatePicker("From", selection: $customStart, displayedComponents: .date)
                    .frame(width: 180)
                DatePicker("To", selection: $customEnd, displayedComponents: .date)
                    .frame(width: 180)
            }

            Divider().frame(height: 22)

            HStack(spacing: 6) {
                Text("Working hours (Mon–Fri):")
                    .foregroundColor(.secondary)
                Picker("", selection: $workdayStartHour) {
                    ForEach(0..<24, id: \.self) { h in
                        Text(String(format: "%02d:00", h)).tag(h)
                    }
                }
                .frame(width: 80)
                .labelsHidden()
                Text("–")
                Picker("", selection: $workdayEndHour) {
                    ForEach(1..<25, id: \.self) { h in
                        Text(String(format: "%02d:00", h)).tag(h)
                    }
                }
                .frame(width: 80)
                .labelsHidden()
            }

            Spacer()

            Text("\(sessionsInRange.count) sessions")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - KPI row

    private var kpiRow: some View {
        HStack(spacing: 16) {
            StatKPI(
                title: "Total Booked Hours",
                value: String(format: "%.1f h", totalBookedHours),
                icon: "clock.fill",
                color: .blue
            )
            StatKPI(
                title: "Avg Room Occupancy",
                value: String(format: "%.0f%%", overallOccupancy * 100),
                icon: "building.2.fill",
                color: occupancyColor(overallOccupancy),
                note: overallOccupancy > 1.0 ? "above capacity" : nil
            )
            StatKPI(
                title: "Sessions",
                value: "\(sessionsInRange.count)",
                icon: "calendar",
                color: .purple
            )
            StatKPI(
                title: "Weekend Hours",
                value: String(format: "%.1f h", totalWeekendHours),
                icon: "moon.stars",
                color: totalWeekendHours > 0 ? .orange : .secondary,
                note: totalWeekendHours > 0 ? "not counted in capacity" : nil
            )
        }
    }

    // MARK: - Generic occupancy section (shared by all four tabs)

    @ViewBuilder
    private func occupancySection(
        title: String,
        subtitle: String,
        stats: [OccupancyStat]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title, subtitle: subtitle)

            if stats.filter({ $0.bookedHours > 0 }).isEmpty {
                Text("No data for this period.")
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            } else {
                VStack(spacing: 8) {
                    // Column header
                    HStack {
                        Text("Name")
                            .frame(width: 180, alignment: .leading)
                        Text("Booked")
                            .frame(width: 70, alignment: .trailing)
                        Text("Weekend")
                            .frame(width: 72, alignment: .trailing)
                        Text("Capacity")
                            .frame(width: 72, alignment: .trailing)
                        Text("Occupancy")
                            .frame(width: 90, alignment: .trailing)
                        Text("Sessions")
                            .frame(width: 65, alignment: .trailing)
                        Spacer()
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)

                    ForEach(stats) { stat in
                        OccupancyStatRow(
                            stat: stat,
                            maxHours: stats.first?.bookedHours ?? 1
                        )
                    }
                }
            }
        }
    }

    // MARK: - Colour helper

    private func occupancyColor(_ pct: Double) -> Color {
        if pct > 1.0  { return .red }
        if pct >= 0.8 { return .green }
        if pct >= 0.5 { return .orange }
        return .secondary
    }
}

// MARK: - Occupancy row (used by all four tabs)

private struct OccupancyStatRow: View {
    let stat: OccupancyStat
    let maxHours: Double

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(stat.name)
                    .frame(width: 180, alignment: .leading)
                    .lineLimit(1)

                Text(String(format: "%.1f h", stat.bookedHours))
                    .frame(width: 70, alignment: .trailing)
                    .foregroundColor(.secondary)

                Group {
                    if stat.weekendHours > 0 {
                        Text(String(format: "%.1f h", stat.weekendHours))
                            .foregroundColor(.orange)
                    } else {
                        Text("–").foregroundColor(.secondary)
                    }
                }
                .frame(width: 72, alignment: .trailing)

                Text(String(format: "%.0f h", stat.availableHours))
                    .frame(width: 72, alignment: .trailing)
                    .foregroundColor(.secondary)

                HStack(spacing: 4) {
                    Text(String(format: "%.0f%%", stat.occupancy * 100))
                        .bold()
                        .foregroundColor(labelColor)
                    if stat.occupancy > 1.0 {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .frame(width: 90, alignment: .trailing)

                Text("\(stat.sessionCount)")
                    .frame(width: 65, alignment: .trailing)
                    .foregroundColor(.secondary)

                Spacer()
            }
            .font(.callout)

            // Progress bar — stacked weekday + weekend, red when over capacity
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 8)

                    if stat.occupancy <= 1.0 {
                        let totalFraction   = CGFloat(stat.occupancy)
                        let weekendFraction = CGFloat(stat.weekendHours / max(1, stat.availableHours))
                        let weekdayFraction = totalFraction - weekendFraction

                        // Full bar (weekday tint)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(barColor)
                            .frame(width: max(4, geo.size.width * totalFraction), height: 8)

                        // Weekend overlay in orange
                        if weekendFraction > 0 {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.orange.opacity(0.85))
                                .frame(width: max(4, geo.size.width * weekendFraction), height: 8)
                                .offset(x: max(0, geo.size.width * weekdayFraction))
                        }
                    } else {
                        // Over capacity — full red bar
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.red.opacity(0.75))
                            .frame(width: geo.size.width, height: 8)
                        Image(systemName: "chevron.right.2")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: geo.size.width, height: 8, alignment: .trailing)
                    }
                }
            }
            .frame(height: 8)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            stat.occupancy > 1.0
                ? Color.red.opacity(0.05)
                : Color.secondary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    private var barColor: Color {
        if stat.occupancy >= 0.8 { return .green }
        if stat.occupancy >= 0.5 { return .orange }
        return Color.accentColor.opacity(0.7)
    }

    private var labelColor: Color {
        if stat.occupancy > 1.0  { return .red }
        if stat.occupancy >= 0.8 { return .green }
        if stat.occupancy >= 0.5 { return .orange }
        return .primary
    }
}

// MARK: - Reusable sub-views

private struct StatKPI: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    var note: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.title2).bold()
                    .foregroundColor(color)
                if let note {
                    Text(note)
                        .font(.caption2)
                        .foregroundColor(color.opacity(0.8))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title3).bold()
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
