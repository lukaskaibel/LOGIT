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

// MARK: - MuscleFocus

final class MuscleFocusTests: XCTestCase {
    private let goals = 1 ... 9

    func testPresetsTargetEveryStrengthGroupAndOnlyTheCardioPresetTargetsCardio() {
        for preset in MuscleFocusPreset.allCases {
            let focus = preset.focus(forWorkoutsPerWeek: MuscleFocus.baseWorkoutsPerWeek)
            for group in MuscleGroup.allCases where group != .cardio {
                XCTAssertGreaterThan(focus.target(for: group), 0, "\(preset.rawValue) must keep \(group.rawValue) at maintenance at least")
            }
            XCTAssertEqual(focus.target(for: .cardio) > 0, preset == .cardio, "Only the cardio focus targets cardio")
        }
    }

    func testPresetsAreFiveDistinctWeeksThatRecogniseThemselvesAtEveryGoal() {
        XCTAssertEqual(MuscleFocusPreset.allCases.count, 5)
        for goal in goals {
            let focuses = MuscleFocusPreset.allCases.map { $0.focus(forWorkoutsPerWeek: goal) }
            for (index, focus) in focuses.enumerated() {
                XCTAssertEqual(focus.matchingPreset, MuscleFocusPreset.allCases[index], "at \(goal) a week")
                XCTAssertEqual(focus.workoutsPerWeek, goal)
                for other in focuses[(index + 1)...] {
                    XCTAssertFalse(focus.hasSameTargets(as: other), "two presets collide at \(goal) a week")
                }
            }
        }
    }

    func testBackIsNeverBehindChestInAPreset() {
        for preset in MuscleFocusPreset.allCases {
            XCTAssertGreaterThanOrEqual(preset.baseTargets[.back] ?? 0, preset.baseTargets[.chest] ?? 0, preset.rawValue)
        }
    }

    func testDefaultIsFullBodyForTheBaseWeek() {
        XCTAssertEqual(MuscleFocus.default.matchingPreset, .fullBody)
        XCTAssertEqual(MuscleFocus.default.workoutsPerWeek, 3)
        XCTAssertEqual(MuscleFocus.default.weeklyTotal, 46)
    }

    func testPresetsScaleWithTheWeeklyGoal() {
        func week(_ goal: Int) -> [Int] {
            let focus = MuscleFocusPreset.fullBody.focus(forWorkoutsPerWeek: goal)
            return MuscleFocus.displayOrder.map { focus.target(for: $0) }
        }
        // legs, back, chest, shoulders, biceps, triceps, abs, cardio
        XCTAssertEqual(week(2), [7, 7, 5, 4, 3, 3, 3, 0])
        XCTAssertEqual(week(3), [10, 10, 8, 6, 4, 4, 4, 0])
        XCTAssertEqual(week(4), [13, 13, 11, 8, 5, 5, 5, 0])
        XCTAssertEqual(week(5), [17, 17, 13, 10, 7, 7, 7, 0])
        let single = MuscleFocusPreset.cardio.focus(forWorkoutsPerWeek: 1)
        for group in MuscleGroup.allCases {
            XCTAssertGreaterThanOrEqual(single.target(for: group), 1, "a targeted group never scales away")
        }
        XCTAssertLessThanOrEqual(
            MuscleFocusPreset.lowerBody.focus(forWorkoutsPerWeek: 9).target(for: .legs),
            MuscleFocus.targetRange.upperBound
        )
    }

    func testDisplayOrderCoversEveryGroupOnce() {
        XCTAssertEqual(Set(MuscleFocus.displayOrder), Set(MuscleGroup.allCases))
        XCTAssertEqual(MuscleFocus.displayOrder.count, MuscleGroup.allCases.count)
    }

    func testTargetsClampToTheStepperRange() {
        var focus = MuscleFocus.default
        focus.setTarget(99, for: .legs)
        XCTAssertEqual(focus.target(for: .legs), MuscleFocus.targetRange.upperBound)
        focus.setTarget(-3, for: .legs)
        XCTAssertEqual(focus.target(for: .legs), 0)
        XCTAssertTrue(focus.isExcluded(.legs))
        XCTAssertFalse(focus.includedGroups.contains(.legs))
    }

