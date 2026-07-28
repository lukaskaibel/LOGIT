//
//  VolumeCalculatingTests.swift
//  LOGITTests
//
//  Tests for volume calculation utilities
//

import XCTest

@testable import LOGIT

final class VolumeCalculatingTests: XCTestCase {
    
    private var database: Database!
    private var builder: TestDataBuilder!
    private var userDefaultsHelper: UserDefaultsTestHelper!
    
    override func setUp() {
        super.setUp()
        database = Database(isPreview: true)
        builder = TestDataBuilder(database: database)
        userDefaultsHelper = UserDefaultsTestHelper()
        // Set to kg for consistent testing
        userDefaultsHelper.setTestValue("kg", forKey: "weightUnit")
    }
    
    override func tearDown() {
        userDefaultsHelper.restoreAll()
        database = nil
        builder = nil
        super.tearDown()
    }
    
    // MARK: - Standard Set Volume Tests
    
    func testVolumeOfEmptyArray() {
        let volume = getVolume(of: [WorkoutSet]())
        XCTAssertEqual(volume, 0, "Volume of empty array should be 0")
    }
    
    func testVolumeOfSingleStandardSet() {
        let exercise = builder.createExercise(name: "Bench Press", muscleGroup: .chest)
        let standardSet = builder.createStandardSet(
            repetitions: 10,
            weight: 50000,  // 50 kg in grams
            exercise: exercise
        )
        
        let volume = getVolume(of: [standardSet])
        XCTAssertEqual(volume, 10 * 50000, "Volume should be reps * weight")
    }
    
    func testVolumeOfMultipleStandardSets() {
        let exercise = builder.createExercise(name: "Bench Press", muscleGroup: .chest)
        let workout = database.newWorkout(name: "Test")
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: exercise,
            workout: workout
        )
        
        let set1 = database.newStandardSet(repetitions: 10, weight: 50000, setGroup: setGroup)
        let set2 = database.newStandardSet(repetitions: 8, weight: 55000, setGroup: setGroup)
        let set3 = database.newStandardSet(repetitions: 6, weight: 60000, setGroup: setGroup)
        
