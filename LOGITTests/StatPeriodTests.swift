//
//  StatPeriodTests.swift
//  LOGITTests
//
//  Unit tests for the shared Week/Month/Year period primitive and the muscle target split model.
//

import XCTest

@testable import LOGIT

final class StatPeriodTests: XCTestCase {
    private let calendar = Calendar.current

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return calendar.date(from: components)!
    }

    // MARK: - currentRange

    func testCurrentRangeWeekMatchesStartAndEndOfWeek() {
        let reference = date(2026, 6, 15)
        let range = StatPeriod.week.currentRange(containing: reference)
        XCTAssertEqual(range.lowerBound, reference.startOfWeek)
        XCTAssertEqual(range.upperBound, reference.endOfWeek)
        XCTAssertTrue(range.contains(reference))
    }

    func testCurrentRangeMonthMatchesStartAndEndOfMonth() {
        let reference = date(2026, 6, 15)
        let range = StatPeriod.month.currentRange(containing: reference)
        XCTAssertEqual(range.lowerBound, reference.startOfMonth)
        XCTAssertEqual(range.upperBound, reference.endOfMonth)
        XCTAssertTrue(range.contains(reference))
    }

    func testCurrentRangeYearMatchesStartAndEndOfYear() {
        let reference = date(2026, 6, 15)
        let range = StatPeriod.year.currentRange(containing: reference)
        XCTAssertEqual(range.lowerBound, reference.startOfYear)
        XCTAssertEqual(range.upperBound, reference.endOfYear)
        XCTAssertTrue(range.contains(reference))
    }

    // MARK: - previousRange

    func testPreviousWeekRangeIsTheWeekBeforeAndDoesNotOverlap() {
        let reference = date(2026, 6, 15)
        let current = StatPeriod.week.currentRange(containing: reference)
        let previous = StatPeriod.week.previousRange(before: reference)
        let weekBefore = calendar.date(byAdding: .weekOfYear, value: -1, to: reference)!
        XCTAssertEqual(previous.lowerBound, weekBefore.startOfWeek)
        XCTAssertLessThan(previous.upperBound, current.lowerBound)
    }

    func testPreviousMonthRangeFromMonthEndIsFullPriorMonth() {
        // March 31 minus one month must land in February, not "March 3" — the range helper rebuilds
        // the whole prior month from start to end.
        let reference = date(2026, 3, 31)
        let previous = StatPeriod.month.previousRange(before: reference)
        XCTAssertEqual(previous.lowerBound, date(2026, 2, 10).startOfMonth)
        XCTAssertEqual(previous.upperBound, date(2026, 2, 10).endOfMonth)
    }

    func testPreviousYearRangeIsPriorYear() {
        let reference = date(2026, 6, 15)
        let previous = StatPeriod.year.previousRange(before: reference)
        XCTAssertEqual(previous.lowerBound, date(2025, 1, 1).startOfYear)
        XCTAssertEqual(previous.upperBound, date(2025, 12, 1).endOfYear)
    }

    // MARK: - Titles

    func testTitlesAreNonEmpty() {
        for period in StatPeriod.allCases {
            XCTAssertFalse(period.title.isEmpty)
        }
    }

    // MARK: - History depth

    func testHistoryBucketCountFollowsTheAppWideRule() {
        XCTAssertEqual(StatPeriod.week.historyBucketCount, 12)
        XCTAssertEqual(StatPeriod.month.historyBucketCount, 12)
        XCTAssertEqual(StatPeriod.year.historyBucketCount, 6)
    }
}

// MARK: - ChartRange