    func testChangingATargetMakesTheFocusCustom() {
        var focus = MuscleFocusPreset.upperBody.focus(forWorkoutsPerWeek: 4)
        XCTAssertEqual(focus.matchingPreset, .upperBody)
        focus.setTarget(9, for: .legs)
        XCTAssertNil(focus.matchingPreset)
    }

    func testLastGroupWithATargetCannotReachZero() {
        var focus = MuscleFocus.default
        for group in MuscleGroup.allCases where group != .chest {
            focus.setTarget(0, for: group)
        }
        XCTAssertEqual(focus.includedGroups, [.chest])
        XCTAssertEqual(focus.minimumTarget(for: .chest), 1)
        focus.setTarget(0, for: .chest)
        XCTAssertEqual(focus.target(for: .chest), 1)
        XCTAssertEqual(focus.minimumTarget(for: .legs), 0, "Other groups can still be at 0")
    }

    // MARK: Resizing for a new weekly goal

    func testResizingAPresetKeepsItExactlyThatPreset() {
        let resized = MuscleFocusPreset.armsAndShoulders.focus(forWorkoutsPerWeek: 3).resized(forWorkoutsPerWeek: 5)
        XCTAssertEqual(resized, MuscleFocusPreset.armsAndShoulders.focus(forWorkoutsPerWeek: 5))
        XCTAssertEqual(resized.matchingPreset, .armsAndShoulders)
        // Back again lands on the preset too, with no rounding drift from the round trip.
        XCTAssertEqual(resized.resized(forWorkoutsPerWeek: 3), MuscleFocusPreset.armsAndShoulders.focus(forWorkoutsPerWeek: 3))
    }

    func testResizingCustomTargetsScalesEveryGroupAndKeepsZeroes() {
        var custom = MuscleFocusPreset.fullBody.focus(forWorkoutsPerWeek: 3)
        custom.setTarget(12, for: .legs)
        custom.setTarget(1, for: .abdominals)
        let resized = custom.resized(forWorkoutsPerWeek: 6)
        XCTAssertNil(resized.matchingPreset)
        XCTAssertEqual(resized.workoutsPerWeek, 6)
        XCTAssertEqual(resized.target(for: .legs), 24)
        XCTAssertEqual(resized.target(for: .abdominals), 2)
        XCTAssertEqual(resized.target(for: .cardio), 0, "A group out of the focus stays out")
        let shrunk = custom.resized(forWorkoutsPerWeek: 1)
        XCTAssertEqual(shrunk.target(for: .abdominals), 1, "A group in the focus never scales to zero")
    }

    func testTheOfferToRescaleIsForANewGoalTheUserHasNotKept() {
        var focus = MuscleFocusPreset.fullBody.focus(forWorkoutsPerWeek: 3)
        XCTAssertFalse(focus.suggestsResize(forWorkoutsPerWeek: nil), "No goal, nothing to size for")
        XCTAssertFalse(focus.suggestsResize(forWorkoutsPerWeek: 3))
        XCTAssertTrue(focus.suggestsResize(forWorkoutsPerWeek: 4))
        focus.keep(forWorkoutsPerWeek: 4)
        XCTAssertFalse(focus.suggestsResize(forWorkoutsPerWeek: 4), "Not Now holds for that goal")
        XCTAssertTrue(focus.suggestsResize(forWorkoutsPerWeek: 5), "…and not for the next one")
        XCTAssertEqual(focus.matchingPreset, .fullBody, "Keeping the targets doesn't make them custom")
    }

    // MARK: Persistence

    func testCodableRoundTripKeepsTargetsTheGoalAndAKeptGoal() throws {
        var original = MuscleFocusPreset.lowerBody.focus(forWorkoutsPerWeek: 4)
        original.setTarget(13, for: .back)
        original.keep(forWorkoutsPerWeek: 6)
        let decoded = try JSONDecoder().decode(MuscleFocus.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.target(for: .back), 13)
        XCTAssertEqual(decoded.workoutsPerWeek, 4)
        XCTAssertFalse(decoded.suggestsResize(forWorkoutsPerWeek: 6))
    }

