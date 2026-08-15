//
// TimelineDayView.swift
// Projector
//

import SwiftUI
import AppKit

// MARK: - Hour Grid

private struct HourGrid: View {
    let totalHours: Int
    let hourWidth: CGFloat
    let height: CGFloat
    var highlightedHour: Int? = nil
    var theme: DesignSystem.TimelineTheme = DesignSystem.TimelineTheme(lightMode: false)

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<totalHours, id: \.self) { hour in
                Rectangle()
                    .fill(fillColor(for: hour))
                    .frame(width: hourWidth, height: height)
                    .overlay(
                        Rectangle()
                            .fill(lineColor(for: hour))
                            .frame(width: lineWidth(for: hour)),
                        alignment: .trailing
                    )
            }
        }
    }

    private func lineColor(for hour: Int) -> Color {
        hour.isMultiple(of: 3) ? theme.gridLineMajor : theme.gridLine
    }
    private func lineWidth(for hour: Int) -> CGFloat {
        hour.isMultiple(of: 3) ? 1.0 : 0.5
    }
    private func fillColor(for hour: Int) -> Color {
        if let h = highlightedHour, h == hour { return theme.nowHourTint }
        return Color.clear
    }
}

// MARK: - Timeline Day View

struct TimelineDayView: View {
    let day: Date
    let sessions: [Session]
    let rooms: [String]
    let zoom: Double
    var lightMode: Bool = false
    var onSelect: (Session) -> Void
    var condensed: Bool = false
    var onPrevDay: () -> Void = {}
    var onNextDay: () -> Void = {}
    var onCreate: (_ room: String, _ start: Date, _ end: Date) -> Void = { _,_,_ in }

    /// Theme built from our own lightMode state — guaranteed to update when lightMode changes
    private var theme: DesignSystem.TimelineTheme { DesignSystem.TimelineTheme(lightMode: lightMode) }

    @EnvironmentObject private var projects: ProjectStore
    @ObservedObject private var store = SessionStore.shared
    @EnvironmentObject private var people: PeopleStore
    @EnvironmentObject private var filters: Filters

    private var dayStart: Date { Calendar.current.startOfDay(for: day) }
    private var dayEnd: Date { Calendar.current.date(byAdding: .day, value: 1, to: dayStart)! }

    private var hourWidth: CGFloat {
        let base: CGFloat = condensed ? 12.0 : 80.0
        return CGFloat((base * zoom).rounded())
    }
    private var totalHours: Int { 24 }
    private var contentWidth: CGFloat { CGFloat(totalHours) * hourWidth }
    private let snapMinutes: Double = 30
    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    private func xForTime(_ date: Date) -> CGFloat {
        let clamped = min(max(date, dayStart), dayEnd)
        let secs = clamped.timeIntervalSince(dayStart)
        return CGFloat(secs / 3600.0) * hourWidth
    }