final class ChartRangeTests: XCTestCase {
    private let calendar = Calendar.current

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return calendar.date(from: components)!
    }

    func testThreeMonthDomainWithoutDataStartsThreeMonthsBack() {
        let now = date(2026, 7, 4)
        let domain = ChartRange.threeMonths.xDomain(firstDataDate: nil, now: now)
        XCTAssertEqual(domain.lowerBound, calendar.date(byAdding: .month, value: -3, to: now))
        XCTAssertEqual(domain.upperBound, now.endOfWeek)
    }

    func testDomainExtendsBackToFirstDataDateStartOfMonth() {
        let now = date(2026, 7, 4)
        let firstData = date(2025, 11, 20)
        let domain = ChartRange.threeMonths.xDomain(firstDataDate: firstData, now: now)
        XCTAssertEqual(domain.lowerBound, firstData.startOfMonth)
    }

    func testYearDomainEndsAtEndOfYear() {
        let now = date(2026, 7, 4)
        let domain = ChartRange.year.xDomain(firstDataDate: nil, now: now)
        XCTAssertEqual(domain.upperBound, now.endOfYear)
    }

    func testVisibleWindowLengths() {
        XCTAssertEqual(ChartRange.threeMonths.visibleDomainSeconds(firstDataDate: nil), 3600 * 24 * 91)
        XCTAssertEqual(ChartRange.year.visibleDomainSeconds(firstDataDate: nil), 3600 * 24 * 365)
    }

    func testAllTimeVisibleWindowEqualsDomainSpan() {
        let now = date(2026, 7, 4)
        let firstData = date(2022, 3, 9)
        let domain = ChartRange.allTime.xDomain(firstDataDate: firstData, now: now)
        let seconds = ChartRange.allTime.visibleDomainSeconds(firstDataDate: firstData, now: now)
        XCTAssertEqual(Double(seconds), domain.upperBound.timeIntervalSince(domain.lowerBound), accuracy: 1)
    }

    func testAllTimeInitialScrollPositionIsDomainStart() {
        let now = date(2026, 7, 4)
        let firstData = date(2022, 3, 9)
        let domain = ChartRange.allTime.xDomain(firstDataDate: firstData, now: now)
        let position = ChartRange.allTime.initialScrollPosition(firstDataDate: firstData, now: now)
        XCTAssertEqual(position.timeIntervalSince(domain.lowerBound), 0, accuracy: 1)
    }

    func testAllTimeAxisStrideScalesWithSpan() {
        let now = date(2026, 7, 4)
        XCTAssertEqual(ChartRange.allTime.axisStride(firstDataDate: nil).component, .month)
        // ~4 years of data → yearly marks.
        XCTAssertEqual(ChartRange.allTime.axisStride(firstDataDate: calendar.date(byAdding: .year, value: -4, to: now)).component, .year)
    }

    func testTitlesAreNonEmpty() {
        for range in ChartRange.allCases {
            XCTAssertFalse(range.title.isEmpty)
        }
    }
}

// MARK: - PeriodHistoryChart helpers

final class PeriodHistoryChartTests: XCTestCase {
    func testBucketsFollowHistoryDepthOldestFirstCurrentLast() {
        let buckets = PeriodHistoryChart.buckets(for: .week) { _ in 1 }
        XCTAssertEqual(buckets.count, StatPeriod.week.historyBucketCount)
        XCTAssertEqual(buckets.last?.isCurrent, true)
        XCTAssertEqual(buckets.filter(\.isCurrent).count, 1)
        XCTAssertEqual(buckets.first?.date, StatPeriod.week.range(periodsAgo: buckets.count - 1).lowerBound)
        XCTAssertEqual(buckets.last?.date, StatPeriod.week.currentRange().lowerBound)
    }

    func testBucketsPullValuesFromTheirPeriodRange() {
        // Value = days since the current week's start, so each bucket must carry its own range.
        let currentStart = StatPeriod.week.currentRange().lowerBound
        let buckets = PeriodHistoryChart.buckets(for: .week) { range in
            range.lowerBound.timeIntervalSince(currentStart) / (3600 * 24)
        }
        XCTAssertEqual(buckets.last?.value, 0)
        XCTAssertEqual(buckets[buckets.count - 2].value, -7, accuracy: 0.1)
    }

