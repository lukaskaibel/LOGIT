//
//  ChartRange.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 04.07.26.
//

import Foundation

/// The rolling range shared by the capability charts — the exercise Weight / e1RM / Repetitions /
/// Set Volume screens and the measurement detail chart. Capability metrics track what the body can
/// do *right now*, so their windows roll ("the last 3 months") instead of snapping to calendar
/// periods the way the effort stats' `StatPeriod` does — strength doesn't reset on Monday.
/// One enum, one segmented control (`RangePicker`), so "3M" means the same window on every chart.
enum ChartRange: String, CaseIterable, Identifiable {
    case threeMonths, year, allTime

    var id: String { rawValue }

    /// Localized segment title ("3M" / "1Y" / "All").
    var title: String {
        switch self {
        case .threeMonths: return NSLocalizedString("rangeThreeMonths", comment: "")
        case .year: return NSLocalizedString("rangeYear", comment: "")
        case .allTime: return NSLocalizedString("rangeAllTime", comment: "")
        }
    }
}

// MARK: - Chart geometry

/// The scrollable-chart math every capability chart shares: full domain, visible window, scroll
/// anchoring and axis labeling, all derived from the selected range and the first data point.
/// Living here (not per screen) is what guarantees "3M" scrolls, snaps and labels identically
/// on every chart that offers it.
extension ChartRange {
    /// The chart's full scrollable domain: back to the first data point (snapped to the start of
    /// its month or year so the left edge lands on a boundary), but never shorter than one visible
    /// window so young histories still fill the chart. `.allTime` shows this domain in full.
    func xDomain(firstDataDate: Date?, now: Date = .now) -> ClosedRange<Date> {
        let minStart: Date
        switch self {
        case .threeMonths, .allTime:
            minStart = Calendar.current.date(byAdding: .month, value: -3, to: now) ?? now
        case .year:
            minStart = Calendar.current.date(byAdding: .year, value: -1, to: now) ?? now
        }
        guard let firstDataDate, firstDataDate < minStart else { return minStart ... domainEnd(now: now) }
        let snapped = self == .year ? firstDataDate.startOfYear : firstDataDate.startOfMonth
        return snapped ... domainEnd(now: now)
    }

    /// Where the domain (and therefore scrolling) ends. The year view keeps a month-aligned end so
    /// its month-snapping scroll always lands on full months; the others stop at the current week's
    /// end so the newest data hugs the right edge.
    private func domainEnd(now: Date) -> Date {
        switch self {
        case .threeMonths, .allTime: return now.endOfWeek
        case .year: return now.endOfYear
        }
    }

    /// Length of the visible window in seconds — what `chartXVisibleDomain` expects. `.allTime`
    /// fits the whole domain into view, which also disables scrolling (content == viewport).
    func visibleDomainSeconds(firstDataDate: Date?, now: Date = .now) -> Int {
        switch self {
        case .threeMonths: return 3600 * 24 * 91
        case .year: return 3600 * 24 * 365
        case .allTime:
            let domain = xDomain(firstDataDate: firstDataDate, now: now)
            return Int(domain.upperBound.timeIntervalSince(domain.lowerBound).rounded(.up))
        }
    }

    /// The initial scroll position (the visible window's *left* edge) placing the newest data at
    /// the right edge: current week for 3M, next month's boundary for 1Y (so month snapping doesn't
    /// fight the edge), the whole domain for All.
    func initialScrollPosition(firstDataDate: Date?, now: Date = .now) -> Date {
        let rightEdge: Date
        switch self {
        case .threeMonths:
            rightEdge = Calendar.current.date(byAdding: .day, value: 1, to: now.endOfWeek) ?? now
        case .year:
            rightEdge = Calendar.current.date(byAdding: .month, value: 1, to: now.startOfMonth) ?? now
        case .allTime:
            rightEdge = xDomain(firstDataDate: firstDataDate, now: now).upperBound
        }
        return Calendar.current.date(
            byAdding: .second,
            value: -visibleDomainSeconds(firstDataDate: firstDataDate, now: now),
            to: rightEdge
        ) ?? rightEdge
    }