    private static let headerFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = .current; df.locale = .current
        df.setLocalizedDateFormatFromTemplate("EEEE, d MMMM yyyy")
        return df
    }()

    var body: some View { content }

    /// Returns the appropriate overlay tint for this day.
    /// Priority: today+holiday > today > holiday > weekend > nil
    private var dayTint: Color? {
        let cal = Calendar.current
        if cal.isPublicHoliday(day) { return theme.holidayTint }
        if cal.isDateInWeekend(day) { return theme.weekendTint }
        return nil
    }
    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !condensed { headerView }
            scrollArea
        }
        .background(theme.background)
        .overlay {
            if let tint = dayTint { tint.allowsHitTesting(false) }
        }
    }

    private var headerView: some View {
        HStack {
            Button(action: { withAnimation { onPrevDay() } }) { Image(systemName: "chevron.left") }
                .buttonStyle(.plain)
            Text(Self.headerFormatter.string(from: day))
                .font(.title3).bold()
                .frame(maxWidth: .infinity, alignment: .center)
            Button(action: { withAnimation { onNextDay() } }) { Image(systemName: "chevron.right") }
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.top, 6)
    }

    private var scrollArea: some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(spacing: 0) {
                if !condensed { hourHeader }
                roomRows
            }
            .padding(.bottom, 8)
            .overlay(alignment: .topLeading) {
                if !condensed && isToday {
                    GeometryReader { geo in
                        let nowX = xForTime(Date())
                        ZStack(alignment: .top) {
                            // 2px line
                            Rectangle()
                                .fill(theme.nowLine)
                                .frame(width: 2, height: geo.size.height)
                            // dot at top
                            Circle()
                                .fill(theme.nowLine)
                                .frame(width: 8, height: 8)
                                .offset(x: -3)
                        }
                        .position(x: nowX, y: geo.size.height / 2)
                        .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    private var hourHeader: some View {
        ZStack(alignment: .topLeading) {
            theme.hourHeaderBackground
            HourGrid(
                totalHours: totalHours, hourWidth: hourWidth, height: 28,
                highlightedHour: (!condensed && isToday) ? Calendar.current.component(.hour, from: Date()) : nil,
                theme: theme
            )
            HStack(spacing: 0) {
                ForEach(0..<totalHours, id: \.self) { h in
                    Text(String(format: "%02d:00", h))
                        .font(.system(size: 11).monospacedDigit())
                        .frame(width: hourWidth, alignment: .leading)
                        .foregroundColor(theme.hourLabel)
                }
            }
        }
        .frame(width: contentWidth)
        .overlay(alignment: .bottomLeading) {
            Rectangle().fill(theme.hourHeaderSeparator).frame(height: 1)
        }
    }

    private var roomRows: some View {
        VStack(spacing: 0) {
            ForEach(rooms, id: \.self) { room in
                TimelineRoomRow(
                    room: room,
                    dayStart: dayStart,
                    dayEnd: dayEnd,
                    hourWidth: hourWidth,
                    contentWidth: contentWidth,
                    sessions: sessions.filter { $0.room == room },
                    colorForSession: { s in color(forProjectID: s.projectID) },
                    snapMinutes: snapMinutes,
                    theme: theme,
                    onSelect: onSelect,
                    peopleNames: { ids in self.peopleNames(for: ids) },
                    projectName: { id, client in self.projectTitle(id, fallbackClient: client) },
                    onCreate: onCreate
                )
            }

            ServicesTimelineRow(day: day, totalHours: totalHours, hourWidth: hourWidth, contentWidth: contentWidth, theme: theme)
            VacationsTimelineRow(day: day, totalHours: totalHours, hourWidth: hourWidth, contentWidth: contentWidth, theme: theme)
        }
    }

    private func color(forProjectID id: UUID?) -> Color {
        guard let id else { return Color.gray.opacity(0.35) }
        let hex = id.uuidString.replacingOccurrences(of: "-", with: "")
        let prefix = String(hex.prefix(6))
        let value = Int(prefix, radix: 16) ?? 0
        return Color(hue: Double(value % 360) / 360.0, saturation: 0.55, brightness: 0.85)
    }

    private func projectTitle(_ id: UUID?, fallbackClient: String) -> String {
        guard let id, let p = projects.projects.first(where: { $0.id == id }) else { return fallbackClient }
        return p.isActive ? p.name : "\(p.name) (Completed)"
    }

    private func peopleNames(for ids: [UUID]) -> String {
        let map = Dictionary(uniqueKeysWithValues: people.people.map { ($0.id, $0.name) })
        let names = ids.compactMap { map[$0] }
        if names.isEmpty { return "–" }
        let joined = names.joined(separator: ", ")
        if joined.count <= 28 { return joined }
        return names.map { name in
            name.split(separator: " ").prefix(3).compactMap { $0.first }.map(String.init).joined().uppercased()
        }.joined(separator: ", ")
    }
}

// MARK: - Recurrence helpers

private enum RecurrenceEndMode: Hashable { case byDate, byCount }

private enum RecurrencePattern {
    case daily(every: Int)
    case weekly(every: Int, weekdays: Set<Int>)
}

private struct RecurrenceConfig: Identifiable {
    let id = UUID()
    let baseSession: Session
    let pattern: RecurrencePattern
}

// MARK: - Timeline Room Row

struct TimelineRoomRow: View {
    let room: String
    let dayStart: Date
    let dayEnd: Date
    let hourWidth: CGFloat
    let contentWidth: CGFloat
    let sessions: [Session]
    let colorForSession: (Session) -> Color
    let snapMinutes: Double
    var theme: DesignSystem.TimelineTheme = DesignSystem.TimelineTheme(lightMode: false)

    var onSelect: (Session) -> Void
    var peopleNames: ([UUID]) -> String
    var projectName: (UUID?, String) -> String
    var onCreate: (_ room: String, _ start: Date, _ end: Date) -> Void

    @ObservedObject private var store = SessionStore.shared

    @State private var activeID: UUID? = nil
    @State private var mode: Mode? = nil
    @State private var dx: CGFloat = 0
    @State private var lastClickX: CGFloat? = nil
    @State private var dragStartX: CGFloat? = nil
    @State private var dragEndX: CGFloat? = nil
    @State private var previewRect: CGRect? = nil
    @State private var recurrenceConfig: RecurrenceConfig? = nil

    private enum Mode { case move, resize }
    private var snapSeconds: TimeInterval { snapMinutes * 60 }
    private let handleGrabWidth: CGFloat = 22
    private var rowHeight: CGFloat { DesignSystem.Layout.timelineRowHeight }
    private var barHeight: CGFloat { DesignSystem.Layout.timelineBarHeight }

    private func x(for date: Date) -> CGFloat {
        let clamped = min(max(date, dayStart), dayEnd)
        return CGFloat(clamped.timeIntervalSince(dayStart) / 3600.0) * hourWidth
    }
    private func width(from start: Date, to end: Date) -> CGFloat { max(6, x(for: end) - x(for: start)) }
    private func snapped(_ t: TimeInterval) -> TimeInterval { (t / snapSeconds).rounded() * snapSeconds }
    private func dateForX(_ x: CGFloat) -> Date {
        let seconds = TimeInterval(x / hourWidth) * 3600.0
        let t = dayStart.addingTimeInterval(seconds).timeIntervalSinceReferenceDate
        return min(max(Date(timeIntervalSinceReferenceDate: snapped(t)), dayStart), dayEnd)
    }

    private func onDragChanged(for s: Session, startX: CGFloat, baseWidth: CGFloat, value: DragGesture.Value) {
        if activeID == nil {
            activeID = s.id
            let barLeft = startX - baseWidth / 2
            let localXAtStart = value.startLocation.x - barLeft
            mode = (localXAtStart >= baseWidth - handleGrabWidth) ? .resize : .move
        }
        guard activeID == s.id, mode != nil else { return }
        dx = value.translation.width
    }

    private func onDragEnded(for s: Session, occStart: Date, baseWidth: CGFloat, value: DragGesture.Value) {
        defer { activeID = nil; mode = nil; dx = 0 }
        guard let m = mode, activeID == s.id else { return }
        let secondsDelta = Double(value.translation.width / hourWidth) * 3600.0
        switch m {
        case .move:
            let proposed = s.start.addingTimeInterval(secondsDelta)
            var newSession = s
            newSession.start = Date(timeIntervalSinceReferenceDate: snapped(proposed.timeIntervalSinceReferenceDate))
            if SessionStore.shared.canSchedule(newSession, ignoring: s.id) { try? SessionStore.shared.update(newSession) } else { NSSound.beep() }
        case .resize:
            let proposedEnd = s.end.addingTimeInterval(secondsDelta)
            let snappedEnd = Date(timeIntervalSinceReferenceDate: snapped(proposedEnd.timeIntervalSinceReferenceDate))
            var newSession = s
            newSession.durationMinutes = max(30, Int(max(snappedEnd, s.start.addingTimeInterval(30*60)).timeIntervalSince(s.start) / 60))
            if SessionStore.shared.canSchedule(newSession, ignoring: s.id) { try? SessionStore.shared.update(newSession) } else { NSSound.beep() }
        }
    }

    @ViewBuilder
    private func sessionBar(_ s: Session, liveWidth: CGFloat, posX: CGFloat, isActive: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(theme.sessionBarFill(colorForSession(s), isActive: isActive))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(theme.sessionBarStroke(colorForSession(s), isActive: isActive), lineWidth: isActive ? 1.5 : 1))
            .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
            .overlay(barLabel(s), alignment: .leading)
            .overlay(alignment: .topTrailing) {
                if !s.confirmed {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                        .padding(5)
                }
            }
            .frame(width: liveWidth, height: barHeight)
            .position(x: posX, y: rowHeight * 0.62)
            .onTapGesture { onSelect(s) }
            .help("\(s.title) (\(s.client))\n\(s.start.formatted(date: .omitted, time: .shortened))–\(s.end.formatted(date: .omitted, time: .shortened))")
            .overlay(alignment: .trailing) { resizeHandle() }
    }

    @ViewBuilder
    private func barLabel(_ s: Session) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Title row — colour dot + session name
            HStack(spacing: 5) {
                Circle()
                    .fill(colorForSession(s))
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(theme.sessionBarResizeHandle, lineWidth: 0.5))
                Text(s.title)
                    .font(DesignSystem.Fonts.sessionTitle)
                    .lineLimit(1)
                    .foregroundColor(theme.sessionBarTitle(colorForSession(s)))
            }
            // Project name — most important secondary info
            let proj = projectName(s.projectID, s.client)
            if !proj.isEmpty {
                Text(proj)
                    .font(DesignSystem.Fonts.sessionSubtitle)
                    .lineLimit(1)
                    .foregroundColor(theme.sessionBarSubtitle)
            }
            // People — quietest
            let ppl = peopleNames(s.peopleIDs)
            if !ppl.isEmpty {
                Text(ppl)
                    .font(.system(size: 11, weight: .regular))
                    .lineLimit(1)
                    .foregroundColor(theme.sessionBarMeta)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
    }

    @ViewBuilder
    private func recurrenceMenu(for s: Session) -> some View {
        if s.seriesID == nil {
            Button("Repeat: Weekdays (Mon–Fri)…") {
                recurrenceConfig = RecurrenceConfig(baseSession: s, pattern: .weekly(every: 1, weekdays: [2,3,4,5,6]))
            }
            Divider()
            Button("Repeat: Daily (every 1 day)…") {
                recurrenceConfig = RecurrenceConfig(baseSession: s, pattern: .daily(every: 1))
            }
            Button("Repeat: Daily (every 2 days)…") {
                recurrenceConfig = RecurrenceConfig(baseSession: s, pattern: .daily(every: 2))
            }
        }
    }

    @ViewBuilder
    private func resizeHandle() -> some View {
        Capsule().fill(Color.white.opacity(0.35)).frame(width: 3, height: 32).padding(.trailing, 3)
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
    }

    private func makeDragGesture(s: Session, startX: CGFloat, baseWidth: CGFloat, occStart: Date) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in onDragChanged(for: s, startX: startX, baseWidth: baseWidth, value: value) }
            .onEnded   { value in onDragEnded(for: s, occStart: occStart, baseWidth: baseWidth, value: value) }
    }

    private func sameMinute(_ a: Date, _ b: Date) -> Bool {
        Calendar.current.compare(a, to: b, toGranularity: .minute) == .orderedSame
    }

    private func deleteRepeatBatch(seriesID: UUID) {
        let toDelete = store.sessions.filter { $0.seriesID == seriesID }
        guard !toDelete.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Delete repeated sessions?"
        alert.informativeText = "This will delete \(toDelete.count) sessions created by this repeat action."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() != .alertFirstButtonReturn { return }
        for s in toDelete { store.delete(s) }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HourGrid(totalHours: 24, hourWidth: hourWidth, height: rowHeight, theme: theme).frame(width: contentWidth, height: rowHeight)

            Text(room)
                .font(.callout.weight(.semibold))
                .foregroundColor(theme.roomLabel)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(theme.roomLabelBackground)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.roomLabelBorder, lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.leading, 6).padding(.top, 4)

            let visibleWindow = DateInterval(start: dayStart, end: dayEnd)
            let occs = store.sessions
                .filter { s in s.room == room && s.end > visibleWindow.start && s.start < visibleWindow.end }
                .sorted { $0.start < $1.start }

            ForEach(occs) { s in
                let startX = x(for: s.start)
                let baseWidth = width(from: s.start, to: s.end)
                let isActive = (activeID == s.id)
                let thisMode = isActive ? mode : nil

                let liveWidth: CGFloat = {
                    guard isActive, thisMode == .resize else { return baseWidth }
                    return max(baseWidth + dx, hourWidth * 0.5)
                }()
                let posX: CGFloat = {
                    let base = startX + (thisMode == .resize ? liveWidth : baseWidth) / 2
                    return base + (thisMode == .move ? dx : 0)
                }()

                sessionBar(s, liveWidth: liveWidth, posX: posX, isActive: isActive)
                    .gesture(makeDragGesture(s: s, startX: startX, baseWidth: baseWidth, occStart: s.start))
                    .contextMenu {
                        recurrenceMenu(for: s)
                        if let sid = s.seriesID {
                            Divider()
                            Button("Delete this repeat batch…") { deleteRepeatBatch(seriesID: sid) }
                        }
                    }
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    lastClickX = v.location.x
                    if dragStartX == nil { dragStartX = v.location.x; dragEndX = v.location.x }
                    else { dragEndX = v.location.x }
                    if let startX = dragStartX {
                        let endX = dragEndX ?? v.location.x
                        let x1 = min(startX, endX); let x2 = max(startX, endX)
                        previewRect = CGRect(x: x1, y: 0, width: max(0, x2 - x1), height: rowHeight)
                    }
                }
                .onEnded { v in
                    defer { dragStartX = nil; dragEndX = nil; previewRect = nil }
                    guard let startX = dragStartX else { return }
                    let endX = dragEndX ?? v.location.x
                    guard abs(endX - startX) > 10 else { return }
                    let startDate = dateForX(min(startX, endX))
                    let endDate = dateForX(max(startX, endX))
                    if endDate > startDate { onCreate(room, startDate, endDate) }
                }
        )
        .highPriorityGesture(
            TapGesture(count: 2).onEnded {
                guard let x = lastClickX else { return }
                let start = dateForX(x)
                let end = min(start.addingTimeInterval(2 * 3600), dayEnd)
                onCreate(room, start, end)
            }
        )
        .frame(width: contentWidth, height: rowHeight)
        .overlay(alignment: .topLeading) {
            if let rect = previewRect {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.18))
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            }
        }
        .overlay(Rectangle().fill(theme.rowSeparator).frame(height: 1), alignment: .bottom)
        .sheet(item: $recurrenceConfig) { config in
            RecurrenceOptionsSheet(config: config).environmentObject(store)
        }
    }

    // MARK: - Recurrence Options Sheet

    private struct RecurrenceOptionsSheet: View {
        @ObservedObject private var store = SessionStore.shared
        @Environment(\.dismiss) private var dismiss
        let config: RecurrenceConfig
        @State private var mode: RecurrenceEndMode = .byDate
        @State private var endDate: Date
        @State private var occurrenceCount: Int = 10

        init(config: RecurrenceConfig) {
            self.config = config
            _endDate = State(initialValue: Calendar.current.date(byAdding: .month, value: 1, to: config.baseSession.start) ?? config.baseSession.start)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("Repeat Session").font(.headline)
                Text(summaryText).font(.subheadline).foregroundColor(.secondary)

                Picker("End", selection: $mode) {
                    Text("On date").tag(RecurrenceEndMode.byDate)
                    Text("After N occurrences").tag(RecurrenceEndMode.byCount)
                }
                .pickerStyle(.segmented)

                if mode == .byDate {
                    DatePicker("End date", selection: $endDate, displayedComponents: .date).datePickerStyle(.field)
                } else {
                    Stepper(value: $occurrenceCount, in: 1...365) { Text("Occurrences: \(occurrenceCount)") }
                }

                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                    Button("OK") { applyRecurrence() }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(20).frame(minWidth: 340)
        }

        private var summaryText: String {
            switch config.pattern {
            case .daily(let every):
                return every == 1
                    ? "Daily, starting \(formattedDate(config.baseSession.start))."
                    : "Every \(every) days, starting \(formattedDate(config.baseSession.start))."
            case .weekly(let every, let weekdays):
                let symbols = Calendar.current.shortWeekdaySymbols
                let names = weekdays.sorted().map { symbols[$0 - 1] }.joined(separator: ", ")
                return every == 1
                    ? "Weekly on \(names), starting \(formattedDate(config.baseSession.start))."
                    : "Every \(every) weeks on \(names), starting \(formattedDate(config.baseSession.start))."
            }
        }

        private func formattedDate(_ d: Date) -> String {
            let f = DateFormatter(); f.dateStyle = .medium; return f.string(from: d)
        }

        private func applyRecurrence() {
            let until: Date? = (mode == .byDate) ? endDate : endDateFromOccurrences()
            guard let untilDate = until else { dismiss(); return }

            var temp = config.baseSession
            switch config.pattern {
            case .daily(let every):  temp.recurrence = .daily(every: every, until: untilDate)
            case .weekly(let every, let weekdays): temp.recurrence = .weekly(every: every, weekdays: weekdays, until: untilDate)
            }

            let windowEnd = untilDate.addingTimeInterval(36 * 3600)
            let window = DateInterval(start: config.baseSession.start, end: windowEnd)
            let intervals = temp.occurrences(in: window, calendar: .current)

            let cal = Calendar.current
            let baseStart = config.baseSession.start
            let occurrenceStarts: [Date] = intervals
                .map { $0.start }
                .filter { cal.compare($0, to: baseStart, toGranularity: .minute) != .orderedSame }
                .sorted()

            if config.baseSession.recurrence != .none {
                var cleared = config.baseSession; cleared.recurrence = .none
                try? store.update(cleared)
            }

            var created = 0; var skipped = 0
            let batchID = UUID()
            for start in occurrenceStarts {
                var newSession = config.baseSession
                newSession.id = UUID(); newSession.start = start
                newSession.recurrence = .none; newSession.seriesID = batchID; newSession.exceptions = []
                if store.canSchedule(newSession) { try? store.add(newSession); created += 1 }
                else { skipped += 1 }
            }

            if skipped > 0 { NSSound.beep(); print("⚠️ Repeat created \(created) sessions, skipped \(skipped) due to overlap.") }
            else { print("✅ Repeat created \(created) sessions.") }
            dismiss()
        }

        private func endDateFromOccurrences() -> Date? {
            guard occurrenceCount > 0 else { return nil }
            let start = config.baseSession.start; let cal = Calendar.current
            switch config.pattern {
            case .daily(let every):
                return cal.date(byAdding: .day, value: every * (occurrenceCount - 1), to: start)
            case .weekly(_, let weekdays):
                var count = 0; var date = start
                while count < occurrenceCount {
                    date = cal.date(byAdding: .day, value: 1, to: date)!
                    if weekdays.contains(cal.component(.weekday, from: date)) { count += 1 }
                }
                return date
            }
        }
    }
}

