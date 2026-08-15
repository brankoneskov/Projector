//
//  DesignSystem.swift
//  Projector
//
//  Created by Branko Neskov on 15/11/2025.
//
import SwiftUI

/// Central place for all visual styling in Projector.
/// Colors, fonts, spacing, shadows, etc.
enum DesignSystem {

    // MARK: - Timeline Theme

    /// A value-type theme object built from the view's own lightMode state.
    /// Pass TimelineDayView's lightMode property to ensure SwiftUI observes changes correctly.
    struct TimelineTheme {
        let lightMode: Bool

        var background: Color {
            lightMode
                ? Color(red: 0.92, green: 0.93, blue: 0.94)
                : Color(red: 0.078, green: 0.094, blue: 0.141)
        }
        var nowHourTint: Color {
            lightMode
                ? Color(red: 0.23, green: 0.51, blue: 0.95).opacity(0.10)
                : Color(red: 0.20, green: 0.36, blue: 0.60).opacity(0.18)
        }
        var nowLine: Color {
            lightMode
                ? Color(red: 0.15, green: 0.39, blue: 0.92).opacity(0.75)
                : Color(red: 0.38, green: 0.64, blue: 0.98).opacity(0.75)
        }
        var weekendTint: Color {
            lightMode
                ? Color(red: 0.85, green: 0.86, blue: 0.89).opacity(0.45)
                : Color(red: 0.04, green: 0.05, blue: 0.09).opacity(0.55)
        }
        var holidayTint: Color {
            lightMode
                ? Color(red: 0.99, green: 0.93, blue: 0.80).opacity(0.60)
                : Color(red: 0.55, green: 0.38, blue: 0.04).opacity(0.28)
        }
        var roomLabel: Color {
            lightMode ? Color(red: 0.22, green: 0.25, blue: 0.32) : Color.white.opacity(0.75)
        }
        var roomLabelBackground: Color {
            lightMode ? Color.white : Color.white.opacity(0.10)
        }
        var roomLabelBorder: Color {
            lightMode ? Color(red: 0.80, green: 0.82, blue: 0.87) : Color.white.opacity(0.15)
        }
        var hourHeaderBackground: Color {
            lightMode ? Color(red: 0.94, green: 0.95, blue: 0.96) : Color.clear
        }
        var hourLabel: Color {
            lightMode ? Color(red: 0.60, green: 0.63, blue: 0.70) : Color.white.opacity(0.55)
        }
        var gridLine: Color {
            lightMode ? Color(red: 0.76, green: 0.78, blue: 0.82) : Color.white.opacity(0.14)
        }
        var gridLineMajor: Color {
            lightMode ? Color(red: 0.70, green: 0.72, blue: 0.78) : Color.white.opacity(0.20)
        }
        var rowSeparator: Color {
            lightMode ? Color(red: 0.88, green: 0.90, blue: 0.94) : Color.white.opacity(0.06)
        }
        var hourHeaderSeparator: Color {
            lightMode ? Color(red: 0.80, green: 0.82, blue: 0.87) : Color.white.opacity(0.50)
        }
        var laneTitle: Color {
            lightMode ? Color(red: 0.60, green: 0.63, blue: 0.70) : Color.white.opacity(0.70)
        }
        var laneEmpty: Color {
            lightMode ? Color(red: 0.72, green: 0.74, blue: 0.78) : Color.white.opacity(0.45)
        }
        var sessionBarResizeHandle: Color {
            lightMode ? Color.black.opacity(0.15) : Color.white.opacity(0.28)
        }
        var sessionBarSubtitle: Color {
            lightMode
                ? Color(red: 0.35, green: 0.38, blue: 0.46).opacity(0.85)
                : Color.white.opacity(0.62)
        }
        var sessionBarMeta: Color {
            lightMode ? Color(red: 0.55, green: 0.58, blue: 0.65) : Color.white.opacity(0.40)
        }
        func sessionBarFill(_ color: Color, isActive: Bool) -> Color {
            lightMode
                ? color.opacity(isActive ? 0.18 : 0.13)
                : color.opacity(isActive ? 0.65 : 0.22)
        }
        func sessionBarStroke(_ color: Color, isActive: Bool) -> Color {
            lightMode
                ? color.opacity(isActive ? 0.80 : 0.55)
                : color.opacity(isActive ? 0.95 : 0.65)
        }
        func sessionBarTitle(_ color: Color) -> Color {
            lightMode ? color.opacity(0.90) : Color.white
        }
    }