    /// What scroll positions snap to: week starts for 3M, month starts for 1Y. Irrelevant for All
    /// (nothing to scroll) — month starts keep the modifier valid.
    var scrollSnapComponents: DateComponents {
        switch self {
        case .threeMonths: return DateComponents(weekday: Calendar.current.firstWeekday)
        case .year, .allTime: return DateComponents(month: 1, day: 1)
        }
    }

    /// X-axis mark cadence: every 2nd week for 3M (~7 marks), monthly for 1Y. All picks by span —
    /// monthly up to a year of data, quarterly to three years, yearly beyond.
    func axisStride(firstDataDate: Date?) -> (component: Calendar.Component, count: Int) {
        switch self {
        case .threeMonths: return (.weekOfYear, 2)
        case .year: return (.month, 1)
        case .allTime:
            switch spannedDays(firstDataDate: firstDataDate) {
            case ..<400: return (.month, 1)
            case ..<1100: return (.month, 3)
            default: return (.year, 1)
            }
        }
    }

    /// Axis label for a mark date, matched to the mark cadence — day-month for weekly marks,
    /// narrow month for monthly, abbreviated month for quarterly, year for yearly.
    func axisLabel(for date: Date, firstDataDate: Date?) -> String {
        switch axisStride(firstDataDate: firstDataDate) {
        case (.weekOfYear, _): return date.formatted(.dateTime.day().month(.defaultDigits))
        case (.month, 1): return date.formatted(Date.FormatStyle().month(.narrow))
        case (.month, _): return date.formatted(Date.FormatStyle().month(.abbreviated))
        default: return date.formatted(.dateTime.year())
        }
    }

    /// Whether an axis mark represents "now" (highlighted label): the current week for weekly
    /// marks, the current month for monthly/quarterly, the current year for yearly.
    func isCurrentAxisMark(_ date: Date, firstDataDate: Date?) -> Bool {
        switch axisStride(firstDataDate: firstDataDate) {
        case (.weekOfYear, _):
            return Calendar.current.isDate(date, equalTo: .now, toGranularity: [.weekOfYear, .yearForWeekOfYear])
        case (.month, _):
            return Calendar.current.isDate(date, equalTo: .now, toGranularity: [.month, .year])
        default:
            return Calendar.current.isDate(date, equalTo: .now, toGranularity: [.year])
        }
    }

    /// Header caption describing the visible window ("14 Apr – 4 Jul", "Jul 2025 – Jul 2026",
    /// "2021 – 2026"), from the scroll position and the window length.
    func visibleWindowDescription(from scrollPosition: Date, firstDataDate: Date?) -> String {
        let end = Calendar.current.date(
            byAdding: .second,
            value: visibleDomainSeconds(firstDataDate: firstDataDate),
            to: scrollPosition
        ) ?? scrollPosition
        switch self {
        case .threeMonths:
            let startText = scrollPosition.isInCurrentYear
                ? scrollPosition.formatted(.dateTime.day().month())
                : scrollPosition.formatted(.dateTime.day().month().year())
            let endText = end.isInCurrentYear
                ? end.formatted(.dateTime.day().month())
                : end.formatted(.dateTime.day().month().year())
            return "\(startText) - \(endText)"
        case .year:
            return "\(scrollPosition.formatted(.dateTime.month().year())) - \(end.formatted(.dateTime.month().year()))"
        case .allTime:
            if spannedDays(firstDataDate: firstDataDate) < 400 {
                return "\(scrollPosition.formatted(.dateTime.month().year())) - \(end.formatted(.dateTime.month().year()))"
            }
            return "\(scrollPosition.formatted(.dateTime.year())) - \(end.formatted(.dateTime.year()))"
        }
    }

    private func spannedDays(firstDataDate: Date?) -> Int {
        let domain = xDomain(firstDataDate: firstDataDate)
        return Int(domain.upperBound.timeIntervalSince(domain.lowerBound)) / (3600 * 24)
    }
}
