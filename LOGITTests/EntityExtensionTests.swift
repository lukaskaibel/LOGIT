//
//  EntityExtensionTests.swift
//  LOGITTests
//
//  Tests for Core Data entity extension methods
//

import XCTest

@testable import LOGIT

final class EntityExtensionTests: XCTestCase {
    
    private var database: Database!
    private var builder: TestDataBuilder!
    private var userDefaultsHelper: UserDefaultsTestHelper!
    
    override func setUp() {
        super.setUp()
        database = Database(isPreview: true)
        builder = TestDataBuilder(database: database)
        userDefaultsHelper = UserDefaultsTestHelper()
        userDefaultsHelper.setTestValue("kg", forKey: "weightUnit")
    }
    
    override func tearDown() {
        userDefaultsHelper.restoreAll()
        database = nil
        builder = nil
        super.tearDown()
    }
    
    // MARK: - StandardSet Tests
    
    func testStandardSetHasEntryWithValues() {
        let set = database.newStandardSet(repetitions: 10, weight: 50000)
        XCTAssertTrue(set.hasEntry, "Set with reps and weight should have entry")
    }
    
    func testStandardSetHasEntryWithOnlyReps() {
        let set = database.newStandardSet(repetitions: 10, weight: 0)
        XCTAssertTrue(set.hasEntry, "Set with only reps should have entry")
    }
    
    func testStandardSetHasEntryWithOnlyWeight() {
        let set = database.newStandardSet(repetitions: 0, weight: 50000)
        XCTAssertTrue(set.hasEntry, "Set with only weight should have entry")
    }

    func testStandardSetHasNoRepetitionEntryWithOnlyWeight() {
        let set = database.newStandardSet(repetitions: 0, weight: 50000)
        XCTAssertFalse(set.hasRepetitionEntry, "Set with only weight should not have a repetition entry")
    }
    
    func testStandardSetHasNoEntry() {
        let set = database.newStandardSet(repetitions: 0, weight: 0)
        XCTAssertFalse(set.hasEntry, "Set with no values should not have entry")
    }
    
    func testStandardSetClearEntries() {
        let set = database.newStandardSet(repetitions: 10, weight: 50000)
        set.clearEntries()
        
        XCTAssertEqual(set.repetitions, 0, "Reps should be cleared")
        XCTAssertEqual(set.weight, 0, "Weight should be cleared")
        XCTAssertFalse(set.hasEntry, "Should have no entry after clearing")
    }
    
    // MARK: - DropSet Tests
    
    func testDropSetHasEntryWithValues() {
        let dropSet = builder.createDropSet(drops: [(10, 50000), (8, 40000)])
        XCTAssertTrue(dropSet.hasEntry, "Drop set with values should have entry")
    }
    
    func testDropSetHasEntryWithOnlyReps() {
        let dropSet = database.newDropSet(repetitions: [10, 8], weights: [0, 0])
        XCTAssertTrue(dropSet.hasEntry, "Drop set with only reps should have entry")
    }
    
    func testDropSetHasEntryWithOnlyWeights() {
        let dropSet = database.newDropSet(repetitions: [0, 0], weights: [50000, 40000])
        XCTAssertTrue(dropSet.hasEntry, "Drop set with only weights should have entry")
    }

    func testDropSetHasNoRepetitionEntryWithOnlyWeights() {
        let dropSet = database.newDropSet(repetitions: [0, 0], weights: [50000, 40000])
        XCTAssertFalse(dropSet.hasRepetitionEntry, "Drop set with only weights should not have a repetition entry")
    }
    
    func testDropSetHasNoEntry() {
        let dropSet = database.newDropSet(repetitions: [0, 0], weights: [0, 0])
        XCTAssertFalse(dropSet.hasEntry, "Drop set with all zeros should not have entry")
    }
    
    func testDropSetNumberOfDrops() {
        let dropSet = builder.createDropSet(drops: [(10, 50000), (8, 40000), (6, 30000)])
        XCTAssertEqual(dropSet.numberOfDrops, 3, "Should have 3 drops")
    }
    
    func testDropSetAddDrop() {
        let dropSet = builder.createDropSet(drops: [(10, 50000)])
        let initialCount = dropSet.numberOfDrops
        
        dropSet.addDrop()
        
        XCTAssertEqual(dropSet.numberOfDrops, initialCount + 1, "Should have one more drop")
        XCTAssertEqual(dropSet.entryValues.last?.repetitions, 0, "New drop should have 0 reps")
        XCTAssertEqual(dropSet.entryValues.last?.weight, 0, "New drop should have 0 weight")
    }
    