// MARK: - Services Timeline Row

struct ServicesTimelineRow: View {
    let day: Date
    let totalHours: Int
    let hourWidth: CGFloat
    let contentWidth: CGFloat
    var theme: DesignSystem.TimelineTheme = DesignSystem.TimelineTheme(lightMode: false)

    @ObservedObject private var serviceStore = ServiceStore.shared
    @EnvironmentObject private var projectStore: ProjectStore
    @State private var showQuickCreate: Bool = false

    private var bookingsForDay: [ServiceBooking] {
        serviceStore.bookings.filter { $0.date.isSameDay(as: day) }.sorted { $0.date < $1.date }
    }

    private func label(for booking: ServiceBooking) -> String {
        let serviceName = serviceStore.services.first(where: { $0.id == booking.serviceId })?.name ?? "Service"
        if let pid = booking.projectId, let p = projectStore.projects.first(where: { $0.id == pid }) {
            return "\(serviceName) – \(p.name)"
        }
        return serviceName
    }

    private func chipBackground(for booking: ServiceBooking) -> Color {
        switch booking.status {
        case .completed: return .green
        case .canceled:  return Color.gray.opacity(0.35)
        case .scheduled: return DesignSystem.Colors.servicesChip
        }
    }

    private func chipTextColor(for booking: ServiceBooking) -> Color {
        booking.status == .completed ? .white : .primary
    }

