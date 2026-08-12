//
//  StatPeriod.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import Foundation

/// The Week / Month / Year scope shared by the Summary's month-scoped tiles and the stat detail
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

// MARK: - Trend Window

/// The **rolling** window every scoped surface in the Summary reports over — 4 weeks, 3 months or a
/// year, each one ending *now* rather than on a calendar boundary. Distinct from `StatPeriod` on
/// purpose: that enum answers "which calendar week/month/year is this", which is the right question
/// for a running total and the wrong one for a trend, where a part-elapsed calendar month would make
/// the number lie for three weeks out of four.
///
/// **This is the Summary's one timeframe.** The screen carries a single `TrendWindowPicker`, and
/// everything scoped by it — the Strength and Balance pair, the four core-stat tiles, the pinned
/// exercise tiles — reads this same window, as do all six detail screens behind them (Strength,
/// Muscle Groups, and the Volume / Duration / Sets / Reps stat screens). Before this the screen
/// reported over five different spans at once with nothing on it saying so; anything new that scopes
/// itself by time belongs on this enum and that picker, not on a private one.
///
/// Two things deliberately do **not** scope: the weekly-goal pill in the title row, which is a weekly
/// target by definition, and the Highlights carousel, which lists events rather than aggregates and
/// stays on the recent window so it keeps meaning "what just happened" (its own screen offers the
/// picker to widen).
///
/// `default` is four weeks — the window `Exercise.currentBestWindowStart` already calls "current" and
/// the one the tiles opened on before there was a picker.
enum TrendWindow: String, CaseIterable, Identifiable {
    case fourWeeks, threeMonths, oneYear

    static let `default` = TrendWindow.fourWeeks

    var id: String { rawValue }

    /// Restores a persisted selection, falling back to the default for an unknown or empty raw value
    /// — the one place the `@AppStorage`-backed Summary scope is decoded, so a stale string from an
    /// older build can't leave a screen scopeless.
    static func stored(_ rawValue: String) -> TrendWindow {
        TrendWindow(rawValue: rawValue) ?? .default
    }

    /// One window's length, as a calendar step. `.weekOfYear`/4 rather than `.day`/28 so the window
    /// tracks the user's calendar the way every other span in the app does.
    var step: (component: Calendar.Component, value: Int) {
        switch self {
        case .fourWeeks: return (.weekOfYear, 4)
        case .threeMonths: return (.month, 3)
        case .oneYear: return (.year, 1)
        }
    }

    /// Segment title — "4 weeks" / "3 months" / "1 year".
    var title: String {
        switch self {
        case .fourWeeks: return String(format: NSLocalizedString("nWeeks", comment: ""), 4)
        case .threeMonths: return String(format: NSLocalizedString("nMonths", comment: ""), 3)
        case .oneYear: return NSLocalizedString("oneYear", comment: "")
        }
    }

    /// The header label for the window ending now — "Last 4 weeks" / "Last 3 months" / "Last year".
    var currentWindowLabel: String {
        switch self {
        case .fourWeeks: return NSLocalizedString("last4Weeks", comment: "")
        case .threeMonths: return String(format: NSLocalizedString("lastNMonths", comment: ""), 3)
        case .oneYear: return NSLocalizedString("lastYear", comment: "")
        }
    }

    /// The window `n` windows back — `n == 0` is the current one, which ends at `date` exactly. Each
    /// older window is the same length again, counted back from there, so the run tiles the timeline
    /// without gaps or overlap.
    func range(windowsAgo n: Int, from date: Date = .now) -> ClosedRange<Date> {
        let calendar = Calendar.current
        let step = self.step
        let end = calendar.date(byAdding: step.component, value: -n * step.value, to: date) ?? date
        let start = calendar.date(byAdding: step.component, value: -step.value, to: end) ?? end
        return start ... end
    }

    /// The window ending now — "the selected timeframe" itself. Every scoped surface goes through
    /// this rather than reaching for a date offset of its own, which is how the Summary ended up
    /// reporting over five spans at once.
    func currentRange(from date: Date = .now) -> ClosedRange<Date> {
        range(windowsAgo: 0, from: date)
    }

    /// The current window's first instant — the cutoff an "is this in scope" filter compares against.
    func windowStart(from date: Date = .now) -> Date {
        currentRange(from: date).lowerBound
    }

    /// Whether `date` falls in the window `n` windows back. **Half-open at the lower edge**:
    /// consecutive windows share a boundary instant, so a workout landing exactly on one counts once
    /// — in the newer window — rather than in both. The one membership test for every rolling
    /// window, so a bucket strip and the tile above it can't disagree about which side a workout
    /// falls on.
    func contains(_ date: Date, windowsAgo n: Int = 0, from reference: Date = .now) -> Bool {
        let range = self.range(windowsAgo: n, from: reference)
        return date > range.lowerBound && date <= range.upperBound
    }

