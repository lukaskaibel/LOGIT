//
//  RecorderTopSheetModelTests.swift
//  LOGITTests
//
//  The recorder top sheet's fold rules: how the list's scroll opens and closes it, and how
//  measurements move its stops. These are the rules the old in-flow header kept breaking.
//

import XCTest

@testable import LOGIT

final class RecorderTopSheetModelTests: XCTestCase {
    private let actions: CGFloat = 70
    private let panel: CGFloat = 230

    /// A measured, bootstrapped sheet with the list at `offset`.
    private func makeSheet(offset: CGFloat = 0) -> RecorderTopSheetModel {
        let sheet = RecorderTopSheetModel()
        sheet.scrollDidChange(to: offset, isFrozen: false)
        sheet.closedHeight = 73
        sheet.containerDidMeasure(800)
        sheet.actionsDidMeasure(actions)
        sheet.panelDidMeasure(panel)
        return sheet
    }

    // MARK: - Bootstrap

    func testFreshWorkoutOpensAtTheActionsStop() {
        let sheet = makeSheet(offset: 0)
        XCTAssertEqual(sheet.reveal, actions)
        XCTAssertFalse(sheet.summaryIsRevealed, "The note must not be out when a workout starts")
    }

    func testResumedWorkoutScrolledIntoItsSetsOpensClosed() {
        let sheet = makeSheet(offset: 900)
        XCTAssertEqual(sheet.reveal, 0)
    }

    // MARK: - Scrolling

    func testScrollingDownFromTheTopFoldsInLockStep() {
        let sheet = makeSheet()
        sheet.scrollDidChange(to: 30, isFrozen: false)
        XCTAssertEqual(sheet.reveal, actions - 30)
        sheet.scrollDidChange(to: 200, isFrozen: false)
        XCTAssertEqual(sheet.reveal, 0)
    }

    func testScrollingBackToTheTopBringsTheActionsBack() {
        let sheet = makeSheet()
        sheet.scrollDidChange(to: 300, isFrozen: false)
        sheet.scrollDidChange(to: 20, isFrozen: false)
        XCTAssertEqual(sheet.reveal, actions - 20)
        sheet.scrollDidChange(to: 0, isFrozen: false)
        XCTAssertEqual(sheet.reveal, actions)
    }

    func testASmallScrollUpDeepInTheListBringsNothingBack() {
        let sheet = makeSheet()
        sheet.scrollDidChange(to: 600, isFrozen: false)
        sheet.scrollDidChange(to: 540, isFrozen: false)
        XCTAssertEqual(sheet.reveal, 0)
    }

    /// The reported bug: open the sheet mid-list, scroll down, and it must fold — never grow first.
    func testOpenedMidListScrollingDownOnlyEverFolds() {
        let sheet = makeSheet(offset: actions)
        XCTAssertEqual(sheet.reveal, 0)
        sheet.reveal = actions // opened by a tap
        var previous = sheet.reveal
        for offset in stride(from: actions + 5, through: actions + 120, by: 5) {
            sheet.scrollDidChange(to: offset, isFrozen: false)
            XCTAssertLessThanOrEqual(sheet.reveal, previous, "Expanded while scrolling down at offset \(offset)")
            previous = sheet.reveal
        }
        XCTAssertEqual(sheet.reveal, 0)
    }

    func testRubberBandingAtTheTopDoesNotFold() {
        let sheet = makeSheet()
        sheet.scrollDidChange(to: -40, isFrozen: false)
        sheet.scrollDidChange(to: -10, isFrozen: false)
        sheet.scrollDidChange(to: 0, isFrozen: false)
        XCTAssertEqual(sheet.reveal, actions)
    }

    func testBouncingAtTheBottomDoesNotReopen() {
        let sheet = makeSheet()
        sheet.scrollDidChange(to: 1_000, isFrozen: false)
        sheet.scrollDidChange(to: 1_060, isFrozen: false)
        sheet.scrollDidChange(to: 1_000, isFrozen: false)
        XCTAssertEqual(sheet.reveal, 0)
    }