        let volume = getVolume(of: [set1, set2, set3])
        let expected = (10 * 50000) + (8 * 55000) + (6 * 60000)
        XCTAssertEqual(volume, expected, "Volume should be sum of all sets")
    }
    
    // MARK: - Drop Set Volume Tests
    
    func testVolumeOfDropSet() {
        let exercise = builder.createExercise(name: "Curls", muscleGroup: .biceps)
        let dropSet = builder.createDropSet(
            drops: [
                (reps: 10, weight: 20000),  // 10 * 20kg
                (reps: 8, weight: 15000),   // 8 * 15kg
                (reps: 6, weight: 10000)    // 6 * 10kg
            ],
            exercise: exercise
        )
        
        let volume = getVolume(of: [dropSet])
        let expected = (10 * 20000) + (8 * 15000) + (6 * 10000)
        XCTAssertEqual(volume, expected, "Drop set volume should sum all drops")
    }
    
    func testVolumeOfDropSetWithSingleDrop() {
        let dropSet = builder.createDropSet(
            drops: [(reps: 10, weight: 50000)]
        )
        
        let volume = getVolume(of: [dropSet])
        XCTAssertEqual(volume, 10 * 50000, "Single drop should work like standard set")
    }
    
    // MARK: - Super Set Volume Tests
    
    func testVolumeOfSuperSet() {
        let exercise1 = builder.createExercise(name: "Curls", muscleGroup: .biceps)
        let exercise2 = builder.createExercise(name: "Tricep Extension", muscleGroup: .biceps)
        
        let superSet = builder.createSuperSet(
            repsFirst: 10,
            repsSecond: 12,
            weightFirst: 20000,
            weightSecond: 15000,
            firstExercise: exercise1,
            secondExercise: exercise2
        )
        
        let volume = getVolume(of: [superSet])
        let expected = (10 * 20000) + (12 * 15000)
        XCTAssertEqual(volume, expected, "Super set volume should include both exercises")
    }
    
    // MARK: - Volume For Exercise Tests
    
    /// Tests that getVolume(of:for exercise:) correctly filters sets by exercise
    func testVolumeForSpecificExercise() {
        let benchPress = builder.createExercise(name: "Bench Press", muscleGroup: .chest)
        let squat = builder.createExercise(name: "Squat", muscleGroup: .legs)
        
        let workout = database.newWorkout(name: "Test")
        
        let benchGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: benchPress,
            workout: workout
        )
        let set1 = database.newStandardSet(repetitions: 10, weight: 50000, setGroup: benchGroup)
        
        let squatGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: squat,
            workout: workout
        )
        let set2 = database.newStandardSet(repetitions: 8, weight: 80000, setGroup: squatGroup)
        
        let benchVolume = getVolume(of: [set1, set2], for: benchPress)
        let squatVolume = getVolume(of: [set1, set2], for: squat)
        
        // Should only count volume for the specified exercise
        XCTAssertEqual(benchVolume, 10 * 50000, "Should only count bench press volume")
        XCTAssertEqual(squatVolume, 8 * 80000, "Should only count squat volume")
    }
    
    /// Tests that volume for exercise correctly filters DropSets
    func testVolumeForExerciseWithDropSet() {
        let curls = builder.createExercise(name: "Curls", muscleGroup: .biceps)
        let benchPress = builder.createExercise(name: "Bench Press", muscleGroup: .chest)
        
        let curlDropSet = builder.createDropSet(
            drops: [(reps: 10, weight: 20000), (reps: 8, weight: 15000)],
            exercise: curls
        )
        let benchDropSet = builder.createDropSet(
            drops: [(reps: 10, weight: 50000)],
            exercise: benchPress
        )
        
        let curlVolume = getVolume(of: [curlDropSet, benchDropSet], for: curls)
        let benchVolume = getVolume(of: [curlDropSet, benchDropSet], for: benchPress)
        
        XCTAssertEqual(curlVolume, (10 * 20000) + (8 * 15000), "Should only count curl drop set volume")
        XCTAssertEqual(benchVolume, 10 * 50000, "Should only count bench press drop set volume")
    }
    
    func testVolumeForExerciseInSuperSet() {
        let curls = builder.createExercise(name: "Curls", muscleGroup: .biceps)
        let triceps = builder.createExercise(name: "Triceps", muscleGroup: .biceps)
        
        let workout = database.newWorkout(name: "Test")
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: curls,
            workout: workout
        )
        setGroup.secondaryExercise = triceps
        
        let superSet = database.newSuperSet(
            repetitionsFirstExercise: 10,
            repetitionsSecondExercise: 12,
            weightFirstExercise: 20000,
            weightSecondExercise: 15000,
            setGroup: setGroup
        )
        
        let curlsVolume = getVolume(of: [superSet], for: curls)
        let tricepsVolume = getVolume(of: [superSet], for: triceps)
        
        XCTAssertEqual(curlsVolume, 10 * 20000, "Should only count curls in super set")
        XCTAssertEqual(tricepsVolume, 12 * 15000, "Should only count triceps in super set")
    }
    
    // MARK: - Volume For Muscle Group Tests
    
    func testVolumeForMuscleGroup() {
        let benchPress = builder.createExercise(name: "Bench Press", muscleGroup: .chest)
        let squat = builder.createExercise(name: "Squat", muscleGroup: .legs)
        
        let workout = database.newWorkout(name: "Test")
        
        let chestGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: benchPress,
            workout: workout
        )
        let set1 = database.newStandardSet(repetitions: 10, weight: 50000, setGroup: chestGroup)
        
        let legGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: squat,
            workout: workout
        )
        let set2 = database.newStandardSet(repetitions: 8, weight: 80000, setGroup: legGroup)
        
        let chestVolume = getVolume(of: [set1, set2], for: MuscleGroup.chest)
        let legVolume = getVolume(of: [set1, set2], for: MuscleGroup.legs)
        let backVolume = getVolume(of: [set1, set2], for: MuscleGroup.back)
        
        XCTAssertEqual(chestVolume, 10 * 50000)
        XCTAssertEqual(legVolume, 8 * 80000)
        XCTAssertEqual(backVolume, 0, "Should be 0 for muscle group with no exercises")
    }
    
    func testVolumeForMuscleGroupInSuperSet() {
        let curls = builder.createExercise(name: "Curls", muscleGroup: .biceps)
        let facePulls = builder.createExercise(name: "Face Pulls", muscleGroup: .shoulders)
        
        let workout = database.newWorkout(name: "Test")
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: curls,
            workout: workout
        )
        setGroup.secondaryExercise = facePulls
        
        let superSet = database.newSuperSet(
            repetitionsFirstExercise: 10,
            repetitionsSecondExercise: 15,
            weightFirstExercise: 20000,
            weightSecondExercise: 10000,
            setGroup: setGroup
        )
        
        let armsVolume = getVolume(of: [superSet], for: MuscleGroup.biceps)
        let shoulderVolume = getVolume(of: [superSet], for: MuscleGroup.shoulders)
        
        XCTAssertEqual(armsVolume, 10 * 20000)
        XCTAssertEqual(shoulderVolume, 15 * 10000)
    }
    
    // MARK: - Edge Cases
    
    func testVolumeWithZeroWeight() {
        let standardSet = builder.createStandardSet(repetitions: 10, weight: 0)
        let volume = getVolume(of: [standardSet])
        XCTAssertEqual(volume, 0, "Volume with zero weight should be 0")
    }
    
    func testVolumeWithZeroReps() {
        let standardSet = builder.createStandardSet(repetitions: 0, weight: 50000)
        let volume = getVolume(of: [standardSet])
        XCTAssertEqual(volume, 0, "Volume with zero reps should be 0")
    }
    
    func testVolumeWithBothZero() {
        let standardSet = builder.createStandardSet(repetitions: 0, weight: 0)
        let volume = getVolume(of: [standardSet])
        XCTAssertEqual(volume, 0, "Volume with both zero should be 0")
    }
    
    func testVolumeWithHighValues() {
        // Test with very high but realistic values
        // 20 reps * 500kg = 10,000 kg volume (stored as grams: 500,000,000)
        let standardSet = builder.createStandardSet(repetitions: 20, weight: 500000)  // 500 grams (0.5 kg)
        let volume = getVolume(of: [standardSet])
        XCTAssertEqual(volume, 20 * 500000)
    }
    
    func testVolumeOfDropSetWithEmptyArrays() {
        let dropSet = database.newDropSet(repetitions: [], weights: [])
        let volume = getVolume(of: [dropSet])
        XCTAssertEqual(volume, 0, "Empty drop set should have 0 volume")
    }
    
    func testVolumeOfMixedSetTypes() {
        let exercise = builder.createExercise(name: "Mixed", muscleGroup: .chest)
        let workout = database.newWorkout(name: "Mixed Workout")
        
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: exercise,
            workout: workout
        )
        
        let standardSet = database.newStandardSet(repetitions: 10, weight: 50000, setGroup: setGroup)
        
        let dropSetGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: exercise,
            workout: workout
        )
        let dropSet = database.newDropSet(
            repetitions: [8, 6],
            weights: [40000, 30000],
            setGroup: dropSetGroup
        )
        
        let volume = getVolume(of: [standardSet, dropSet])
        let expected = (10 * 50000) + (8 * 40000) + (6 * 30000)
        XCTAssertEqual(volume, expected, "Mixed set types should all contribute to volume")
    }
    
    // MARK: - Additional Edge Cases
    
    func testVolumeForNonExistentExercise() {
        let benchPress = builder.createExercise(name: "Bench Press", muscleGroup: .chest)
        let unrelatedExercise = builder.createExercise(name: "Unrelated", muscleGroup: .legs)
        
        let workout = database.newWorkout(name: "Test")
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: benchPress,
            workout: workout
        )
        let set = database.newStandardSet(repetitions: 10, weight: 50000, setGroup: setGroup)
        
        let volume = getVolume(of: [set], for: unrelatedExercise)
        XCTAssertEqual(volume, 0, "Volume for unrelated exercise should be 0")
    }
    
    func testVolumeWithNilSetGroup() {
        let standardSet = database.newStandardSet(repetitions: 10, weight: 50000, setGroup: nil)
        
        // Volume calculation should still work for the set itself
        let volume = getVolume(of: [standardSet])
        XCTAssertEqual(volume, 10 * 50000, "Volume should still calculate without setGroup")
    }
    
    func testVolumeForMuscleGroupWithNilExercise() {
        let standardSet = database.newStandardSet(repetitions: 10, weight: 50000, setGroup: nil)
        
        let volume = getVolume(of: [standardSet], for: MuscleGroup.chest)
        XCTAssertEqual(volume, 0, "Volume should be 0 when set has no exercise/muscle group")
    }
    
    func testDropSetWithMismatchedArrays() {
        // When repetitions and weights arrays have different lengths, zip uses shorter one
        let dropSet = database.newDropSet(
            repetitions: [10, 8, 6],
            weights: [50000, 40000],  // Only 2 weights for 3 reps
            setGroup: nil
        )
        
        let volume = getVolume(of: [dropSet])
        let expected = (10 * 50000) + (8 * 40000)  // 6 reps ignored due to zip
        XCTAssertEqual(volume, expected, "Should handle mismatched arrays using zip behavior")
    }
    
    func testLargeVolumeCalculation() {
        // Test with large values to ensure no integer overflow
        // 1000 reps * 1,000,000 grams (1000 kg) = 1,000,000,000
        let standardSet = builder.createStandardSet(repetitions: 1000, weight: 1000000)
        let volume = getVolume(of: [standardSet])
        XCTAssertEqual(volume, 1000 * 1000000, "Should handle large volume calculations")
    }
}