    func testDropSetRemoveLastDrop() {
        let dropSet = builder.createDropSet(drops: [(10, 50000), (8, 40000), (6, 30000)])
        
        dropSet.removeLastDrop()
        
        XCTAssertEqual(dropSet.numberOfDrops, 2, "Should have 2 drops after removal")
    }
    
    func testDropSetRemoveLastDropMinimum() {
        let dropSet = builder.createDropSet(drops: [(10, 50000)])
        
        dropSet.removeLastDrop()  // Should not remove if only 1 drop
        
        XCTAssertEqual(dropSet.numberOfDrops, 1, "Should keep minimum of 1 drop")
    }
    
    func testDropSetClearEntries() {
        let dropSet = builder.createDropSet(drops: [(10, 50000), (8, 40000)])
        
        dropSet.clearEntries()
        
        XCTAssertEqual(dropSet.entryValues.map { $0.repetitions }, [0, 0], "Reps should be cleared")
        XCTAssertEqual(dropSet.entryValues.map { $0.weight }, [0, 0], "Weights should be cleared")
        XCTAssertEqual(dropSet.numberOfDrops, 2, "Should keep same number of drops")
        XCTAssertFalse(dropSet.hasEntry, "Should have no entry after clearing")
    }
    
    // MARK: - SuperSet Tests
    
    func testSuperSetHasEntryWithAllValues() {
        let superSet = builder.createSuperSet(
            repsFirst: 10,
            repsSecond: 12,
            weightFirst: 50000,
            weightSecond: 40000
        )
        XCTAssertTrue(superSet.hasEntry, "Super set with all values should have entry")
    }
    
    func testSuperSetHasEntryWithOnlyFirstExercise() {
        let superSet = database.newSuperSet(
            repetitionsFirstExercise: 10,
            repetitionsSecondExercise: 0,
            weightFirstExercise: 50000,
            weightSecondExercise: 0
        )
        XCTAssertTrue(superSet.hasEntry, "Super set with only first exercise should have entry")
    }
    
    func testSuperSetHasEntryWithOnlySecondExercise() {
        let superSet = database.newSuperSet(
            repetitionsFirstExercise: 0,
            repetitionsSecondExercise: 12,
            weightFirstExercise: 0,
            weightSecondExercise: 40000
        )
        XCTAssertTrue(superSet.hasEntry, "Super set with only second exercise should have entry")
    }

    func testSuperSetHasNoRepetitionEntryWithOnlyWeights() {
        let superSet = database.newSuperSet(
            repetitionsFirstExercise: 0,
            repetitionsSecondExercise: 0,
            weightFirstExercise: 50000,
            weightSecondExercise: 40000
        )
        XCTAssertFalse(superSet.hasRepetitionEntry, "Super set with only weights should not have a repetition entry")
    }
    
    func testSuperSetHasNoEntry() {
        let superSet = database.newSuperSet()
        XCTAssertFalse(superSet.hasEntry, "Empty super set should not have entry")
    }
    
    func testSuperSetClearEntries() {
        let superSet = builder.createSuperSet(
            repsFirst: 10,
            repsSecond: 12,
            weightFirst: 50000,
            weightSecond: 40000
        )
        
        superSet.clearEntries()
        
        XCTAssertEqual(superSet.repetitionsFirstExercise, 0)
        XCTAssertEqual(superSet.repetitionsSecondExercise, 0)
        XCTAssertEqual(superSet.weightFirstExercise, 0)
        XCTAssertEqual(superSet.weightSecondExercise, 0)
        XCTAssertFalse(superSet.hasEntry)
    }
    
    // MARK: - WorkoutSet Maximum Tests
    
    func testStandardSetMaximumReps() {
        let exercise = builder.createExercise(name: "Test")
        let set = builder.createStandardSet(repetitions: 15, weight: 50000, exercise: exercise)
        
        let maxReps = set.maximum(.repetitions, for: exercise)
        XCTAssertEqual(maxReps, 15, "Should return repetitions for standard set")
    }
    
