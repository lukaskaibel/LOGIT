//
//  StatPeriod.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import Foundation

/// The Week / Month / Year scope shared by the Summary screen's period selector and the stat detail
/// screens. The single source of truth for "the current period", "the equivalent prior period", and
/// the localized segment titles — replacing the per-screen private `ChartGranularity` enums every
/// detail screen used to declare on its own.
enum StatPeriod: String, CaseIterable, Identifiable {
    case week, month, year

    var id: String { rawValue }

    /// Localized segment title ("Week" / "Month" / "Year"), reusing the keys the detail-screen
    /// granularity pickers already ship.
    var title: String { NSLocalizedString(rawValue, comment: "") }

    /// The closed date range of the period containing `date` — this calendar week, month, or year.
    /// Built on the `Date.startOf…`/`endOf…` helpers so the week boundary respects the user's locale.
    func currentRange(containing date: Date = .now) -> ClosedRange<Date> {
        switch self {
        case .week: return date.startOfWeek ... date.endOfWeek
        case .month: return date.startOfMonth ... date.endOfMonth
        case .year: return date.startOfYear ... date.endOfYear
        }
    }

    /// The equivalent prior period before the one containing `date` — last week / last month / last
    /// year. Load-bearing for every "vs last period" trend pill in the stats grid: the trend compares
    /// `currentRange` against this.
    func previousRange(before date: Date = .now) -> ClosedRange<Date> {
        range(periodsAgo: 1, from: date)
    }

    /// How far through the current period `now` sits — 0 at the period's first instant, 1 at its last
    /// (clamped). Drives the "building your trend" ring on a fresh tile, so it fills as the week (or
    /// month / year) goes on rather than sitting at a fixed mark.
    func elapsedFraction(now: Date = .now) -> Double {
        let range = currentRange(containing: now)
        let total = range.upperBound.timeIntervalSince(range.lowerBound)
        guard total > 0 else { return 0 }
        return min(max(now.timeIntervalSince(range.lowerBound) / total, 0), 1)
    }

    /// How many periods of history a period-scoped chart shows — the current period plus its recent
    /// past. One rule for every such chart in the app: 12 recent weeks, 12 recent months or 6 recent
    /// years, so switching screens never silently changes how far back "history" reaches.
    var historyBucketCount: Int {
        switch self {
        case .week, .month: return 12
        case .year: return 6
        }
    }

    /// Localized "This Week" / "This Month" / "This Year" — the header label above a stat scoped to
    /// the current period.
    var currentPeriodLabel: String {
        switch self {
        case .week: return NSLocalizedString("thisWeek", comment: "")
        case .month: return NSLocalizedString("thisMonth", comment: "")
        case .year: return NSLocalizedString("thisYear", comment: "")
        }
    }

    /// The calendar component one period spans — the x-axis unit of one history bar.
    var calendarComponent: Calendar.Component {
        switch self {
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        }
    }

    /// Axis label for a history bucket's start date ("9 Jun" / "J" / "2026"), shared by every
    /// period-scoped history chart.
    func axisLabel(for date: Date) -> String {
        switch self {
        case .week: return date.formatted(.dateTime.day().month(.abbreviated))
        case .month: return date.formatted(.dateTime.month(.narrow))
        case .year: return date.formatted(.dateTime.year())
        }
    }

    /// The closed range of the period `n` periods before the one containing `date` — `n == 0` is the
    /// current period, `n == 1` the previous. Powers the stats grid's history bars and the
    /// detail screen's recent-periods chart.
    func range(periodsAgo n: Int, from date: Date = .now) -> ClosedRange<Date> {
        let component: Calendar.Component
        switch self {
        case .week: component = .weekOfYear
        case .month: component = .month
        case .year: component = .year
        }
        let shifted = Calendar.current.date(byAdding: component, value: -n, to: date) ?? date
        return currentRange(containing: shifted)
    }

    /// The span the history average covers — the oldest history bucket through the last finished
    /// period, excluding the current, in-progress one. Anchors the "Average" caption on the stat
    /// detail headers so the number reads against a legible window.
    func completedHistoryRange(now: Date = .now) -> ClosedRange<Date> {
        let start = range(periodsAgo: historyBucketCount - 1, from: now).lowerBound
        let end = range(periodsAgo: 1, from: now).upperBound
        return start ... end
    }

    /// A compact "start – end" caption for a date span at this granularity — days for weeks
    /// ("14 Apr - 29 Jun"), month + year for months, the year for years — collapsing to a single
    /// token when both ends land in the same unit ("Jul 2026", "2026"). The year is dropped from a
    /// week span sitting entirely in the current year, matching the scrollable chart-range headers.
    func rangeCaption(_ range: ClosedRange<Date>) -> String {
        let lower = range.lowerBound
        let upper = range.upperBound
        switch self {
        case .week:
            let start = lower.isInCurrentYear
                ? lower.formatted(.dateTime.day().month())
                : lower.formatted(.dateTime.day().month().year())
            let end = upper.isInCurrentYear
                ? upper.formatted(.dateTime.day().month())
                : upper.formatted(.dateTime.day().month().year())
            return "\(start) - \(end)"
        case .month:
            let start = lower.formatted(.dateTime.month().year())
            let end = upper.formatted(.dateTime.month().year())
            return start == end ? start : "\(start) - \(end)"
        case .year:
            let start = lower.formatted(.dateTime.year())
            let end = upper.formatted(.dateTime.year())
            return start == end ? start : "\(start) - \(end)"
        }
    }
}

// MARK: - Stat Basis