    func testTheSummaryStopFoldsFromWhereverItIs() {
        let sheet = makeSheet()
        sheet.reveal = panel
        sheet.scrollDidChange(to: 100, isFrozen: false)
        XCTAssertEqual(sheet.reveal, panel - 100)
    }

    func testAFrozenOrDraggedSheetIgnoresTheScroll() {
        let sheet = makeSheet()
        sheet.scrollDidChange(to: 50, isFrozen: true)
        XCTAssertEqual(sheet.reveal, actions)
        sheet.isDragging = true
        sheet.scrollDidChange(to: 120, isFrozen: false)
        XCTAssertEqual(sheet.reveal, actions)
        sheet.isDragging = false
        // The baseline moved with the ignored scrolls, so letting go does not replay them.
        sheet.scrollDidChange(to: 125, isFrozen: false)
        XCTAssertEqual(sheet.reveal, actions - 5)
    }

    // MARK: - Measurement

    /// The first layout pass can measure the actions at a narrower width, taller. The sheet must stay
    /// at the actions stop as it settles, not keep the taller reveal and show the note.
    func testTheRestingStopSurvivesTheActionsBeingRemeasured() {
        let sheet = RecorderTopSheetModel()
        sheet.actionsDidMeasure(140)
        sheet.panelDidMeasure(300)
        XCTAssertEqual(sheet.reveal, 140)
        sheet.actionsDidMeasure(actions)
        sheet.panelDidMeasure(panel)
        XCTAssertEqual(sheet.reveal, actions)
        XCTAssertFalse(sheet.summaryIsRevealed)
    }

    func testLoggingTheFirstSetDoesNotGrowTheSheet() {
        let sheet = makeSheet()
        sheet.panelDidMeasure(panel + 80) // the tiles appear
        XCTAssertEqual(sheet.reveal, actions)
    }

    func testRestingAllTheWayOutStaysAllTheWayOut() {
        let sheet = makeSheet()
        sheet.reveal = panel
        sheet.panelDidMeasure(panel + 80)
        XCTAssertEqual(sheet.reveal, panel + 80)
    }

    // MARK: - Stops

    func testReleaseSnapsToTheNearestStopOrFlingsToTheNext() {
        let sheet = makeSheet()
        XCTAssertEqual(sheet.stops, [0, actions, panel])
        XCTAssertEqual(sheet.stop(nearestTo: 50, velocity: 0), actions)
        XCTAssertEqual(sheet.stop(nearestTo: 50, velocity: 900), actions, "A fling goes one stop on, not to the end")
        XCTAssertEqual(sheet.stop(nearestTo: 100, velocity: 900), panel)
        XCTAssertEqual(sheet.stop(nearestTo: 50, velocity: -900), 0)
        XCTAssertEqual(sheet.stop(nearestTo: 200, velocity: 0), panel)
        XCTAssertEqual(sheet.stop(nearestTo: 200, velocity: -900), actions)
    }

    func testTheFinishStopRunsToTheBottomOfTheContainer() {
        let sheet = makeSheet()
        XCTAssertEqual(sheet.fullReveal, 800 - 73)
    }

    func testRubberBandStretchesPastTheLastStopButNeverAboveTheRow() {
        XCTAssertEqual(RecorderTopSheetModel.rubberBand(-20, upper: panel), 0)
        XCTAssertEqual(RecorderTopSheetModel.rubberBand(100, upper: panel), 100)
        let stretched = RecorderTopSheetModel.rubberBand(panel + 200, upper: panel)
        XCTAssertGreaterThan(stretched, panel)
        XCTAssertLessThan(stretched, panel + 40)
    }
}

// MARK: - Finish panel recap