    func testStandardSetMaximumWeight() {
        let exercise = builder.createExercise(name: "Test")
        let set = builder.createStandardSet(repetitions: 15, weight: 50000, exercise: exercise)
        
        let maxWeight = set.maximum(.weight, for: exercise)
        XCTAssertEqual(maxWeight, 50000, "Should return weight for standard set")
    }
    
    func testDropSetMaximumReps() {
        let exercise = builder.createExercise(name: "Test")
        let dropSet = builder.createDropSet(
            drops: [(10, 50000), (8, 40000), (12, 30000)],
            exercise: exercise
        )
        
        let maxReps = dropSet.maximum(.repetitions, for: exercise)
        XCTAssertEqual(maxReps, 12, "Should return max reps from all drops")
    }
    
    func testDropSetMaximumWeight() {
        let exercise = builder.createExercise(name: "Test")
        let dropSet = builder.createDropSet(
            drops: [(10, 50000), (8, 60000), (6, 30000)],
            exercise: exercise
        )
        
        let maxWeight = dropSet.maximum(.weight, for: exercise)
        XCTAssertEqual(maxWeight, 60000, "Should return max weight from all drops")
    }
    
    func testSuperSetMaximumForFirstExercise() {
        let exercise1 = builder.createExercise(name: "Curls")
        let exercise2 = builder.createExercise(name: "Triceps")
        
        let superSet = builder.createSuperSet(
            repsFirst: 10,
            repsSecond: 12,
            weightFirst: 50000,
            weightSecond: 40000,
            firstExercise: exercise1,
            secondExercise: exercise2
        )
        
        XCTAssertEqual(superSet.maximum(.repetitions, for: exercise1), 10)
        XCTAssertEqual(superSet.maximum(.weight, for: exercise1), 50000)
    }
    
    func testSuperSetMaximumForSecondExercise() {
        let exercise1 = builder.createExercise(name: "Curls")
        let exercise2 = builder.createExercise(name: "Triceps")
        
        let superSet = builder.createSuperSet(
            repsFirst: 10,
            repsSecond: 12,
            weightFirst: 50000,
            weightSecond: 40000,
            firstExercise: exercise1,
            secondExercise: exercise2
        )
        
        XCTAssertEqual(superSet.maximum(.repetitions, for: exercise2), 12)
        XCTAssertEqual(superSet.maximum(.weight, for: exercise2), 40000)
    }
    
    func testMaximumForWrongExercise() {
        let exercise1 = builder.createExercise(name: "Bench")
        let exercise2 = builder.createExercise(name: "Squat")
        
        let set = builder.createStandardSet(repetitions: 10, weight: 50000, exercise: exercise1)
        
        let maxReps = set.maximum(.repetitions, for: exercise2)
        XCTAssertEqual(maxReps, 0, "Should return 0 for wrong exercise")
    }

    // MARK: - WorkoutSet Max Entry Tests

    func testStandardSetMaxWeightEntry() {
        let exercise = builder.createExercise(name: "Test")
        let set = builder.createStandardSet(repetitions: 15, weight: 50000, exercise: exercise)

        let entry = set.maxWeightEntry(for: exercise)
        XCTAssertEqual(entry.weight, 50000)
        XCTAssertEqual(entry.repetitions, 15, "Paired reps come from the same set")
    }

    func testStandardSetMaxRepetitionsEntry() {
        let exercise = builder.createExercise(name: "Test")
        let set = builder.createStandardSet(repetitions: 15, weight: 50000, exercise: exercise)

        let entry = set.maxRepetitionsEntry(for: exercise)
        XCTAssertEqual(entry.repetitions, 15)
        XCTAssertEqual(entry.weight, 50000, "Paired weight comes from the same set")
    }

    func testDropSetMaxWeightEntryUsesSameDrop() {
        let exercise = builder.createExercise(name: "Test")
        // Heaviest drop (60000) and most reps (12) are in *different* drops.
        let dropSet = builder.createDropSet(
            drops: [(10, 50000), (8, 60000), (12, 30000)],
            exercise: exercise
        )

        let entry = dropSet.maxWeightEntry(for: exercise)
        XCTAssertEqual(entry.weight, 60000, "Heaviest drop wins")
        XCTAssertEqual(entry.repetitions, 8, "Reps must be the heaviest drop's, not the max reps")
    }