// MARK: - Milestone ladder

/// The milestone detection behind the Highlights carousel: an all-time best crossing a fixed ladder
/// step. Pure functions — no Core Data — so these run against the ladder itself. Weight ladders
/// follow the display unit, so tests pin `weightUnit` explicitly and restore it.
final class MilestoneLadderTests: XCTestCase {
    private var originalWeightUnit: String?

    override func setUp() {
        super.setUp()
        originalWeightUnit = UserDefaults.standard.string(forKey: "weightUnit")
        UserDefaults.standard.set(WeightUnit.kg.rawValue, forKey: "weightUnit")
    }

    override func tearDown() {
        if let originalWeightUnit {
            UserDefaults.standard.set(originalWeightUnit, forKey: "weightUnit")
        } else {
            UserDefaults.standard.removeObject(forKey: "weightUnit")
        }
        super.tearDown()
    }

    func testWeightCrossingReturnsHighestStep() {
        // 95 kg → 122.5 kg crosses 100 AND 120 — the highest crossed step wins.
        let step = MilestoneLadder.highestStep(crossedFrom: 95_000, to: 122_500, metric: .weight)
        XCTAssertEqual(step, 120_000)
    }

    func testNoCrossingBetweenSteps() {
        // 92.5 kg → 97.5 kg improves without reaching the next step (100 kg).
        XCTAssertNil(MilestoneLadder.highestStep(crossedFrom: 92_500, to: 97_500, metric: .weight))
    }