    func testTrendSuppressedUnlessBothPeriodsHaveData() {
        XCTAssertNil(PeriodHistoryChart.trendPercentChange(current: 0, previous: 10), "Fresh period must not read as −100%")
        XCTAssertNil(PeriodHistoryChart.trendPercentChange(current: 10, previous: 0))
        XCTAssertNil(PeriodHistoryChart.trendPercentChange(current: 0, previous: 0))
        XCTAssertEqual(PeriodHistoryChart.trendPercentChange(current: 15, previous: 10) ?? 0, 50, accuracy: 0.001)
        XCTAssertEqual(PeriodHistoryChart.trendPercentChange(current: 5, previous: 10) ?? 0, -50, accuracy: 0.001)
    }
}

// MARK: - MuscleTargetSplit

final class MuscleTargetSplitTests: XCTestCase {
    func testAllPresetsSumTo100() {
        for preset in MuscleTargetPreset.allCases {
            XCTAssertEqual(preset.split.total, 100, "\(preset.rawValue) must sum to 100")
        }
    }

    func testDefaultIsBalancedPreset() {
        XCTAssertEqual(MuscleTargetSplit.default, MuscleTargetPreset.balanced.split)
        XCTAssertEqual(MuscleTargetSplit.default.matchingPreset, .balanced)
    }

    func testAbsentGroupReadsAsZero() {
        let split = MuscleTargetSplit(percentages: [.legs: 50])
        XCTAssertEqual(split.percentage(for: .cardio), 0)
        XCTAssertEqual(split.percentage(for: .legs), 50)
    }

    func testSetPercentageClampsToRange() {
        var split = MuscleTargetSplit(percentages: [:])
        split.setPercentage(-10, for: .chest)
        XCTAssertEqual(split.percentage(for: .chest), 0)
        split.setPercentage(150, for: .chest)
        XCTAssertEqual(split.percentage(for: .chest), 100)
    }

    func testCodableRoundTripPreservesValues() throws {
        let original = MuscleTargetPreset.pushPullLegs.split
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MuscleTargetSplit.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.matchingPreset, .pushPullLegs)
    }

    func testCustomSplitHasNoMatchingPreset() {
        let custom = MuscleTargetSplit(percentages: [.chest: 100])
        XCTAssertNil(custom.matchingPreset)
    }
}

// MARK: - Weekly streak

final class WeeklyStreakTests: XCTestCase {
    private let calendar = Calendar.current
    private let reference = Date(timeIntervalSince1970: 1_780_000_000) // a fixed mid-week instant