    func testDropSetMaxRepetitionsEntryUsesSameDrop() {
        let exercise = builder.createExercise(name: "Test")
        let dropSet = builder.createDropSet(
            drops: [(10, 50000), (8, 60000), (12, 30000)],
            exercise: exercise
        )

        let entry = dropSet.maxRepetitionsEntry(for: exercise)
        XCTAssertEqual(entry.repetitions, 12, "Most-reps drop wins")
        XCTAssertEqual(entry.weight, 30000, "Weight must be the most-reps drop's, not the max weight")
    }

    func testSuperSetMaxEntryForEachExercise() {
        let exercise1 = builder.createExercise(name: "Curls")
        let exercise2 = builder.createExercise(name: "Triceps")
        let superSet = builder.createSuperSet(
            repsFirst: 10,
            repsSecond: 12,
            weightFirst: 50000,
            weightSecond: 40000,
            firstExercise: exercise1,
            secondExercise: exercise2
        )

        XCTAssertEqual(superSet.maxWeightEntry(for: exercise1).weight, 50000)
        XCTAssertEqual(superSet.maxWeightEntry(for: exercise1).repetitions, 10)
        XCTAssertEqual(superSet.maxRepetitionsEntry(for: exercise2).repetitions, 12)
        XCTAssertEqual(superSet.maxRepetitionsEntry(for: exercise2).weight, 40000)
    }

    func testMaxEntryForWrongExerciseIsZero() {
        let exercise1 = builder.createExercise(name: "Bench")
        let exercise2 = builder.createExercise(name: "Squat")
        let set = builder.createStandardSet(repetitions: 10, weight: 50000, exercise: exercise1)

        XCTAssertEqual(set.maxWeightEntry(for: exercise2).weight, 0)
        XCTAssertEqual(set.maxRepetitionsEntry(for: exercise2).repetitions, 0)
    }

    // MARK: - Exercise Current Best Tests

    func testCurrentBestWindowIsExactlyFourWeeks() {
        // The UI copy promises "last 4 weeks" everywhere a current best is explained — the window
        // must be 28 days, not a calendar month.
        let anchor = Date(timeIntervalSince1970: 1_780_000_000)
        XCTAssertEqual(
            Exercise.currentBestWindowStart(endingAt: anchor),
            Calendar.current.date(byAdding: .day, value: -28, to: anchor)
        )
    }

    func testCurrentBestSetExcludesSetJustOutsideFourWeekWindow() {
        let exercise = builder.createExercise(name: "Test")
        let outsideWorkout = builder.createWorkout(date: Calendar.current.date(byAdding: .day, value: -29, to: .now)!)
        builder.createStandardSet(repetitions: 5, weight: 100_000, exercise: exercise, workout: outsideWorkout)
        let insideWorkout = builder.createWorkout(date: Calendar.current.date(byAdding: .day, value: -27, to: .now)!)
        let insideSet = builder.createStandardSet(repetitions: 8, weight: 80_000, exercise: exercise, workout: insideWorkout)

        XCTAssertEqual(
            exercise.currentBestSet(for: .weight), insideSet,
            "A set 29 days ago sits outside the 4-week window; the 27-day-old set is the current best"
        )
    }

    func testCurrentBestSetIgnoresSetsOutsideWindow() {
        let exercise = builder.createExercise(name: "Test")
        let oldWorkout = builder.createWorkout(date: Calendar.current.date(byAdding: .month, value: -2, to: .now)!)
        builder.createStandardSet(repetitions: 5, weight: 100_000, exercise: exercise, workout: oldWorkout)
        let recentWorkout = builder.createWorkout(date: Calendar.current.date(byAdding: .day, value: -7, to: .now)!)
        let recentSet = builder.createStandardSet(repetitions: 8, weight: 80_000, exercise: exercise, workout: recentWorkout)

        let best = exercise.currentBestSet(for: .weight)
        XCTAssertEqual(best, recentSet, "The heavier set is outside the window, so the recent lighter set is the current best")
    }

    func testCurrentBestSetIncludesTodaysWorkout() {
        let exercise = builder.createExercise(name: "Test")
        let recentWorkout = builder.createWorkout(date: Calendar.current.date(byAdding: .day, value: -14, to: .now)!)
        builder.createStandardSet(repetitions: 8, weight: 80_000, exercise: exercise, workout: recentWorkout)
        let todaysWorkout = builder.createWorkout(date: .now)
        let todaysSet = builder.createStandardSet(repetitions: 8, weight: 90_000, exercise: exercise, workout: todaysWorkout)

        let best = exercise.currentBestSet(for: .weight)
        XCTAssertEqual(best, todaysSet, "A set from the workout being recorded counts toward the current best")
    }

