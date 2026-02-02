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
        XCTAssertEqual(dropSet.repetitions?.last, 0, "New drop should have 0 reps")
        XCTAssertEqual(dropSet.weights?.last, 0, "New drop should have 0 weight")
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
        
        XCTAssertEqual(dropSet.repetitions, [0, 0], "Reps should be cleared")
        XCTAssertEqual(dropSet.weights, [0, 0], "Weights should be cleared")
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
    
    // MARK: - WorkoutSet Match Tests
    
    func testStandardSetMatchFromWorkoutSet() {
        let set1 = database.newStandardSet(repetitions: 0, weight: 0)
        let set2 = database.newStandardSet(repetitions: 10, weight: 50000)
        
        set1.match(set2)
        
        XCTAssertEqual(set1.repetitions, 10)
        XCTAssertEqual(set1.weight, 50000)
    }
    
    func testDropSetMatchFromWorkoutSet() {
        let dropSet1 = database.newDropSet(repetitions: [0, 0], weights: [0, 0])
        let dropSet2 = database.newDropSet(repetitions: [10, 8], weights: [50000, 40000])
        
        dropSet1.match(dropSet2)
        
        XCTAssertEqual(dropSet1.repetitions, [10, 8])
        XCTAssertEqual(dropSet1.weights, [50000, 40000])
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
        
        XCTAssertEqual(superSet1.repetitionsFirstExercise, 10)
        XCTAssertEqual(superSet1.repetitionsSecondExercise, 12)
        XCTAssertEqual(superSet1.weightFirstExercise, 50000)
        XCTAssertEqual(superSet1.weightSecondExercise, 40000)
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
        
        XCTAssertEqual(dropSet.numberOfDrops, 0, "Empty drop set should have 0 drops")
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
}