/// How a period's workouts collapse into the single number a stat surface shows: the running
/// **total** over the period, or the **per-workout average** that divides frequency out so a light
/// week and a heavy week compare on session quality alone — the reason a one-workout week can still
/// be read against a four-workout one. The Summary tiles are always per-workout; their detail screens
/// let the reader flip back to totals.
enum StatBasis: String, CaseIterable, Identifiable {
    case perWorkout, total

    var id: String { rawValue }

    /// Segmented-control title — "Per Workout" / "Total".
    var title: String {
        switch self {
        case .perWorkout: return NSLocalizedString("perWorkoutBasis", comment: "")
        case .total: return NSLocalizedString("total", comment: "")
        }
    }

    /// Collapses a period's summed raw value and its non-empty workout count into the one number this
    /// basis shows. Per-workout is the mean per session — zero when the period had no workout, so an
    /// empty period reads as no data rather than a misleading zero average; total is the sum untouched.
    func aggregate(sum: Int, count: Int) -> Double {
        switch self {
        case .total: return Double(sum)
        case .perWorkout: return count > 0 ? Double(sum) / Double(count) : 0
        }
    }
}

// MARK: - Scrollable chart geometry

/// The scrollable-timeline math for the period-history charts — the mirror of `ChartRange`'s for the
/// capability charts, but derived from `range(periodsAgo:)` so a "week" window is exactly the twelve
/// calendar weeks it shows, not an approximate span. Living here (not per screen) keeps every period
/// chart scrolling, snapping and framing the current period identically.
extension StatPeriod {
    /// The visible window in seconds — exactly the most recent `historyBucketCount` periods, which is
    /// what `chartXVisibleDomain` expects and the fixed width the chart showed before it scrolled.
    func visibleDomainSeconds(now: Date = .now) -> Int {
        let start = range(periodsAgo: historyBucketCount - 1, from: now).lowerBound
        let end = currentRange(containing: now).upperBound
        return Int(end.timeIntervalSince(start).rounded(.up))
    }

    /// The full scrollable domain: from the period containing the first data point through the current
    /// period's end, but never shorter than one visible window so a young history still fills the chart.
    func scrollableXDomain(firstDataDate: Date?, now: Date = .now) -> ClosedRange<Date> {
        let end = currentRange(containing: now).upperBound
        let windowStart = range(periodsAgo: historyBucketCount - 1, from: now).lowerBound
        guard let firstDataDate, firstDataDate < windowStart else { return windowStart ... end }
        return currentRange(containing: firstDataDate).lowerBound ... end
    }

    /// The initial scroll position (the visible window's left edge) placing the current period at the
    /// right edge — the chart opens on the most recent periods, the fixed view it replaced.
    func initialScrollPosition(now: Date = .now) -> Date {
        let end = currentRange(containing: now).upperBound
        return Calendar.current.date(byAdding: .second, value: -visibleDomainSeconds(now: now), to: end) ?? end
    }

    /// What scroll positions snap to: the start of a week / month / year.
    var scrollSnapComponents: DateComponents {
        switch self {
        case .week: return DateComponents(weekday: Calendar.current.firstWeekday)
        case .month: return DateComponents(day: 1)
        case .year: return DateComponents(month: 1, day: 1)
        }
    }

    /// X-axis mark cadence on the scrollable chart — about six marks across the visible window.
    var scrollAxisStride: (component: Calendar.Component, count: Int) {
        switch self {
        case .week: return (.weekOfYear, 2)
        case .month: return (.month, 2)
        case .year: return (.year, 1)
        }
    }

    /// The explicit x-axis mark dates for the scrollable chart: period starts counted back from the
    /// current period in `scrollAxisStride` steps, across the whole scrollable domain. The stride is
    /// anchored at "now" rather than at the domain's start (whose parity shifts with where the data
    /// happens to begin) so the current period always carries a mark — the label the chart bolds.
    func scrollAxisValues(firstDataDate: Date?, now: Date = .now) -> [Date] {
        let domainStart = scrollableXDomain(firstDataDate: firstDataDate, now: now).lowerBound
        let stride = scrollAxisStride
        var marks: [Date] = []
        var mark = currentRange(containing: now).lowerBound
        while mark >= domainStart {
            marks.append(mark)
            guard let previous = Calendar.current.date(
                byAdding: stride.component, value: -stride.count, to: mark
            ) else { break }
            mark = currentRange(containing: previous).lowerBound
        }
        return marks.reversed()
    }

    /// Whether the mark at `date` yields its label to the current period's: true only for the mark
    /// one stride before the current period on the week axis. The current label hangs trailing off
    /// its mark (so the plot edge can't clip it), and the week axis is the one granularity whose
    /// day-month labels are wide enough relative to the two-week stride that the two would collide —
    /// month letters and year numbers keep clear of it on their own.
    func axisLabelYieldsToCurrent(_ date: Date, now: Date = .now) -> Bool {
        guard self == .week else { return false }
        let stride = scrollAxisStride
        guard let next = Calendar.current.date(
            byAdding: stride.component, value: stride.count, to: date
        ) else { return false }
        return currentRange(containing: now).contains(next)
    }

    /// The visible window as a date range — `[scrollPosition, scrollPosition + one window]` — for the
    /// header's moving "average" caption and the visible-window average it labels.
    func visibleWindowRange(from scrollPosition: Date, now: Date = .now) -> ClosedRange<Date> {
        let end = Calendar.current.date(byAdding: .second, value: visibleDomainSeconds(now: now), to: scrollPosition) ?? scrollPosition
        return scrollPosition ... end
    }
}