    func testCurrentBestSetIsMetricSpecific() {
        let exercise = builder.createExercise(name: "Test")
        let workout = builder.createWorkout(date: .now)
        let heaviestSet = builder.createStandardSet(repetitions: 5, weight: 100_000, exercise: exercise, workout: workout)
        let highestRepSet = builder.createStandardSet(repetitions: 12, weight: 60_000, exercise: exercise, workout: workout)

        XCTAssertEqual(exercise.currentBestSet(for: .weight), heaviestSet)
        XCTAssertEqual(exercise.currentBestSet(for: .repetitions), highestRepSet)
    }

    func testCurrentBestSetForE1RMSkipsHighRepSets() {
        let exercise = builder.createExercise(name: "Test")
        let workout = builder.createWorkout(date: .now)
        // 15 reps is above the e1RM reliability cutoff, so this set has no e1RM at all.
        builder.createStandardSet(repetitions: 15, weight: 100_000, exercise: exercise, workout: workout)
        let lowRepSet = builder.createStandardSet(repetitions: 5, weight: 80_000, exercise: exercise, workout: workout)

        let best = exercise.currentBestSet(for: .estimatedOneRepMax)
        XCTAssertEqual(best, lowRepSet, "Sets above the rep cutoff don't produce an e1RM and can't be the current best")
    }

    func testCurrentBestSetNilWithoutUsableSetsInWindow() {
        let exercise = builder.createExercise(name: "Test")
        let oldWorkout = builder.createWorkout(date: Calendar.current.date(byAdding: .month, value: -3, to: .now)!)
        builder.createStandardSet(repetitions: 5, weight: 100_000, exercise: exercise, workout: oldWorkout)

        XCTAssertNil(exercise.currentBestSet(for: .weight), "Only sets older than the window exist")
        XCTAssertNil(exercise.currentBestSet(for: .estimatedOneRepMax))
    }

    func testCurrentBestSetRespectsNarrowedCandidates() {
        let exercise = builder.createExercise(name: "Test")
        let workout = builder.createWorkout(date: .now)
        builder.createStandardSet(repetitions: 5, weight: 100_000, exercise: exercise, workout: workout)
        let lighterSet = builder.createStandardSet(repetitions: 8, weight: 70_000, exercise: exercise, workout: workout)

        let best = exercise.currentBestSet(for: .weight, in: [lighterSet])
        XCTAssertEqual(best, lighterSet, "Narrowed candidate list excludes the heavier set")
    }

    // MARK: - Workout Extension Tests
    
    func testWorkoutIsEmpty() {
        let workout = database.newWorkout(name: "Empty")
        XCTAssertTrue(workout.isEmpty, "Workout with no set groups should be empty")
    }
    
    func testWorkoutIsNotEmpty() {
        let workout = database.newWorkout(name: "Not Empty")
        database.newWorkoutSetGroup(workout: workout)
        XCTAssertFalse(workout.isEmpty, "Workout with set groups should not be empty")
    }
    
    func testWorkoutNumberOfSets() {
        let workout = builder.createCompleteWorkout(
            exerciseCount: 2,
            setsPerExercise: 3
        )
        XCTAssertEqual(workout.numberOfSets, 6, "Should have 6 sets (2 exercises * 3 sets)")
    }
    
    func testWorkoutNumberOfSetGroups() {
        let workout = builder.createCompleteWorkout(
            exerciseCount: 3,
            setsPerExercise: 2
        )
        XCTAssertEqual(workout.numberOfSetGroups, 3, "Should have 3 set groups")
    }
    
    func testWorkoutExercises() {
        let workout = builder.createCompleteWorkout(
            exerciseCount: 3,
            setsPerExercise: 2
        )
        XCTAssertEqual(workout.exercises.count, 3, "Should have 3 exercises")
    }
    