    /// Week-start key `weeksAgo` weeks before the reference week.
    private func weekStart(_ weeksAgo: Int) -> Date {
        calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: reference.startOfWeek)!.startOfWeek
    }

    func testZeroTargetIsAlwaysZero() {
        XCTAssertEqual(
            SummaryViewModel.weeklyStreak(countsByWeek: [weekStart(0): 9], target: 0, reference: reference),
            0
        )
    }

    func testNoDataIsZero() {
        XCTAssertEqual(
            SummaryViewModel.weeklyStreak(countsByWeek: [:], target: 4, reference: reference),
            0
        )
    }

    func testInProgressCurrentWeekDoesNotCountButPriorRunDoes() {
        // Current week 3/4 (not met) with five completed weeks behind it, then a missed week.
        var counts: [Date: Int] = [weekStart(0): 3]
        for n in 1 ... 5 { counts[weekStart(n)] = 4 }
        counts[weekStart(6)] = 2
        XCTAssertEqual(
            SummaryViewModel.weeklyStreak(countsByWeek: counts, target: 4, reference: reference),
            5
        )
    }

    func testMetCurrentWeekAddsToStreak() {
        var counts: [Date: Int] = [weekStart(0): 4]
        for n in 1 ... 2 { counts[weekStart(n)] = 5 }
        XCTAssertEqual(
            SummaryViewModel.weeklyStreak(countsByWeek: counts, target: 4, reference: reference),
            3
        )
    }

    func testBreaksOnFirstWeekUnderTarget() {
        let counts: [Date: Int] = [weekStart(0): 4, weekStart(1): 1, weekStart(2): 4]
        XCTAssertEqual(
            SummaryViewModel.weeklyStreak(countsByWeek: counts, target: 4, reference: reference),
            1
        )
    }

    // MARK: - Compact tile averages

    /// Digit characters only, so assertions ignore the locale's grouping / decimal separators
    /// ("1,234.5", "1.234,5" and "1 234,5" all count five digits).
    private func digitCount(_ string: String) -> Int {
        string.filter(\.isNumber).count
    }

    func testTileAverageKeepsDecimalBelowThousand() {
        // Under 1000 the compact tile still carries its one decimal — a rounded count would overstate
        // a fractional average's precision.
        let sets = WorkoutStatMetric.sets.formattedAverage(rawAverage: 18.5, compact: true)
        XCTAssertEqual(digitCount(sets), 3, "18.5 should keep its fractional digit")
        XCTAssertEqual(
            sets,
            WorkoutStatMetric.sets.formattedAverage(rawAverage: 18.5, compact: false),
            "compact and full agree below 1000"
        )
    }

    func testTileAverageDropsDecimalAtThousand() {
        // 1000+: the compact tile drops the fractional part so it doesn't overflow…
        let compact = WorkoutStatMetric.repetitions.formattedAverage(rawAverage: 1234.5, compact: true)
        XCTAssertEqual(digitCount(compact), 4, "1234.5 should render as four whole digits when compact")

        // …while the roomier detail header (non-compact) keeps the decimal.
        let full = WorkoutStatMetric.repetitions.formattedAverage(rawAverage: 1234.5, compact: false)
        XCTAssertEqual(digitCount(full), 5, "the detail header keeps the fractional digit")
        XCTAssertNotEqual(compact, full)
    }

    func testTileAverageDropsDecimalExactlyAtThousand() {
        // The threshold is inclusive: exactly 1000 already drops the decimal.
        let atThreshold = WorkoutStatMetric.repetitions.formattedAverage(rawAverage: 1000.4, compact: true)
        XCTAssertEqual(digitCount(atThreshold), 4, "1000 should render as four whole digits")
    }
}

// MARK: - TrendWindow bins