    func testTargetsSavedBeforeGoalSizingBecomeTheirSuccessorPresets() throws {
        func decode(_ targets: String) throws -> MuscleFocus {
            try JSONDecoder().decode(MuscleFocus.self, from: Data(#"{"targets": \#(targets)}"#.utf8))
        }
        let oldFullBody = try decode(#"{"legs": 10, "back": 10, "chest": 10, "shoulders": 8, "biceps": 6, "triceps": 6, "abdominals": 4, "cardio": 2}"#)
        XCTAssertEqual(oldFullBody.matchingPreset, .fullBody, "A Full Body user stays Full Body")
        XCTAssertEqual(oldFullBody.workoutsPerWeek, 3)
        XCTAssertTrue(oldFullBody.isExcluded(.cardio))

        let oldEndurance = try decode(#"{"legs": 10, "back": 6, "chest": 3, "shoulders": 3, "biceps": 2, "triceps": 2, "abdominals": 6, "cardio": 6}"#)
        XCTAssertEqual(oldEndurance.matchingPreset, .cardio)

        let custom = try decode(#"{"legs": 11, "back": 10, "chest": 10, "shoulders": 8, "biceps": 6, "triceps": 6, "abdominals": 4, "cardio": 2}"#)
        XCTAssertNil(custom.matchingPreset, "Hand-set targets are kept as they were")
        XCTAssertEqual(custom.target(for: .legs), 11)
        XCTAssertEqual(custom.target(for: .cardio), 2)
        XCTAssertEqual(custom.workoutsPerWeek, 3)
    }

    func testANewShapeFocusIsNeverRemapped() throws {
        // Current JSON that happens to hold the old Full Body numbers is a custom focus, not a migration.
        let json = #"{"targets": {"legs": 10, "back": 10, "chest": 10, "shoulders": 8, "biceps": 6, "triceps": 6, "abdominals": 4, "cardio": 2}, "workoutsPerWeek": 3}"#
        let focus = try JSONDecoder().decode(MuscleFocus.self, from: Data(json.utf8))
        XCTAssertNil(focus.matchingPreset)
        XCTAssertEqual(focus.target(for: .cardio), 2)
    }

    func testPriorityShapeDecodesToSets() throws {
        let json = #"{"priorities": {"legs": 3, "back": 2, "chest": 1}, "excluded": ["cardio"]}"#
        let focus = try JSONDecoder().decode(MuscleFocus.self, from: Data(json.utf8))
        XCTAssertEqual(focus.target(for: .legs), 10)
        XCTAssertEqual(focus.target(for: .back), 6)
        XCTAssertEqual(focus.target(for: .chest), 3)
        XCTAssertEqual(focus.target(for: .shoulders), 6, "A group missing from the priorities read as medium")
        XCTAssertEqual(focus.target(for: .cardio), 0)
        XCTAssertEqual(focus.workoutsPerWeek, 3)
    }

    func testLegacyPercentPresetsMigrateToTheirSuccessors() {
        let balanced: [MuscleGroup: Int] = [.legs: 20, .back: 18, .chest: 16, .shoulders: 13, .biceps: 9, .triceps: 9, .abdominals: 9, .cardio: 6]
        XCTAssertEqual(MuscleFocus(legacyPercentages: balanced).matchingPreset, .fullBody)
        let upper: [MuscleGroup: Int] = [.chest: 18, .back: 18, .shoulders: 16, .biceps: 13, .triceps: 13, .legs: 12, .abdominals: 6, .cardio: 4]
        XCTAssertEqual(MuscleFocus(legacyPercentages: upper).matchingPreset, .upperBody)
    }

    func testLegacyCustomPercentagesScaleOntoTheDefaultWeek() {
        let focus = MuscleFocus(legacyPercentages: [.legs: 50, .back: 49, .chest: 1])
        // 46 sets a week, split 50 / 49 / 1 %: the tiny share still keeps a set.
        XCTAssertEqual(focus.target(for: .legs), 23)
        XCTAssertEqual(focus.target(for: .back), 23)
        XCTAssertEqual(focus.target(for: .chest), 1)
        XCTAssertTrue(focus.isExcluded(.biceps), "A zeroed share stays out")
    }

    // MARK: Store

    private func makeDefaults(_ name: String, goal: Int? = nil) throws -> (UserDefaults, String) {
        let suite = "\(name)-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        if let goal {
            defaults.set(goal, forKey: MuscleFocusStore.workoutGoalKey)
        }
        return (defaults, suite)
    }

    func testStoreMigratesLegacySplitAndPersistsEdits() throws {
        let (defaults, suite) = try makeDefaults("MuscleFocusTests")
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacy = ["chest": 18, "back": 18, "shoulders": 16, "biceps": 13, "triceps": 13, "legs": 12, "abdominals": 6, "cardio": 4]
        defaults.set(try JSONEncoder().encode(legacy), forKey: MuscleFocusStore.legacyStorageKey)

        let store = MuscleFocusStore(defaults: defaults)
        XCTAssertEqual(store.focus.matchingPreset, .upperBody)
        XCTAssertTrue(store.hasChosenFocus, "Someone who tuned percentages made a choice")

        store.setTarget(0, for: .abdominals)
        let reloaded = MuscleFocusStore(defaults: defaults)
        XCTAssertTrue(reloaded.focus.isExcluded(.abdominals))
        XCTAssertNil(reloaded.focus.matchingPreset)
    }

    func testALegacySplitIsSizedForTheUsersOwnWeeklyGoal() throws {
        // The percent editor stored shares with no week attached. Read as a three-workout week, a
        // goal of 5 came out of the update a third short and was offered a rescale for a goal of 3
        // the user never set.
        let (defaults, suite) = try makeDefaults("MuscleFocusLegacyGoal", goal: 5)
        defer { defaults.removePersistentDomain(forName: suite) }
        let upper = ["chest": 18, "back": 18, "shoulders": 16, "biceps": 13, "triceps": 13, "legs": 12, "abdominals": 6, "cardio": 4]
        defaults.set(try JSONEncoder().encode(upper), forKey: MuscleFocusStore.legacyStorageKey)

        let store = MuscleFocusStore(defaults: defaults)
        XCTAssertEqual(store.focus, MuscleFocusPreset.upperBody.focus(forWorkoutsPerWeek: 5))
        XCTAssertNil(store.suggestedResizeGoal, "Nothing to offer: the targets already fit the goal")
    }

    func testALegacyCustomSplitScalesToTheWeeklyGoal() throws {
        let (defaults, suite) = try makeDefaults("MuscleFocusLegacyCustom", goal: 6)
        defer { defaults.removePersistentDomain(forName: suite) }
        let custom = ["legs": 50, "back": 49, "chest": 1]
        defaults.set(try JSONEncoder().encode(custom), forKey: MuscleFocusStore.legacyStorageKey)

        let store = MuscleFocusStore(defaults: defaults)
        XCTAssertEqual(store.focus.workoutsPerWeek, 6)
        XCTAssertEqual(store.focus.target(for: .legs), 40, "23 sets for 3 workouts doubles to 46, capped at 40")
        XCTAssertEqual(store.focus.target(for: .chest), 2)
        XCTAssertNil(store.suggestedResizeGoal)
    }

    func testStoreKnowsWhetherAFocusWasEverChosen() throws {
        let (defaults, suite) = try makeDefaults("MuscleFocusChosen")
        defer { defaults.removePersistentDomain(forName: suite) }

        let fresh = MuscleFocusStore(defaults: defaults)
        XCTAssertFalse(fresh.hasChosenFocus, "A new user runs on the default without having chosen it")

        // Settling on the preset already in force is still a choice, and it survives a relaunch.
        fresh.apply(preset: .fullBody)
        XCTAssertTrue(fresh.hasChosenFocus)
        XCTAssertTrue(MuscleFocusStore(defaults: defaults).hasChosenFocus)
    }

    func testTheDefaultFollowsTheWeeklyGoalUntilAFocusIsChosen() throws {
        let (defaults, suite) = try makeDefaults("MuscleFocusGoal", goal: 4)
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = MuscleFocusStore(defaults: defaults)
        XCTAssertEqual(store.focus, MuscleFocusPreset.fullBody.focus(forWorkoutsPerWeek: 4))
        XCTAssertNil(store.suggestedResizeGoal, "Nothing to offer before a choice — the default already follows")

        defaults.set(2, forKey: MuscleFocusStore.workoutGoalKey)
        store.reloadWorkoutGoal()
        XCTAssertEqual(store.focus, MuscleFocusPreset.fullBody.focus(forWorkoutsPerWeek: 2))

        defaults.set(-1, forKey: MuscleFocusStore.workoutGoalKey)
        store.reloadWorkoutGoal()
        XCTAssertNil(store.workoutGoal)
        XCTAssertEqual(store.focus, MuscleFocus.default, "No goal: the base week")
    }

    func testAChosenFocusOnlyOffersToFollowTheGoal() throws {
        let (defaults, suite) = try makeDefaults("MuscleFocusResize", goal: 3)
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = MuscleFocusStore(defaults: defaults)
        store.apply(preset: .upperBody)
        XCTAssertEqual(store.focus, MuscleFocusPreset.upperBody.focus(forWorkoutsPerWeek: 3))

        defaults.set(5, forKey: MuscleFocusStore.workoutGoalKey)
        store.reloadWorkoutGoal()
        XCTAssertEqual(store.focus, MuscleFocusPreset.upperBody.focus(forWorkoutsPerWeek: 3), "Never moved by itself")
        XCTAssertEqual(store.suggestedResizeGoal, 5)

        store.keepTargetsForWorkoutGoal()
        XCTAssertNil(store.suggestedResizeGoal)
        XCTAssertNil(MuscleFocusStore(defaults: defaults).suggestedResizeGoal, "Not Now survives a relaunch")

        defaults.set(6, forKey: MuscleFocusStore.workoutGoalKey)
        store.reloadWorkoutGoal()
        XCTAssertEqual(store.suggestedResizeGoal, 6)
        store.resizeToWorkoutGoal()
        XCTAssertEqual(store.focus, MuscleFocusPreset.upperBody.focus(forWorkoutsPerWeek: 6))
        XCTAssertNil(store.suggestedResizeGoal)

        // A preset chosen later is sized for the goal in force.
        store.apply(preset: .cardio)
        XCTAssertEqual(store.focus.workoutsPerWeek, 6)
    }

    // MARK: Balance entries

    func testEntryVerdictsReadWholeWeeklySets() {
        func state(_ setsPerWeek: Int, target: Int) -> MuscleBalanceGoalState {
            MuscleBalanceEntry(muscleGroup: .legs, setCount: 0, setsPerWeek: setsPerWeek, target: target).goalState
        }
        XCTAssertEqual(state(9, target: 10), .under)
        XCTAssertEqual(state(10, target: 10), .met)
        XCTAssertEqual(state(11, target: 10), .over, "One set past the target is already above it")
        XCTAssertNil(MuscleBalanceEntry(muscleGroup: .legs, setCount: 3, setsPerWeek: 3, target: 0).goalFraction)
    }

    func testTheRecommendationLeadsWithTheGroupsFurthestBehind() {
        func entry(_ group: MuscleGroup, _ setsPerWeek: Int, _ target: Int) -> MuscleBalanceEntry {
            MuscleBalanceEntry(muscleGroup: group, setCount: setsPerWeek * 4, setsPerWeek: setsPerWeek, target: target)
        }
        let calculator = MuscleBalanceCalculator(entries: [
            entry(.chest, 12, 10), entry(.triceps, 5, 6), entry(.shoulders, 8, 8), entry(.biceps, 6, 6),
            entry(.back, 7, 10), entry(.legs, 4, 10), entry(.abdominals, 4, 4), entry(.cardio, 1, 2),
        ])
        // Short by sets (legs 6, back 3), then the two one-set gaps by fill (cardio ½ before triceps ⅚),
        // then at target in display order, then past it.
        XCTAssertEqual(
            calculator.rankedEntries.map(\.muscleGroup),
            [.legs, .back, .cardio, .triceps, .shoulders, .biceps, .abdominals, .chest]
        )
        XCTAssertEqual(calculator.namedFocusEntries.map(\.muscleGroup), [.legs, .back])
        XCTAssertEqual(calculator.unnamedFocusCount, 2)
        XCTAssertEqual(calculator.rankedEntries.first?.setsShort, 6)
        XCTAssertEqual(calculator.rankedEntries.last?.setsOver, 2)
    }

    func testAnUntrainedGroupRanksByItsWholeTargetAndAnOffGroupNeverRanks() {
        let calculator = MuscleBalanceCalculator(entries: [
            MuscleBalanceEntry(muscleGroup: .legs, setCount: 0, setsPerWeek: 0, target: 8),
            MuscleBalanceEntry(muscleGroup: .back, setCount: 20, setsPerWeek: 5, target: 10),
            MuscleBalanceEntry(muscleGroup: .cardio, setCount: 0, setsPerWeek: 0, target: 0),
            MuscleBalanceEntry(muscleGroup: .chest, setCount: 40, setsPerWeek: 10, target: 10),
        ])
        XCTAssertEqual(calculator.focusEntries.map(\.muscleGroup), [.legs, .back])
        XCTAssertEqual(calculator.unnamedFocusCount, 0)
        XCTAssertFalse(calculator.rankedEntries.contains { $0.muscleGroup == .cardio })
        XCTAssertEqual(calculator.excludedEntries.map(\.muscleGroup), [.cardio])
    }

    func testNothingIsRecommendedOnceEveryGroupIsAtTarget() {
        let calculator = MuscleBalanceCalculator(entries: [
            MuscleBalanceEntry(muscleGroup: .legs, setCount: 40, setsPerWeek: 10, target: 10),
            MuscleBalanceEntry(muscleGroup: .back, setCount: 48, setsPerWeek: 12, target: 10),
        ])
        XCTAssertTrue(calculator.focusEntries.isEmpty)
        XCTAssertTrue(calculator.namedFocusEntries.isEmpty)
    }

    func testWeeksCoveredCapsAtTheHistoryAndNeverDropsBelowOneWeek() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let day: TimeInterval = 24 * 60 * 60
        XCTAssertEqual(TrendWindow.fourWeeks.weeksCovered(firstDataDate: nil, from: now), 4, accuracy: 0.01)
        XCTAssertEqual(TrendWindow.fourWeeks.weeksCovered(firstDataDate: now.addingTimeInterval(-400 * day), from: now), 4, accuracy: 0.01)
        XCTAssertEqual(TrendWindow.fourWeeks.weeksCovered(firstDataDate: now.addingTimeInterval(-14 * day), from: now), 2, accuracy: 0.01)
        XCTAssertEqual(TrendWindow.fourWeeks.weeksCovered(firstDataDate: now.addingTimeInterval(-2 * day), from: now), 1, accuracy: 0.01)
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

    /// …and an untrained bin cannot be inspected either. A tap or a drag landing on a gap snaps to the
    /// nearest trained bar in view, never to a card reading "0" hanging over empty space — and a tap
    /// between thin bars still selects something instead of doing nothing.
    func testUntrainedBinsSnapToTheNearestTrainedBar() {
        let window = TrendWindow.fourWeeks
        let ranges = window.binRanges(count: 28, now: date(2026, 8, 12))
        let bins = TrendWindowBin.strip(
            for: window,
            ranges: ranges,
            raw: ranges.enumerated().map { index, _ in index % 2 == 0 ? 0 : 1000 },
            display: { $0 },
            formatted: { String(Int($0)) }
        )
        let everything = 0 ..< bins.count
        for bin in bins {
            // The point the gesture reports is anywhere in the bin's slot, not its exact start.
            let insideTheSlot = bin.stripDate.addingTimeInterval(3600 * 7)
            let selected = TrendWindowBin.selectableIndex(at: insideTheSlot, in: bins, within: everything)
            if bin.value > 0 {
                XCTAssertEqual(selected, bin.index, "trained bin \(bin.index) should select itself")
            } else {
                // Rest days sit between two trained neighbours; a tie goes to the earlier one, and the
                // first bin has only the one after it.
                let expected = bin.index == 0 ? 1 : bin.index - 1
                XCTAssertEqual(selected, expected, "untrained bin \(bin.index) should snap to \(expected)")
            }
        }
        // Off either end of the strip there is nothing to select.
        XCTAssertNil(TrendWindowBin.selectableIndex(at: TrendWindow.stripDate(forIndex: -1), in: bins, within: everything))
        XCTAssertNil(TrendWindowBin.selectableIndex(at: TrendWindow.stripDate(forIndex: 28), in: bins, within: everything))
        // The snap never reaches past the bins in view: a gap at the edge of the viewport picks the
        // nearest bar *inside* it, even when a closer one sits just out of sight.
        XCTAssertEqual(
            TrendWindowBin.selectableIndex(at: TrendWindow.stripDate(forIndex: 10), in: bins, within: 10 ..< 20),
            11
        )
        // …and a viewport of nothing but rest days selects nothing.
        XCTAssertNil(TrendWindowBin.selectableIndex(at: TrendWindow.stripDate(forIndex: 4), in: bins, within: 4 ..< 5))
    }
}