    private var servicesById: [UUID: ServiceCatalogItem] {
        Dictionary(uniqueKeysWithValues: serviceStore.services.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }.map { svc in
            (svc.id, ServiceCatalogItem(id: svc.id, name: svc.name, category: svc.category ?? "Uncategorized",
                                        unitPrice: svc.unitPriceEUR, taxable: true, variableUnitName: svc.variableUnitName))
        })
    }

    private var projectsById: [UUID: ProjectSummary] {
        Dictionary(uniqueKeysWithValues: projectStore.projects.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }.map { p in (p.id, ProjectSummary(id: p.id, name: p.name)) })
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HourGrid(totalHours: totalHours, hourWidth: hourWidth, height: DesignSystem.Layout.slimLaneHeight, theme: theme)

            VStack(alignment: .leading, spacing: 4) {
                Text("Services").font(DesignSystem.Fonts.sectionHeader).foregroundColor(theme.laneTitle)

                if bookingsForDay.isEmpty {
                    Text("No services booked").font(DesignSystem.Fonts.meta).foregroundColor(theme.laneEmpty)
                } else {
                    HStack(spacing: 10) {
                        ForEach(bookingsForDay) { booking in
                            RoundedRectangle(cornerRadius: 8)
                                .fill(chipBackground(for: booking).opacity(0.85))
                                .shadow(color: .black.opacity(DesignSystem.Shadows.sessionShadow.opacity),
                                        radius: DesignSystem.Shadows.sessionShadow.radius,
                                        x: DesignSystem.Shadows.sessionShadow.x, y: DesignSystem.Shadows.sessionShadow.y)
                                .overlay(alignment: .leading) {
                                    Text(label(for: booking))
                                        .font(DesignSystem.Fonts.sessionTitle)
                                        .foregroundColor(chipTextColor(for: booking) == .primary ? .white : chipTextColor(for: booking))
                                        .lineLimit(1).padding(.horizontal, 10)
                                }
                                .frame(height: 34)
                                .contextMenu {
                                    if booking.status != .scheduled { Button("Mark as scheduled") { serviceStore.setStatus(booking.id, .scheduled) } }
                                    if booking.status != .completed { Button("Mark as completed") { serviceStore.setStatus(booking.id, .completed) } }
                                    if booking.status != .canceled  { Button("Mark as canceled")  { serviceStore.setStatus(booking.id, .canceled)  } }
                                    Divider()
                                    Button("Delete booking", role: .destructive) { serviceStore.deleteBookings(Set([booking.id])) }
                                }
                                .help("Click to toggle executed")
                        }
                    }
                    .padding(.leading, hourWidth * 2).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
        }
        .frame(width: contentWidth, height: DesignSystem.Layout.slimLaneHeight, alignment: .leading)
        .overlay(alignment: .bottomLeading) { Rectangle().fill(Color.white.opacity(0.2)).frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { showQuickCreate = true }
        .sheet(isPresented: $showQuickCreate) {
            ServiceQuickCreateSheet(store: serviceStore, initialDate: day, projects: projectsById) { date, serviceId, projectId, quantity, variableQuantity, note in
                serviceStore.createBookings(serviceId: serviceId, projectId: projectId, date: date,
                                            quantity: quantity, variableQuantity: variableQuantity, note: note)
            }
        }
    }
}