    func testExactStepCounts() {
        // Landing exactly ON a step counts (previousBest < step ≤ value).
        XCTAssertEqual(
            MilestoneLadder.highestStep(crossedFrom: 97_500, to: 100_000, metric: .weight),
            100_000
        )
    }

    func testPreviousBestAtStepCannotRefire() {
        // The all-time best already sits on the step — the same step can't fire again.
        XCTAssertNil(MilestoneLadder.highestStep(crossedFrom: 100_000, to: 105_000, metric: .weight))
    }

    func testLbsLadderUsesPlateMath() {
        UserDefaults.standard.set(WeightUnit.lbs.rawValue, forKey: "weightUnit")
        // 220 lb → 230 lb crosses the 225 lb plate step (in grams).
        let expected = Int(convertWeightForStoring(225.0))
        let from = Int(convertWeightForStoring(220.0))
        let to = Int(convertWeightForStoring(230.0))
        XCTAssertEqual(MilestoneLadder.highestStep(crossedFrom: from, to: to, metric: .weight), expected)
    }

    func testRepetitionsLadder() {
        XCTAssertEqual(MilestoneLadder.highestStep(crossedFrom: 8, to: 12, metric: .repetitions), 10)
        XCTAssertNil(MilestoneLadder.highestStep(crossedFrom: 10, to: 12, metric: .repetitions))
    }

    func testDistanceLadderIncludesHalfMarathon() {
        XCTAssertEqual(
            MilestoneLadder.highestStep(crossedFrom: 15_000, to: 21_100, metric: .distance),
            21_098
        )
    }
}