/// The bins a scoped surface draws: one bar per day / week / month **inside** the selected window.
///
/// The invariants here are what make the Summary's one picker mean one thing. A bar is a slice of the
/// selected timeframe, the viewport is exactly one window wide, and the comparison's baseline is the
/// equally long window immediately before it — so "avg. volume 10,000 kg" and "+8%" read off the same
/// four weeks the picker names, and off the same four weeks the Strength tile beside them reads.
final class TrendWindowBinTests: XCTestCase {
    private let calendar = Calendar.current

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return calendar.date(from: components)!
    }

    /// A viewport is one window of bins — the count the tiles draw and the chart scrolls by.
    func testBinsPerWindowCoverTheWindow() {
        XCTAssertEqual(TrendWindow.fourWeeks.binsPerWindow, 28, "four weeks is twenty-eight days")
        XCTAssertEqual(TrendWindow.threeMonths.binsPerWindow, 13, "a quarter is thirteen weeks")
        XCTAssertEqual(TrendWindow.oneYear.binsPerWindow, 12, "a year is twelve months")
        // Every option has to land in the same range, or the three tiles stop reading alike: a tile
        // is ~140pt wide, and past ~30 bars the bars stop being bars.
        for window in TrendWindow.allCases {
            XCTAssertTrue(
                (12 ... 28).contains(window.binsPerWindow),
                "\(window) draws \(window.binsPerWindow) bars — outside the density every window shares"
            )
        }
    }

    /// `binRanges(count:)` returns exactly what was asked for, newest last.
    func testBinRangesReturnTheRequestedCountEndingNow() {
        let reference = date(2026, 8, 12)
        for window in TrendWindow.allCases {
            let ranges = window.binRanges(count: window.binsPerWindow, now: reference)
            XCTAssertEqual(ranges.count, window.binsPerWindow, "\(window)")
            let newest = ranges.last!
            XCTAssertTrue(
                reference > newest.lowerBound && reference <= newest.upperBound,
                "\(window)'s newest bin must be the one holding now"
            )
        }
    }

    /// Bins must tile the timeline exactly — each bin's upper bound *is* its newer neighbour's lower
    /// bound. Anything else and a workout on a boundary is either counted twice or lost, and the
    /// binary search in `binIndex` stops being valid.
    func testBinsTileTheTimelineWithoutGapsOrOverlap() {
        let reference = date(2026, 8, 12)
        for window in TrendWindow.allCases {
            let ranges = window.binRanges(count: window.binsPerWindow * 2, now: reference)
            for index in 1 ..< ranges.count {
                XCTAssertEqual(
                    ranges[index - 1].upperBound, ranges[index].lowerBound,
                    "\(window) bin \(index) must abut its older neighbour"
                )
            }
        }
    }

    /// The half-open lower edge, shared with `TrendWindow.contains`: a date landing exactly on the
    /// instant two bins share counts once.
    func testBinBoundaryCountsOnce() {
        let reference = date(2026, 8, 12)
        for window in TrendWindow.allCases {
            let ranges = window.binRanges(count: window.binsPerWindow, now: reference)
            let boundary = ranges[ranges.count - 1].lowerBound
            let index = TrendWindow.binIndex(of: boundary, in: ranges)
            XCTAssertEqual(
                index, ranges.count - 2,
                "\(window): a date on a shared boundary belongs to exactly one bin"
            )
        }
    }

    /// Every day of a four-week window gets its own bar, and a workout lands in the bar for its day.
    func testFourWeekBinsAreCalendarDays() {
        let reference = date(2026, 8, 12)
        let ranges = TrendWindow.fourWeeks.binRanges(count: 28, now: reference)
        // The newest bin is today; a workout logged this morning belongs to it.
        let thisMorning = date(2026, 8, 12, hour: 7)
        XCTAssertEqual(TrendWindow.binIndex(of: thisMorning, in: ranges), 27)
        // …and one logged a week ago belongs seven bars to its left.
        let weekAgo = date(2026, 8, 5, hour: 7)
        XCTAssertEqual(TrendWindow.binIndex(of: weekAgo, in: ranges), 20)
        // A workout older than the strip falls outside it rather than being clamped into the oldest
        // bar, which would pile months of training onto one bin.
        XCTAssertNil(TrendWindow.binIndex(of: date(2026, 1, 1), in: ranges))
    }

    /// The strip reaches back to the first logged workout, so nothing scrollable is binned off its
    /// end — and stops at the cap rather than growing without bound.
    func testStripReachesFirstDataDateAndRespectsTheCap() {
        let reference = date(2026, 8, 12)
        for window in TrendWindow.allCases {
            let first = calendar.date(byAdding: .month, value: -7, to: reference)!
            let ranges = window.binRanges(firstDataDate: first, now: reference)
            XCTAssertNotNil(
                TrendWindow.binIndex(of: first, in: ranges),
                "\(window): the first logged workout must fall inside the strip"
            )
            XCTAssertGreaterThanOrEqual(ranges.count, window.binsPerWindow, "\(window) must fill a viewport")

            // A stray date decades back is capped rather than turning the chart into thousands of bars.
            let ancient = calendar.date(byAdding: .year, value: -60, to: reference)!
            let capped = window.binRanges(firstDataDate: ancient, now: reference)
            XCTAssertLessThanOrEqual(capped.count, TrendWindow.maxStripBinCount, "\(window)")
        }
    }

    /// No history at all still fills exactly one viewport — an empty tile draws an empty window, not
    /// a single bar.
    func testStripWithoutHistoryIsExactlyOneWindow() {
        for window in TrendWindow.allCases {
            let ranges = window.binRanges(firstDataDate: nil, now: date(2026, 8, 12))
            XCTAssertEqual(ranges.count, window.binsPerWindow, "\(window)")
        }
    }

    /// The scroll opens with the newest bin at the trailing edge, showing exactly the current window
    /// — the picker names the viewport, so what it names has to be what is on screen.
    func testStripOpensOnTheCurrentWindow() {
        let reference = date(2026, 8, 12)
        for window in TrendWindow.allCases {
            let ranges = window.binRanges(firstDataDate: calendar.date(byAdding: .year, value: -1, to: reference), now: reference)
            let position = window.trailingScrollPosition(binCount: ranges.count)
            let visible = window.visibleIndices(scrollPosition: position, binCount: ranges.count)
            XCTAssertEqual(visible.count, window.binsPerWindow, "\(window) shows one window at a time")
            XCTAssertEqual(visible.upperBound, ranges.count, "\(window) opens at the trailing edge")
        }
    }

    /// The comparison's baseline is the window immediately before the visible one — adjacent, equally
    /// long, and never overlapping it. This is the invariant that stopped the tile and its detail
    /// screen printing two different percentages for the same metric.
    func testPrecedingWindowIsAdjacentAndEquallyLong() {
        let reference = date(2026, 8, 12)
        for window in TrendWindow.allCases {
            let ranges = window.binRanges(firstDataDate: calendar.date(byAdding: .year, value: -2, to: reference), now: reference)
            let visible = window.visibleIndices(
                scrollPosition: window.trailingScrollPosition(binCount: ranges.count),
                binCount: ranges.count
            )
            let preceding = window.precedingIndices(before: visible)
            XCTAssertEqual(preceding.count, window.binsPerWindow, "\(window): baseline is one whole window")
            XCTAssertEqual(preceding.upperBound, visible.lowerBound, "\(window): baseline abuts the visible window")
        }
    }

    /// Too little history for a full baseline yields *no* baseline rather than a partial one — the
    /// header shows "––" instead of comparing four weeks against the five days behind them.
    func testPrecedingWindowIsEmptyWithoutAFullWindowBehindIt() {
        for window in TrendWindow.allCases {
            // A strip only one viewport long: there is nothing before the visible window.
            let visible = 0 ..< window.binsPerWindow
            XCTAssertTrue(window.precedingIndices(before: visible).isEmpty, "\(window)")
        }
    }

    /// Only every `binAxisStride`-th bin is labelled, counted back from the newest so the most recent
    /// bin always carries one — twenty-eight dates in a row would render as an unbroken smear.
    func testAxisLabelsAreStridedAndAnchoredAtTheNewestBin() {
        let reference = date(2026, 8, 12)
        for window in TrendWindow.allCases {
            let ranges = window.binRanges(count: window.binsPerWindow, now: reference)
            let bins = TrendWindowBin.strip(
                for: window,
                ranges: ranges,
                raw: ranges.map { _ in 1 },
                display: { $0 },
                formatted: { String(Int($0)) }
            )
            XCTAssertNotNil(bins.last?.axisLabel, "\(window): the newest bin must be labelled")
            let labelled = bins.filter { $0.axisLabel != nil }.count
            XCTAssertTrue(
                (3 ... 8).contains(labelled),
                "\(window) drew \(labelled) axis labels across a viewport — too few to read by, or too many to fit"
            )
        }
    }

    /// An untrained bin draws no bar. That is what makes a strip of days show the rhythm of a
    /// training week rather than a solid block.
    func testUntrainedBinsHaveNoBar() {
        let window = TrendWindow.fourWeeks
        let ranges = window.binRanges(count: 28, now: date(2026, 8, 12))
        let bins = TrendWindowBin.strip(
            for: window,
            ranges: ranges,
            raw: ranges.enumerated().map { index, _ in index % 2 == 0 ? 0 : 1000 },
            display: { $0 },
            formatted: { String(Int($0)) }
        )
        XCTAssertEqual(bins.filter { $0.value == 0 }.count, 14)
        // …and the dashed reference line averages only the bins that hold training, so rest days
        // can't drag it below the bars it is meant to sit among.
        let stats = TrendWindowBin.visibleStats(bins: bins, indices: 0 ..< bins.count)
        XCTAssertEqual(stats.trainedMean, 1000)
        XCTAssertEqual(stats.displayMax, 1000)
    }
}
