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
}