// MARK: - Duration formatting

/// Recorded durations are stored as whole seconds but displayed as a digital reading, so a held
/// plank and a treadmill run read the way a clock does rather than as a bare seconds count.
final class DurationFormattingTests: XCTestCase {
    func testSubMinuteKeepsLeadingZeroMinute() {
        XCTAssertEqual(formatDurationForDisplay(45), "0:45")
        XCTAssertEqual(formatDurationForDisplay(5), "0:05")
    }

    func testWholeMinute() {
        XCTAssertEqual(formatDurationForDisplay(60), "1:00")
        XCTAssertEqual(formatDurationForDisplay(90), "1:30")
    }

    func testManyMinutesPadsSecondsNotMinutes() {
        // The reported case: a 1280-second run read as "1280 SEC".
        XCTAssertEqual(formatDurationForDisplay(1280), "21:20")
        XCTAssertEqual(formatDurationForDisplay(1320), "22:00")
    }

    func testHoursSplitOffAndPadMinutes() {
        XCTAssertEqual(formatDurationForDisplay(3600), "1:00:00")
        XCTAssertEqual(formatDurationForDisplay(3700), "1:01:40")
        XCTAssertEqual(formatDurationForDisplay(7325), "2:02:05")
    }

    func testZeroAndNegativeAreSafe() {
        XCTAssertEqual(formatDurationForDisplay(0), "0:00")
        // Values can't be negative in the store, but the formatter must not produce "-1:-1".
        XCTAssertEqual(formatDurationForDisplay(-30), "0:00")
    }

    /// The rest-duration picker delegates to the shared formatter — its output must not drift.
    func testRestTimeStringMatchesSharedFormatter() {
        for seconds in [30, 60, 90, 120, 180] {
            XCTAssertEqual(restTimeString(seconds: seconds), formatDurationForDisplay(seconds))
        }
    }

    /// VoiceOver gets words, not a pair of bare numbers.
    func testAccessibleDurationSpellsUnitsAndHidesZeroes() {
        let ninety = accessibleDurationForDisplay(90)
        XCTAssertTrue(ninety.contains("1"), "Expected a minute component in \(ninety)")
        XCTAssertTrue(ninety.contains("30"), "Expected a second component in \(ninety)")
        // A sub-minute hold shouldn't announce "0 minutes".
        let fortyFive = accessibleDurationForDisplay(45)
        XCTAssertFalse(fortyFive.hasPrefix("0"), "Zero-valued units should be hidden: \(fortyFive)")
    }
}

// MARK: - Strength progress

/// The Strength figure is a *set-weighted* mean of each exercise's e1RM change, and the detail
/// screen pulls that mean back apart — so the weighting, the scoping and the ordering are the parts
/// worth pinning down.
final class StrengthProgressTests: XCTestCase {

    private var database: Database!
    private var builder: TestDataBuilder!

    override func setUp() {
        super.setUp()
        database = Database(isPreview: true)
        builder = TestDataBuilder(database: database)
    }

    override func tearDown() {
        database = nil
        builder = nil
        super.tearDown()
    }

    private func change(
        _ name: String,
        _ group: MuscleGroup,
        percent: Double,
        sets: Int
    ) -> StrengthProgress.ExerciseChange {
        StrengthProgress.ExerciseChange(
            exercise: builder.createExercise(name: name, muscleGroup: group),
            muscleGroup: group,
            percentChange: percent,
            setCount: sets
        )
    }

    func testOverallIsWeightedBySetCount() {
        // 10 % over 30 sets and 0 % over 10 sets → 7.5 %, not the unweighted 5 %.
        let progress = StrengthProgress(
            changes: [
                change("Bench Press", .chest, percent: 10, sets: 30),
                change("Curls", .biceps, percent: 0, sets: 10),
            ],
            window: .eightWeeks
        )
        XCTAssertEqual(try XCTUnwrap(progress.overallPercentChange), 7.5, accuracy: 0.001)
    }