    /// The dates a window covers, as a caption ("9 Jul – 6 Aug", "Jul 2026 – Aug 2026"). Rolling
    /// windows have no names — "June" is a calendar month, not a four-week block — so naming one can
    /// only mean saying which dates it holds. Granularity follows the window: days read as noise
    /// across a year, and a month name is uselessly coarse across four weeks.
    func dateSpan(_ range: ClosedRange<Date>) -> String {
        let format: Date.FormatStyle
        switch self {
        case .fourWeeks: format = .dateTime.day().month(.abbreviated)
        case .threeMonths, .oneYear: format = .dateTime.month(.abbreviated).year()
        }
        let start = range.lowerBound.formatted(format)
        let end = range.upperBound.formatted(format)
        return start == end ? start : "\(start) - \(end)"
    }

    /// How much of the span a trend needs — the current window plus the one before it — the logged
    /// history actually covers, 0…1. The fill of the "building your trend" ring, so a fresh account
    /// sees a placeholder that creeps forward as history accumulates rather than one stuck at a fixed
    /// mark. Lives here because every scoped surface wants the same answer for the same window.
    func historyFraction(firstDataDate: Date?, from reference: Date = .now) -> Double {
        guard let firstDataDate else { return 0 }
        let span = reference.timeIntervalSince(range(windowsAgo: 1, from: reference).lowerBound)
        guard span > 0 else { return 0 }
        return min(max(reference.timeIntervalSince(firstDataDate) / span, 0), 1)
    }

    /// How many windows of history a `TrendWindowHistoryChart` shows **at once** — the stat detail
    /// screens and the muscle detail's sets chart: about half a year of four-week blocks, two years of
    /// quarters, six years. The strip itself runs back to the first logged workout; this is the width
    /// of the viewport that scrolls along it.
    ///
    /// Four weeks is capped by its **axis labels**, not by how much history is interesting. A rolling
    /// four-week block has no name, so its label has to be a date ("9 Jun"), and thirteen of those —
    /// a tidy calendar year — render as one unbroken run of overlapping text. Seven fit with room to
    /// spare, and a reader wanting more history has two longer windows to switch to.
    var historyBucketCount: Int {
        switch self {
        case .fourWeeks: return 7
        case .threeMonths: return 8
        case .oneYear: return 6
        }
    }

    /// How much history a viewport of `historyBucketCount` windows covers, as a caption — "28 weeks",
    /// "24 months", "6 years". The counterpart to `StatPeriod`'s fixed "12 weeks" / "12
    /// months" / "6 years" captions, computed rather than spelled out because the bucket counts
    /// differ per window (see `historyBucketCount`) and a hardcoded string would drift from them.
    var historySpanCaption: String {
        let span = historyBucketCount * step.value
        switch self {
        case .fourWeeks: return String(format: NSLocalizedString("nWeeks", comment: ""), span)
        case .threeMonths: return String(format: NSLocalizedString("nMonths", comment: ""), span)
        case .oneYear: return NSLocalizedString("sixYears", comment: "")
        }
    }

    /// Axis label under a history bar — "6 Aug" / "Aug" / "2026".
    ///
    /// Taken from the window's **end**, not its start. A trailing window labelled by its start reads
    /// as a calendar unit it isn't: the current year-long window runs from last August to today, and
    /// labelling it "2025" says the wrong year outright. The end is the date the bar reaches, which
    /// is what a reader scanning left to right is actually looking for.
    func axisLabel(forWindowEnding end: Date) -> String {
        switch self {
        case .fourWeeks: return end.formatted(.dateTime.day().month(.abbreviated))
        case .threeMonths: return end.formatted(.dateTime.month(.abbreviated))
        case .oneYear: return end.formatted(.dateTime.year())
        }
    }