    // MARK: - Colors (non-timeline)

    enum Colors {
        static var appBackground: Color { Color(nsColor: .windowBackgroundColor) }
        static var cardBackground: Color { Color(nsColor: .controlBackgroundColor) }
        static var gridLine: Color     { Color.secondary.opacity(0.18) }
        static var separator: Color    { Color.secondary.opacity(0.25) }
        static var chipBackground: Color { Color.secondary.opacity(0.08) }
        static var quietText: Color    { Color.secondary }
        static var accentText: Color   { Color.accentColor }

        static let servicesLaneBackground  = Color.yellow.opacity(0.08)
        static let servicesChip            = Color.yellow.opacity(0.38)
        static let vacationsLaneBackground = Color.green.opacity(0.08)
        static let vacationsChip           = Color.green.opacity(0.28)
        static let servicesBackground      = Color.yellow.opacity(0.10)
        static let vacationsBackground     = Color.green.opacity(0.10)
    }

    // MARK: - Layout & Radii

    enum Layout {
        static let cardCornerRadius: CGFloat    = 12
        static let chipCornerRadius: CGFloat    = 8
        static let sectionSpacing: CGFloat      = 16
        static let horizontalPadding: CGFloat   = 12
        static let verticalPadding: CGFloat     = 8

        /// Height for a timeline room row — increased from 64 for breathing room
        static let timelineRowHeight: CGFloat   = 76

        /// Height for a session block inside a timeline room row
        static let timelineBarHeight: CGFloat   = 52

        /// Height for slim lanes (Services, Vacations)
        static let slimLaneHeight: CGFloat      = 60
    }

    // MARK: - Fonts

    enum Fonts {
        static var appTitle: Font     { .system(size: 28, weight: .bold, design: .default) }
        static var appSubtitle: Font  { .system(size: 14, weight: .regular, design: .default) }
        static var sectionHeader: Font { .system(size: 13, weight: .semibold, design: .default) }
        static var sessionTitle: Font  { .system(size: 13, weight: .semibold, design: .default) }
        static var sessionSubtitle: Font { .system(size: 12, weight: .medium, design: .default) }
        static var meta: Font          { .system(size: 9, weight: .regular, design: .default) }
    }

    // MARK: - Shadows

    enum Shadows {
        static var cardShadow: ShadowStyle    { ShadowStyle(radius: 6, x: 0, y: 2, opacity: 0.12) }
        static var sessionShadow: ShadowStyle { ShadowStyle(radius: 3, x: 0, y: 1, opacity: 0.18) }
    }

    struct ShadowStyle {
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
        let opacity: Double

        func apply(to color: Color = .black) -> some View {
            color.shadow(color: color.opacity(opacity), radius: radius, x: x, y: y)
        }
    }

    // MARK: - Room Color Palette

    private static let roomBaseColors: [Color] = [
        Color(red: 0.20, green: 0.50, blue: 0.94),
        Color(red: 0.25, green: 0.75, blue: 0.55),
        Color(red: 0.55, green: 0.34, blue: 0.90),
        Color(red: 1.00, green: 0.42, blue: 0.21),
        Color(red: 0.25, green: 0.72, blue: 0.34),
        Color(red: 0.94, green: 0.39, blue: 0.58),
        Color(red: 1.00, green: 0.77, blue: 0.10),
        Color(red: 0.05, green: 0.79, blue: 0.60),
    ]

    static func color(forRoomName name: String) -> Color {
        guard !roomBaseColors.isEmpty else { return .accentColor }
        let scalars = name.unicodeScalars.map { Int($0.value) }
        let hash = scalars.reduce(0) { partial, value in (partial &* 31) &+ value }
        let index = abs(hash) % roomBaseColors.count
        return roomBaseColors[index].opacity(0.80)
    }
}

struct DS {
    struct Lane {
        static let servicesBackground  = Color.yellow.opacity(0.10)
        static let vacationsBackground = Color.green.opacity(0.10)
        static let chipServices        = Color.yellow.opacity(0.30)
        static let chipVacations       = Color.green.opacity(0.30)
    }
}