/// The finish panel's recap: which week a workout counts in, how the goal moves, when a
/// finish earns its celebration, and that records and improvements never list an exercise twice.
final class WorkoutRecapTests: XCTestCase {
    private var database: Database!
    private var builder: TestDataBuilder!
    private let calendar = Calendar.current

    /// A Wednesday at noon, so every "earlier this week" and "last week" below is unambiguous
    /// whatever day the suite runs on.
    private lazy var workoutDate: Date = {
        let week = Date.now.startOfWeek
        return calendar.date(byAdding: .hour, value: 2 * 24 + 12, to: week)!
    }()

    override func setUp() {
        super.setUp()
        database = Database(inMemory: true)
        builder = TestDataBuilder(database: database)
    }

    override func tearDown() {
        database = nil
        builder = nil
        super.tearDown()
    }

    // MARK: Helpers

    private func day(_ offset: Int, from date: Date? = nil) -> Date {
        calendar.date(byAdding: .day, value: offset, to: date ?? workoutDate)!
    }

    /// A finished workout with one logged set per exercise.
    @discardableResult
    private func finishedWorkout(on date: Date, _ sets: [(Exercise, reps: Int, grams: Int)] = []) -> Workout {
        let workout = database.newWorkout(name: "Past", date: date)
        let entries = sets.isEmpty ? [(builder.createExercise(name: "Filler"), reps: 10, grams: 20000)] : sets
        for (exercise, reps, grams) in entries {
            let group = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: exercise, workout: workout)
            database.newStandardSet(repetitions: reps, weight: grams, setGroup: group)
        }
        return workout
    }

    /// The in-progress workout being finished.
    private func currentWorkout(_ sets: [(Exercise, reps: Int, grams: Int)]) -> Workout {
        let workout = finishedWorkout(on: workoutDate, sets)
        workout.name = "Current"
        workout.isCurrentWorkout = true
        return workout
    }

    // MARK: The week

    func testTheWeekCountsFinishedWorkoutsBeforeThisOne() {
        finishedWorkout(on: day(-1))
        finishedWorkout(on: day(-2))
        let current = currentWorkout([(builder.createExercise(), reps: 10, grams: 50000)])

        let recap = WorkoutRecap.compute(for: current, database: database)

        XCTAssertEqual(recap.weekCountBefore, 2)
        XCTAssertEqual(recap.weekCountAfter, 3)
        let goal = recap.goal(target: 3)
        XCTAssertEqual(goal?.countBefore, 2)
        XCTAssertEqual(goal?.countAfter, 3)
        XCTAssertEqual(goal?.isReachedByThisWorkout, true)
        XCTAssertEqual(goal?.remaining, 0)
        XCTAssertEqual(goal?.progressBefore ?? 0, 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(goal?.progressAfter, 1)
    }

    func testEmptyWorkoutsAndOtherWeeksDontCount() {
        _ = database.newWorkout(name: "Empty", date: day(-1)) // no set groups
        finishedWorkout(on: day(-7)) // last week
        let current = currentWorkout([(builder.createExercise(), reps: 10, grams: 50000)])

        let recap = WorkoutRecap.compute(for: current, database: database)

        XCTAssertEqual(recap.weekCountBefore, 0)
        XCTAssertEqual(recap.weekWorkouts.count, 0)
        XCTAssertNil(recap.goal(target: 0), "No goal set means no goal to report")
        XCTAssertEqual(recap.goal(target: 4)?.remaining, 3)
    }

    func testAnAlreadyMetWeekReportsTheExtraWorkout() {
        finishedWorkout(on: day(-1))
        finishedWorkout(on: day(-2))
        let current = currentWorkout([(builder.createExercise(), reps: 10, grams: 50000)])

        let goal = WorkoutRecap.compute(for: current, database: database).goal(target: 2)

        XCTAssertEqual(goal?.wasAlreadyMet, true)
        XCTAssertEqual(goal?.isReachedByThisWorkout, false)
        XCTAssertEqual(goal?.beyond, 1)
    }

    // MARK: Records, improvements, celebration

    func testRecordsAndImprovementsNeverListAnExerciseTwice() {
        let bench = builder.createExercise(name: "Bench", muscleGroup: .chest)
        let row = builder.createExercise(name: "Row", muscleGroup: .back)
        let curl = builder.createExercise(name: "Curl", muscleGroup: .biceps)
        // Bench: beaten outright — a record, and so not repeated under the improvements.
        finishedWorkout(on: day(-7), [(bench, reps: 5, grams: 100_000)])
        // Row: heavier two months ago than today, but better than anything this month.
        finishedWorkout(on: day(-60), [(row, reps: 8, grams: 120_000)])
        finishedWorkout(on: day(-10), [(row, reps: 5, grams: 100_000)])
        let current = currentWorkout([
            (bench, reps: 5, grams: 105_000),
            (row, reps: 6, grams: 110_000),
            (curl, reps: 10, grams: 15000), // first session ever
        ])

        let recap = WorkoutRecap.compute(for: current, database: database)

        XCTAssertEqual(recap.records.map { $0.exercise.name }, ["Bench"])
        XCTAssertEqual(recap.improvements.map { $0.exercise.name }, ["Row"])
        XCTAssertEqual(recap.firstSessionCount, 1)
        XCTAssertTrue(recap.celebrates(target: 0), "A record earns the celebration on its own")
    }

    func testAnImprovementShowsTheWeightWhenItAlsoWentUp() {
        let press = builder.createExercise(name: "Press", muscleGroup: .shoulders)
        let curl = builder.createExercise(name: "Curl", muscleGroup: .biceps)
        // Two months ago both were heavier than anything this month, so neither is a record.
        finishedWorkout(on: day(-60), [(press, reps: 8, grams: 70000), (curl, reps: 12, grams: 20000)])
        finishedWorkout(on: day(-10), [(press, reps: 5, grams: 50000), (curl, reps: 8, grams: 15000)])
        // Press: more weight AND a better estimate → the weight is what's shown.
        // Curl: the same weight for more reps → only the estimate moved, so Strength as a percent.
        let current = currentWorkout([(press, reps: 5, grams: 55000), (curl, reps: 10, grams: 15000)])

        let recap = WorkoutRecap.compute(for: current, database: database)
        let shown = Dictionary(uniqueKeysWithValues: recap.improvements.map {
            ($0.exercise.name ?? "", recap.displayedTrend(for: $0))
        })

        XCTAssertEqual(shown["Press"]?.metric, .weight)
        XCTAssertEqual(shown["Press"]?.current, 55000)
        XCTAssertEqual(shown["Press"]?.baseline, 50000)
        XCTAssertEqual(shown["Curl"]?.metric, .estimatedOneRepMax)
        XCTAssertEqual(recap.report.weightTrends.count, 2, "Every Strength-scored exercise gets a weight comparison")
    }

    func testAStrengthOnlyRecordIsAnImprovementNotARecord() {
        let press = builder.createExercise(name: "Press", muscleGroup: .shoulders)
        // Best weight 100 kg (for 5), best reps 12 (at 60 kg): 95 kg for 10 beats neither, but its
        // estimate (126.7 kg) beats every earlier one (116.7 kg).
        finishedWorkout(on: day(-14), [(press, reps: 5, grams: 100_000)])
        finishedWorkout(on: day(-7), [(press, reps: 12, grams: 60000)])
        let current = currentWorkout([(press, reps: 10, grams: 95000)])

        let recap = WorkoutRecap.compute(for: current, database: database)

        XCTAssertEqual(recap.report.exerciseRecords.map { $0.lead.metric }, [.estimatedOneRepMax], "The report still counts the estimate")
        XCTAssertTrue(recap.records.isEmpty, "The finish panel does not call an estimate a record")
        XCTAssertEqual(recap.improvements.map { $0.exercise.name }, ["Press"])
        XCTAssertEqual(recap.displayedTrend(for: recap.improvements[0]).metric, .estimatedOneRepMax, "No weight gain, so Strength as a percent")
        XCTAssertFalse(recap.celebrates(target: 0), "An estimate moving doesn't earn the confetti on its own")
    }

    func testAnOrdinaryFinishDoesNotCelebrate() {
        let squat = builder.createExercise(name: "Squat", muscleGroup: .legs)
        finishedWorkout(on: day(-7), [(squat, reps: 5, grams: 140_000)])
        let current = currentWorkout([(squat, reps: 5, grams: 120_000)])

        let recap = WorkoutRecap.compute(for: current, database: database)

        XCTAssertTrue(recap.records.isEmpty)
        XCTAssertFalse(recap.celebrates(target: 3), "One of three workouts: the week moved, nothing was won")
        XCTAssertFalse(recap.celebrates(target: 1), "Winning the week is the arc's moment, not the confetti's")
        XCTAssertEqual(recap.goal(target: 1)?.isReachedByThisWorkout, true)
    }

    func testTheCelebrationKeyIsStableUntilSomethingChanges() {
        let press = builder.createExercise(name: "Press", muscleGroup: .shoulders)
        finishedWorkout(on: day(-7), [(press, reps: 5, grams: 50000)])
        let current = currentWorkout([(press, reps: 5, grams: 52500)])

        let first = WorkoutRecap.compute(for: current, database: database)
        let second = WorkoutRecap.compute(for: current, database: database)
        XCTAssertEqual(first.celebrationKey(target: 3), second.celebrationKey(target: 3))

        current.setGroups.first?.sets.first?.entries.first?.weight = 55000
        let changed = WorkoutRecap.compute(for: current, database: database)
        XCTAssertNotEqual(first.celebrationKey(target: 3), changed.celebrationKey(target: 3))
    }

    func testTheCascadeLandsRowsOneAfterAnother() {
        XCTAssertEqual(FinishRevealTiming.total(rowCount: 0), 0)
        XCTAssertGreaterThan(FinishRevealTiming.rowDelay(index: 2), FinishRevealTiming.rowDelay(index: 1))
        XCTAssertGreaterThan(
            FinishRevealTiming.total(rowCount: 3),
            FinishRevealTiming.rowDelay(index: 2) + FinishRevealTiming.rollAfterRow,
            "The cascade ends after the last row has landed and rolled"
        )
    }

    func testHighlightsListRecordsBeforeImprovements() {
        let bench = builder.createExercise(name: "Bench", muscleGroup: .chest)
        let row = builder.createExercise(name: "Row", muscleGroup: .back)
        finishedWorkout(on: day(-7), [(bench, reps: 5, grams: 100_000)])
        finishedWorkout(on: day(-60), [(row, reps: 8, grams: 120_000)])
        finishedWorkout(on: day(-10), [(row, reps: 5, grams: 100_000)])
        let current = currentWorkout([(row, reps: 6, grams: 110_000), (bench, reps: 5, grams: 105_000)])

        let recap = WorkoutRecap.compute(for: current, database: database)

        XCTAssertEqual(recap.highlights.map { $0.exercise.name }, ["Bench", "Row"], "Records first, whatever the order in the workout")
        XCTAssertEqual(recap.highlights.map(\.isRecord), [true, false])
        XCTAssertEqual(recap.highlights.first?.metric, .weight)
        XCTAssertEqual(recap.highlights.first?.previous, 100_000)
        XCTAssertEqual(recap.highlights.first?.current, 105_000)
    }

    func testRevealPhasesRunTopToBottom() {
        let phases: [FinishRevealPhase] = [.hidden, .hero, .heroFilled, .heroSettled, .achievements, .details, .done]
        XCTAssertEqual(phases, phases.sorted())
    }
}