    /// The full title for a window: the "Last …" label for the current one, otherwise the span it
    /// covers. Rolling windows don't have names ("June" is a calendar month, not a 4-week block), so
    /// an older window can only honestly say which dates it holds.
    func windowTitle(windowsAgo n: Int, from date: Date = .now) -> String {
        guard n > 0 else { return currentWindowLabel }
        let range = self.range(windowsAgo: n, from: date)
        let format: Date.FormatStyle
        switch self {
        case .fourWeeks: format = .dateTime.day().month(.abbreviated)
        case .threeMonths: format = .dateTime.month(.abbreviated).year()
        case .oneYear: format = .dateTime.month(.abbreviated).year()
        }
        return "\(range.lowerBound.formatted(format)) - \(range.upperBound.formatted(format))"
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

/// The scrollable-strip math for the rolling-window history charts — the `TrendWindow` counterpart to
/// the extension above.
///
/// A rolling window has no calendar unit to bin or snap to (four weeks is not a month), so the strip
/// is plotted on a **synthetic timeline**: one window per day, counted off an arbitrary epoch. Bucket
/// `i` sits on day `i`, the viewport is `historyBucketCount` days wide, and the scroll snaps to
/// midnight — which is to say to whole windows. The dates are pure geometry and never shown; the axis
/// labels come from the buckets.
///
/// The synthetic day is what buys the strip the machinery Swift Charts only gives a date axis: bars
/// binned by a unit — so `width: .ratio` means "a fraction of a slot", and axis labels centre under
/// the bar they name — and `valueAligned` scroll snapping, so a scroll comes to rest on whole windows.
/// On a plain numeric axis none of that holds: `.ratio` has no step to take a fraction of and renders
/// the bars zero-wide, labels hang off the mark's leading edge, and the scroll rests wherever it
/// stops.
///
/// Every question about "which windows are on screen" is answered here, so the bars, the axis labels,
/// the y-scale and the moving average line can't disagree about the visible window.
extension TrendWindow {
    /// Day zero of the synthetic timeline. Arbitrary and fixed — only differences matter.
    static let stripEpoch = Calendar.current.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))

    /// The synthetic date bucket `index` is plotted on. Counted in calendar days rather than in
    /// 86,400-second steps so every step lands on a real midnight, which is what the scroll snaps to.
    static func stripDate(forIndex index: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: index, to: stripEpoch) ?? stripEpoch
    }

    /// The bucket index a point on the synthetic timeline falls on — the inverse of `stripDate`.
    static func stripIndex(for date: Date) -> Int {
        Calendar.current.dateComponents([.day], from: stripEpoch, to: date).day ?? 0
    }

    /// One day, in seconds — the unit `chartXVisibleDomain` is expressed in.
    static let stripDaySeconds = 86_400
    /// How far back a strip may reach, in windows — a guard against one stray date decades in the past
    /// turning the chart into hundreds of bars. Nine years of four-week blocks, thirty of quarters.
    static let maxHistoryWindowCount = 120

    /// The windows the strip covers, oldest first, the current one last: at least `historyBucketCount`
    /// of them so a young history still fills the viewport, extended back until the oldest one reaches
    /// `firstDataDate`. Contiguous by construction (each window abuts its neighbour), which is what
    /// lets `bucketIndex(of:in:)` binary-search them.
    func historyRanges(firstDataDate: Date?, now: Date = .now) -> [ClosedRange<Date>] {
        var ranges: [ClosedRange<Date>] = []
        var windowsAgo = 0
        while windowsAgo < Self.maxHistoryWindowCount {
            let range = self.range(windowsAgo: windowsAgo, from: now)
            ranges.append(range)
            windowsAgo += 1
            let needsMoreForViewport = windowsAgo < historyBucketCount
            let reachesFurtherBack = firstDataDate.map { $0 < range.lowerBound } ?? false
            guard needsMoreForViewport || reachesFurtherBack else { break }
        }
        return ranges.reversed()
    }

    /// Which bucket of a strip a date falls in, or nil when it sits outside it. **Half-open at the
    /// lower edge** like `contains`, so a date landing on the instant two windows share counts in the
    /// newer one only. A binary search rather than a scan: a strip runs to dozens of buckets and every
    /// consumer walks its whole dataset through this.
    static func bucketIndex(of date: Date, in ranges: [ClosedRange<Date>]) -> Int? {
        guard let first = ranges.first, let last = ranges.last,
              date > first.lowerBound, date <= last.upperBound else { return nil }
        var low = 0
        var high = ranges.count - 1
        while low < high {
            let mid = (low + high) / 2
            if date <= ranges[mid].upperBound { high = mid } else { low = mid + 1 }
        }
        return low
    }

    /// The buckets on screen at `scrollPosition` — the viewport's leading edge on the synthetic
    /// timeline. Mid gesture the edge sits between two buckets; the day count rounds toward the one
    /// occupying the viewport's first slot, so the average and the y-scale step over cleanly rather
    /// than flickering between two answers around the halfway point.
    func visibleIndices(scrollPosition: Date, bucketCount: Int) -> Range<Int> {
        guard bucketCount > 0 else { return 0 ..< 0 }
        let first = min(max(Self.stripIndex(for: scrollPosition), 0), max(bucketCount - 1, 0))
        let last = min(first + historyBucketCount, bucketCount)
        return first ..< last
    }

    /// The scroll offset that puts the current window at the trailing edge — where every strip opens.
    func trailingScrollPosition(bucketCount: Int) -> Date {
        Self.stripDate(forIndex: max(bucketCount - historyBucketCount, 0))
    }
}