    func testWorkoutMuscleGroups() {
        let workout = database.newWorkout(name: "Multi Muscle")
        
        let chestExercise = builder.createExercise(name: "Bench", muscleGroup: .chest)
        let backExercise = builder.createExercise(name: "Row", muscleGroup: .back)
        let chestExercise2 = builder.createExercise(name: "Flyes", muscleGroup: .chest)
        
        database.newWorkoutSetGroup(exercise: chestExercise, workout: workout)
        database.newWorkoutSetGroup(exercise: backExercise, workout: workout)
        database.newWorkoutSetGroup(exercise: chestExercise2, workout: workout)
        
        let muscleGroups = workout.muscleGroups
        
        XCTAssertEqual(muscleGroups.count, 2, "Should have 2 unique muscle groups")
        XCTAssertTrue(muscleGroups.contains(.chest))
        XCTAssertTrue(muscleGroups.contains(.back))
    }
    
    func testWorkoutHasEntriesTrue() {
        let workout = builder.createCompleteWorkout(exerciseCount: 1, setsPerExercise: 1)
        XCTAssertTrue(workout.hasEntries, "Workout with filled sets should have entries")
    }
    
    func testWorkoutHasEntriesFalse() {
        let workout = database.newWorkout(name: "Empty Sets")
        let exercise = builder.createExercise()
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: exercise,
            workout: workout
        )
        database.newStandardSet(repetitions: 0, weight: 0, setGroup: setGroup)

