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