// MARK: - Vacations Timeline Row

struct VacationsTimelineRow: View {
    let day: Date
    let totalHours: Int
    let hourWidth: CGFloat
    let contentWidth: CGFloat
    var theme: DesignSystem.TimelineTheme = DesignSystem.TimelineTheme(lightMode: false)

    @ObservedObject private var vacationStore = VacationsStore.shared
    @EnvironmentObject private var people: PeopleStore
    @State private var showQuickCreate = false

    private var peopleById: [UUID: Person] {
        Dictionary(uniqueKeysWithValues: people.people.map { ($0.id, $0) })
    }

    private var vacationsForDay: [VacationEntry] {
        let cal = Calendar.current
        return vacationStore.vacations.filter { cal.isDate($0.date, inSameDayAs: day) }
    }

    private func label(for entry: VacationEntry) -> String {
        let personName = people.people.first(where: { $0.id == entry.personId })?.name ?? "Unknown person"
        let statusLabel: String = {
            switch entry.status {
            case .planned:  return "planned"
            case .approved: return "approved"
            case .canceled: return "canceled"
            }
        }()
        return "\(personName) – \(statusLabel)"
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HourGrid(totalHours: totalHours, hourWidth: hourWidth, height: DesignSystem.Layout.slimLaneHeight, theme: theme)

            VStack(alignment: .leading, spacing: 4) {
                Text("Vacations").font(DesignSystem.Fonts.sectionHeader).foregroundColor(theme.laneTitle)

                if vacationsForDay.isEmpty {
                    Text("No vacations").font(DesignSystem.Fonts.meta).foregroundColor(theme.laneEmpty)
                } else {
                    HStack(spacing: 10) {
                        ForEach(vacationsForDay) { entry in
                            RoundedRectangle(cornerRadius: 8)
                                .fill(DesignSystem.Colors.vacationsChip.opacity(0.9))
                                .shadow(color: .black.opacity(DesignSystem.Shadows.sessionShadow.opacity),
                                        radius: DesignSystem.Shadows.sessionShadow.radius,
                                        x: DesignSystem.Shadows.sessionShadow.x, y: DesignSystem.Shadows.sessionShadow.y)
                                .overlay(alignment: .leading) {
                                    Text(label(for: entry))
                                        .font(DesignSystem.Fonts.sessionTitle).foregroundColor(.white)
                                        .lineLimit(1).padding(.horizontal, 10)
                                }
                                .frame(height: 34)
                                .contextMenu {
                                    if entry.status != .planned  { Button("Mark as planned")  { VacationsStore.shared.setStatus(entry.id, .planned) } }
                                    if entry.status != .approved { Button("Mark as approved") { VacationsStore.shared.setStatus(entry.id, .approved) } }
                                    if entry.status != .canceled { Button("Mark as canceled") { VacationsStore.shared.setStatus(entry.id, .canceled) } }
                                    Divider()
                                    Button("Delete vacation", role: .destructive) { VacationsStore.shared.delete(Set([entry.id])) }
                                }
                        }
                    }
                    .padding(.leading, hourWidth * 2).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
        }
        .frame(width: contentWidth, height: DesignSystem.Layout.slimLaneHeight, alignment: .leading)
        .overlay(alignment: .bottomLeading) { Rectangle().fill(Color.white.opacity(0.38)).frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { showQuickCreate = true }
        .sheet(isPresented: $showQuickCreate) {
            VacationQuickCreateSheet(initialDate: day, peopleById: peopleById) { start, end, personIds, status in
                VacationsStore.shared.add(personIds: personIds, startDate: start, endDate: end, status: status)
            }
        }
    }
}