        XCTAssertFalse(workout.hasEntries, "Workout with empty sets should not have entries")
    }

    // MARK: - Save Eligibility Tests

    /// A workout with a date and at least one set group can be saved even with no end date —
    /// duration is optional, so the editor must not require it (the "0:00" default is never
    /// fabricated).
    func testCanBeSavedToHistoryWithoutDuration() {
        let workout = database.newWorkout(name: "No Duration")
        database.newWorkoutSetGroup(workout: workout)
        XCTAssertNil(workout.endDate, "newWorkout leaves the end date unset")

        XCTAssertTrue(
            workout.canBeSavedToHistory,
            "A dated workout with set groups is saveable without a duration"
        )
    }

    /// An empty workout (no set groups) still can't be saved, duration or not.
    func testCannotSaveEmptyWorkout() {
        let workout = database.newWorkout(name: "Empty")
        workout.endDate = workout.date?.addingTimeInterval(3600)

        XCTAssertFalse(
            workout.canBeSavedToHistory,
            "A workout with no set groups is not saveable even with a duration"
        )
    }

    /// A workout with a duration set is of course still saveable.
    func testCanBeSavedToHistoryWithDuration() {
        let workout = database.newWorkout(name: "With Duration")
        database.newWorkoutSetGroup(workout: workout)
        workout.endDate = workout.date?.addingTimeInterval(3600)

        XCTAssertTrue(workout.canBeSavedToHistory)
    }
    
    // MARK: - WorkoutSet Match Tests
    
    func testStandardSetMatchFromWorkoutSet() {
        let set1 = database.newStandardSet(repetitions: 0, weight: 0)
        let set2 = database.newStandardSet(repetitions: 10, weight: 50000)
        
        set1.match(set2)

        XCTAssertEqual(set1.entryValues.map { $0.repetitions }, [10])
        XCTAssertEqual(set1.entryValues.map { $0.weight }, [50000])
    }
    
    func testDropSetMatchFromWorkoutSet() {
        let dropSet1 = database.newDropSet(repetitions: [0, 0], weights: [0, 0])
        let dropSet2 = database.newDropSet(repetitions: [10, 8], weights: [50000, 40000])
        
        dropSet1.match(dropSet2)

        XCTAssertEqual(dropSet1.entryValues.map { $0.repetitions }, [10, 8])
        XCTAssertEqual(dropSet1.entryValues.map { $0.weight }, [50000, 40000])
    }
    
    func testSuperSetMatchFromWorkoutSet() {
        let superSet1 = database.newSuperSet()
        let superSet2 = database.newSuperSet(
            repetitionsFirstExercise: 10,
            repetitionsSecondExercise: 12,
            weightFirstExercise: 50000,
            weightSecondExercise: 40000
        )
        
        superSet1.match(superSet2)

        XCTAssertEqual(superSet1.entryValues.map { $0.repetitions }, [10, 12])
        XCTAssertEqual(superSet1.entryValues.map { $0.weight }, [50000, 40000])
    }
    
    // MARK: - WorkoutSet Properties Tests
    
    func testWorkoutSetIsDropSet() {
        let dropSet = builder.createDropSet()
        let standardSet = builder.createStandardSet()
        
        XCTAssertTrue(dropSet.isDropSet)
        XCTAssertFalse(standardSet.isDropSet)
    }
    
    func testWorkoutSetIsSuperSet() {
        let superSet = builder.createSuperSet()
        let standardSet = builder.createStandardSet()
        
        XCTAssertTrue(superSet.isSuperSet)
        XCTAssertFalse(standardSet.isSuperSet)
    }
    
    func testWorkoutSetExerciseProperty() {
        let exercise = builder.createExercise(name: "Test Exercise")
        let standardSet = builder.createStandardSet(exercise: exercise)
        
        XCTAssertEqual(standardSet.exercise, exercise)
    }
    
    func testWorkoutSetWorkoutProperty() {
        let workout = database.newWorkout(name: "Test")
        let exercise = builder.createExercise()
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: exercise,
            workout: workout
        )
        let standardSet = database.newStandardSet(setGroup: setGroup)
        
        XCTAssertEqual(standardSet.workout, workout)
    }
    
    // MARK: - Nil/Edge Case Tests
    
    func testWorkoutSetWithNilSetGroup() {
        let standardSet = database.newStandardSet(repetitions: 10, weight: 50000, setGroup: nil)
        
        XCTAssertNil(standardSet.exercise, "Exercise should be nil when setGroup is nil")
        XCTAssertNil(standardSet.workout, "Workout should be nil when setGroup is nil")
    }
    
    func testDropSetWithEmptyArrays() {
        let dropSet = database.newDropSet(repetitions: [], weights: [])
        
        // A drop set always keeps at least one (placeholder) entry since model v8.
        XCTAssertEqual(dropSet.numberOfDrops, 1, "Empty drop set keeps one placeholder drop")
        XCTAssertFalse(dropSet.hasEntry, "Empty drop set should not have entry")
    }
    
    func testSuperSetWithZeroValues() {
        let superSet = database.newSuperSet(
            repetitionsFirstExercise: 0,
            repetitionsSecondExercise: 0,
            weightFirstExercise: 0,
            weightSecondExercise: 0
        )
        
        XCTAssertFalse(superSet.hasEntry, "SuperSet with all zeros should not have entry")
    }
    
    func testWorkoutWithEmptyName() {
        let workout = database.newWorkout(name: "")
        
        XCTAssertEqual(workout.name, "", "Empty name should be preserved")
    }
    
    func testWorkoutWithDistantPastDate() {
        let distantPast = Date.distantPast
        let workout = database.newWorkout(name: "Old Workout", date: distantPast)
        
        XCTAssertEqual(workout.date, distantPast, "Should handle distant past date")
    }
    
    func testWorkoutWithFutureDate() {
        let futureDate = Calendar.current.date(byAdding: .year, value: 1, to: Date())!
        let workout = database.newWorkout(name: "Future Workout", date: futureDate)

        XCTAssertEqual(workout.date, futureDate, "Should handle future date")
    }

    // MARK: - OneRepMax Tests

    func testOneRepMaxEpleyValue() {
        // Epley: weight × (1 + reps/30). 100000 × (1 + 5/30) = 116667 (rounded).
        XCTAssertEqual(OneRepMax.estimated(weight: 100000, repetitions: 5), 116667)
    }

    func testOneRepMaxSingleRep() {
        // 100000 × (1 + 1/30) = 103333 (rounded).
        XCTAssertEqual(OneRepMax.estimated(weight: 100000, repetitions: 1), 103333)
    }

    func testOneRepMaxZeroWeightOrRepsIsZero() {
        XCTAssertEqual(OneRepMax.estimated(weight: 0, repetitions: 10), 0, "No weight → no estimate")
        XCTAssertEqual(OneRepMax.estimated(weight: 50000, repetitions: 0), 0, "No reps → no estimate")
    }

    func testOneRepMaxAtReliableCutoffIsEstimated() {
        // The last reliable rep count still produces an estimate.
        XCTAssertEqual(OneRepMax.maxReliableRepetitions, 12)
        XCTAssertGreaterThan(
            OneRepMax.estimated(weight: 50000, repetitions: OneRepMax.maxReliableRepetitions),
            0,
            "Sets at the reliable cutoff should be estimated"
        )
    }

    func testOneRepMaxAboveReliableCutoffIsExcluded() {
        // Past the reliable range the estimate is unreliable, so none is reported.
        XCTAssertEqual(OneRepMax.estimated(weight: 50000, repetitions: 13), 0)
        XCTAssertEqual(OneRepMax.estimated(weight: 50000, repetitions: 20), 0)
    }
}