    func testScopingToAGroupIgnoresOtherGroups() {
        let progress = StrengthProgress(
            changes: [
                change("Bench Press", .chest, percent: 10, sets: 10),
                change("Incline Bench", .chest, percent: 20, sets: 10),
                change("Curls", .biceps, percent: -40, sets: 100),
            ],
            window: .eightWeeks
        )
        XCTAssertEqual(try XCTUnwrap(progress.percentChange(in: .chest)), 15, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(progress.percentChange(in: .biceps)), -40, accuracy: 0.001)
        XCTAssertNil(progress.percentChange(in: .legs), "A group with no data has no figure")
    }

    /// A zero set count must not erase an exercise from the mean (weights floor at 1).
    func testZeroSetCountStillCounts() {
        let progress = StrengthProgress(
            changes: [change("Bench Press", .chest, percent: 8, sets: 0)],
            window: .eightWeeks
        )
        XCTAssertEqual(try XCTUnwrap(progress.overallPercentChange), 8, accuracy: 0.001)
    }

    func testGroupsAreSortedByGainAndCarryTheirExerciseCount() {
        let progress = StrengthProgress(
            changes: [
                change("Curls", .biceps, percent: 3, sets: 10),
                change("Bench Press", .chest, percent: 9, sets: 10),
                change("Incline Bench", .chest, percent: 9, sets: 10),
            ],
            window: .eightWeeks
        )
        XCTAssertEqual(progress.groups.map(\.muscleGroup), [.chest, .biceps])
        XCTAssertEqual(progress.groups.first?.exerciseCount, 2)
    }

    /// Sorted by magnitude, so a big decline ranks above a small gain rather than sinking to the
    /// bottom of the list where the cap would hide it.
    func testExerciseChangesRankDeclinesByMagnitude() {
        let progress = StrengthProgress(
            changes: [
                change("Small Gain", .chest, percent: 2, sets: 10),
                change("Big Decline", .back, percent: -18, sets: 10),
                change("Mid Gain", .legs, percent: 7, sets: 10),
            ],
            window: .eightWeeks
        )
        XCTAssertEqual(
            progress.exerciseChanges().map { $0.exercise.name },
            ["Big Decline", "Mid Gain", "Small Gain"]
        )
    }

    func testEmptyProgressHasNoFigure() {
        XCTAssertFalse(StrengthProgress.empty.hasData)
        XCTAssertNil(StrengthProgress.empty.overallPercentChange)
        XCTAssertTrue(StrengthProgress.empty.groups.isEmpty)
    }

    func testComputeIgnoresExercisesWithoutBothWindows() {
        // No sets at all → nothing to compare, so nothing qualifies.
        let progress = StrengthProgress.compute(workouts: [], window: .fourWeeks)
        XCTAssertFalse(progress.hasData)
        XCTAssertEqual(progress.window, .fourWeeks)
    }

    func testWindowTitlesAreDistinct() {
        let titles = Set(StrengthWindow.allCases.map(\.title))
        XCTAssertEqual(titles.count, StrengthWindow.allCases.count)
        // Four weeks, so the recent half of the comparison is the same window the rest of the app
        // calls "current" — and the same one the Summary's Balance tile reads. Changing this back
        // decouples the top pair, which is the thing the default exists to guarantee.
        XCTAssertEqual(StrengthWindow.default, .fourWeeks)
        // ...and it must land on exactly the same instant as the current-best window, not merely
        // "about four weeks": the Summary's top pair claims both tiles read the same period.
        let reference = Date.now
        let recentStart = Calendar.current.date(
            byAdding: .weekOfYear, value: -StrengthWindow.default.rawValue, to: reference
        )
        XCTAssertEqual(recentStart, Exercise.currentBestWindowStart(endingAt: reference))
    }

    /// The trend deadband: small wobble reads as steady and keeps the neutral arrow, so the tile
    /// can't flicker between "up" and "down" on noise.
    func testTrendDirectionDeadband() {
        XCTAssertEqual(strengthTrendSymbol(0.4), "arrow.right")
        XCTAssertEqual(strengthTrendSymbol(-0.4), "arrow.right")
        XCTAssertEqual(strengthTrendSymbol(5), "arrow.up")
        XCTAssertEqual(strengthTrendSymbol(-5), "arrow.down")
        XCTAssertFalse(strengthTrendIsUp(0.9))
        XCTAssertTrue(strengthTrendIsUp(1.0))
    }
}
