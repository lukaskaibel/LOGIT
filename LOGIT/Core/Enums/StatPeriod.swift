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

    /// The header label for the window immediately before the one being read — "Previous 4 weeks" /
    /// "Previous 3 months" / "Previous year". The neutral side of every scoped comparison: whatever a
    /// scoped surface reports, it reports it against the same length of time directly before.
    var previousWindowLabel: String {
        switch self {
        case .fourWeeks: return NSLocalizedString("previous4Weeks", comment: "")
        case .threeMonths: return String(format: NSLocalizedString("previousNMonths", comment: ""), 3)
        case .oneYear: return NSLocalizedString("previousYear", comment: "")
        }
    }

    // MARK: Bins

    /// What one bar covers **inside** a window — the unit the history strips and the tile charts are
    /// drawn in.
    ///
    /// A bar is a slice of the selected timeframe, not a whole timeframe of its own. That is the point
    /// of the picker: pick "4 weeks" and every bar on screen is a day of those four weeks, so the
    /// number in the header and the bars under it describe the same span. Bars used to be windows —
    /// picking "4 weeks" drew five four-week blocks and highlighted one, which meant four fifths of
    /// every chart sat outside the timeframe the screen claimed to be reporting.
    ///
    /// Bins are **calendar** units, unlike the rolling windows that contain them: a day is a day, so
    /// "one bar per workout day" is literally true and an untrained day is a visible gap.
    var bin: Calendar.Component {
        switch self {
        case .fourWeeks: return .day
        case .threeMonths: return .weekOfYear
        case .oneYear: return .month
        }
    }

    /// How many bins fill one window — the width of the scrolling viewport, in bars.
    ///
    /// Every window lands at 12–28 bars, which is what keeps the three options reading at the same
    /// density: a tile ~140pt wide gives a 28-bar strip ~3pt bars, and the same strip on a detail
    /// screen is simply a larger copy. Finer bins do not survive the longer windows — a year of days
    /// is 365 bars, under half a point each in a tile — which is why the unit steps up with the
    /// window instead of staying a day throughout.
    ///
    /// The counts are the window in bins: 28 days, 13 weeks (91 days ≈ a quarter), 12 months.
    var binsPerWindow: Int {
        switch self {
        case .fourWeeks: return 28
        case .threeMonths: return 13
        case .oneYear: return 12
        }
    }

    /// Label every `binAxisStride`-th bin, counted back from the newest — 28 day bars cannot each
    /// carry a date without the labels running together. The strides leave 4–7 labels across a
    /// viewport: weekly marks across four weeks, every third week across a quarter, every second
    /// month across a year.
    var binAxisStride: Int {
        switch self {
        case .fourWeeks: return 7
        case .threeMonths: return 3
        case .oneYear: return 2
        }
    }

    /// The stride between the dates written under a **tile's** bin strip, in bins — deliberately
    /// coarser than `binAxisStride`, which labels a full-width detail chart.
    ///
    /// A half-width tile leaves its strip about 145pt, which is four dates' worth of room. Each
    /// window's stride is the one that lands exactly four *and* falls on a boundary worth naming:
    /// every week across four weeks, every four weeks across a quarter, every quarter across a year.
    /// The labels are counted forward from the window's first bin (the chart's leading edge), so the
    /// oldest date always carries one and the trailing edge — where a label would have nowhere to
    /// sit — never does.
    var tileAxisStride: Int {
        switch self {
        case .fourWeeks: return 7
        case .threeMonths: return 4
        case .oneYear: return 3
        }
    }

    /// Axis label under a bin — "9 Aug" for a day or a week (the week's first day), "Aug" for a month.
    ///
    /// Taken from the bin's **start**, unlike the old per-window labels which had to use the end: a
    /// bin is a real calendar unit, so its start names it exactly ("the week of 9 Aug"), while a
    /// rolling window has no name and could only be labelled by the date it reached.
    func binAxisLabel(for range: ClosedRange<Date>) -> String {
        switch self {
        case .fourWeeks, .threeMonths:
            return range.lowerBound.formatted(.dateTime.day().month(.abbreviated))
        case .oneYear:
            return range.lowerBound.formatted(.dateTime.month(.abbreviated))
        }
    }

    /// The full name of a bin for the inspect card — "Mon, 9 Aug" / "9 - 15 Aug" / "Aug 2026". A bin
    /// is a calendar unit, so unlike a rolling window it can simply be named.
    func binTitle(for range: ClosedRange<Date>) -> String {
        switch self {
        case .fourWeeks:
            return range.lowerBound.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        case .threeMonths:
            // The bin's last *day*: its upper bound is the next week's first instant (see `binRanges`),
            // which would print the following Monday.
            let lastDay = range.upperBound.addingTimeInterval(-1)
            return "\(range.lowerBound.formatted(.dateTime.day().month(.abbreviated))) - \(lastDay.formatted(.dateTime.day().month(.abbreviated)))"
        case .oneYear:
            return range.lowerBound.formatted(.dateTime.month(.abbreviated).year())
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

/// The scrollable-strip math for the rolling-window history charts — the `TrendWindow` counterpart to
/// the extension above.
///
/// The strip's bars are **bins** — days, weeks or months inside the selected window (see `bin`) — and
/// its viewport is exactly one window wide, so what the picker names is what is on screen. Bins are
/// evenly spaced whatever unit they are, and a week bin is not a calendar unit `BarMark` can bin a
/// *mixed* strip by, so the strip is plotted on a **synthetic timeline**: one bin per day, counted off
/// an arbitrary epoch. Bin `i` sits on day `i`, the viewport is `binsPerWindow` days wide, and the
/// scroll snaps to midnight — which is to say to whole bins. The dates are pure geometry and never
/// shown; the axis labels come from the bins' real ranges.
///
/// The synthetic day is what buys the strip the machinery Swift Charts only gives a date axis: bars
/// binned by a unit — so `width: .ratio` means "a fraction of a slot", and axis labels centre under
/// the bar they name — and `valueAligned` scroll snapping, so a scroll comes to rest on whole bins.
/// On a plain numeric axis none of that holds: `.ratio` has no step to take a fraction of and renders
/// the bars zero-wide, labels hang off the mark's leading edge, and the scroll rests wherever it
/// stops.
///
/// Every question about "which bins are on screen" is answered here, so the bars, the axis labels,
/// the y-scale, the header and the average line can't disagree about the visible window.
extension TrendWindow {
    /// Day zero of the synthetic timeline. Arbitrary and fixed — only differences matter.
    static let stripEpoch = Calendar.current.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))

    /// The synthetic date bin `index` is plotted on. Counted in calendar days rather than in
    /// 86,400-second steps so every step lands on a real midnight, which is what the scroll snaps to.
    static func stripDate(forIndex index: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: index, to: stripEpoch) ?? stripEpoch
    }

    /// The bin index a point on the synthetic timeline falls on — the inverse of `stripDate`.
    static func stripIndex(for date: Date) -> Int {
        Calendar.current.dateComponents([.day], from: stripEpoch, to: date).day ?? 0
    }

    /// One day, in seconds — the unit `chartXVisibleDomain` is expressed in.
    static let stripDaySeconds = 86_400
    /// How far back a strip may reach, in bins — a guard against one stray date decades in the past
    /// turning the chart into thousands of bars, and the ceiling on how many `BarMark`s a scrolling
    /// chart has to carry. Roughly fourteen months of days, seven and a half years of weeks, thirty
    /// years of months; a reader wanting further back than a strip of days reaches has two longer
    /// windows to switch to, which is the same trade the bin sizes themselves make.
    static let maxStripBinCount = 400

    /// The most recent `count` bins, oldest first, the one holding `now` last.
    ///
    /// Each bin runs from its calendar unit's first instant to the next one's, so the ranges tile the
    /// timeline exactly — every bin's upper bound *is* its newer neighbour's lower bound. That is the
    /// same shared-boundary tiling `range(windowsAgo:)` produces, which is what lets
    /// `binIndex(of:in:)` binary-search a strip of bins and a strip of windows identically, and
    /// what makes the half-open lower edge one rule rather than two.
    func binRanges(count: Int, now: Date = .now) -> [ClosedRange<Date>] {
        let calendar = Calendar.current
        let wanted = min(max(count, 1), Self.maxStripBinCount)
        var ranges: [ClosedRange<Date>] = []
        var cursor = now
        while ranges.count < wanted {
            guard let interval = calendar.dateInterval(of: bin, for: cursor) else { break }
            ranges.append(interval.start ... interval.end)
            // An instant inside the previous bin — `dateInterval` finds it from any date it contains.
            cursor = interval.start.addingTimeInterval(-1)
        }
        return ranges.reversed()
    }

    /// The bins a scrollable strip covers: at least `binsPerWindow` so a young history still fills the
    /// viewport, extended back far enough to reach `firstDataDate`, capped at `maxStripBinCount`.
    ///
    /// The reach is counted in bin units and padded by two. `dateComponents` counts *whole* units
    /// between two dates, so a first workout last Sunday and a "now" on Monday spans zero weeks while
    /// occupying two week bins; the slack costs a couple of empty bins off the left edge, which are
    /// simply gaps nobody has to scroll to, and guarantees the oldest workout is never binned off the
    /// end of the strip.
    func binRanges(firstDataDate: Date?, now: Date = .now) -> [ClosedRange<Date>] {
        var count = binsPerWindow
        if let firstDataDate, firstDataDate < now {
            let spanned = Calendar.current
                .dateComponents([bin], from: firstDataDate, to: now)
                .value(for: bin) ?? 0
            count = max(count, spanned + 2)
        }
        return binRanges(count: count, now: now)
    }

    /// Which bin of a strip a date falls in, or nil when it sits outside it. **Half-open at the lower
    /// edge** like `contains`, so a date landing on the instant two bins share counts once. A binary
    /// search rather than a scan: a strip runs to hundreds of bins and every consumer walks its whole
    /// dataset through this.
    static func binIndex(of date: Date, in ranges: [ClosedRange<Date>]) -> Int? {
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

    /// The bins on screen at `scrollPosition` — the viewport's leading edge on the synthetic timeline.
    /// Exactly one window wide, which is the whole point: what the picker names is what is on screen.
    /// Mid gesture the edge sits between two bins; the day count rounds toward the one occupying the
    /// viewport's first slot, so the header and the y-scale step over cleanly rather than flickering
    /// between two answers around the halfway point.
    func visibleIndices(scrollPosition: Date, binCount: Int) -> Range<Int> {
        guard binCount > 0 else { return 0 ..< 0 }
        let first = min(max(Self.stripIndex(for: scrollPosition), 0), max(binCount - 1, 0))
        let last = min(first + binsPerWindow, binCount)
        return first ..< last
    }

    /// The window's worth of bins immediately *before* `visible` — the neutral side of the comparison,
    /// and the reason a scoped percentage means what the picker says it means. Empty when the strip
    /// does not reach back a whole further window, which is what makes the header show "––" rather
    /// than compare against a partial span.
    func precedingIndices(before visible: Range<Int>) -> Range<Int> {
        let end = visible.lowerBound
        let start = end - binsPerWindow
        guard start >= 0 else { return end ..< end }
        return start ..< end
    }

    /// The scroll offset that puts the newest bin at the trailing edge — where every strip opens, so
    /// the viewport starts on exactly the selected window.
    func trailingScrollPosition(binCount: Int) -> Date {
        Self.stripDate(forIndex: max(binCount - binsPerWindow, 0))
    }
}
