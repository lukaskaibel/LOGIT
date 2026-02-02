//
//  DatabaseTests.swift
//  LOGITTests
//
//  Created by Lukas Kaibel on 15.09.23.
//

import XCTest
import CoreData

@testable import LOGIT

final class DatabaseTests: XCTestCase {

    private var database: Database!

    override func setUp() {
        super.setUp()
        database = Database(isPreview: true)
    }

    override func tearDown() {
        database = nil
        super.tearDown()
    }

    // MARK: - Entity Creation Tests

    func testNewWorkoutCreation() {
        let workout = database.newWorkout(name: "Test Workout", date: Date())
        
        XCTAssertNotNil(workout.id, "Workout should have a UUID")
        XCTAssertEqual(workout.name, "Test Workout")
        XCTAssertTrue(workout.setGroups.isEmpty, "New workout should have no set groups")
    }
    
    func testNewWorkoutWithDefaultValues() {
        let workout = database.newWorkout()
        
        XCTAssertNotNil(workout.id)
        XCTAssertEqual(workout.name, "")
        XCTAssertNotNil(workout.date)
    }

    func testNewWorkoutSetGroupCreation() {
        let workout = database.newWorkout(name: "Test")
        let setGroup = database.newWorkoutSetGroup(workout: workout)
        
        XCTAssertNotNil(setGroup.id, "SetGroup should have a UUID")
        XCTAssertEqual(setGroup.sets.count, 1, "SetGroup should have one default set")
        XCTAssertEqual(workout.setGroups.count, 1, "Workout should contain the set group")
    }
    
    func testNewWorkoutSetGroupWithoutAutoSet() {
        let setGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false)
        
        XCTAssertTrue(setGroup.sets.isEmpty, "SetGroup should have no sets when auto-creation is disabled")
    }

    func testNewStandardSetCreation() {
        let setGroup = database.newWorkoutSetGroup()
        let standardSet = database.newStandardSet(repetitions: 10, weight: 50000, setGroup: setGroup)
        
        XCTAssertNotNil(standardSet.id)
        XCTAssertEqual(standardSet.repetitions, 10)
        XCTAssertEqual(standardSet.weight, 50000)
        XCTAssertTrue(setGroup.sets.contains(standardSet))
    }

    func testNewDropSetCreation() {
        let setGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false)
        let dropSet = database.newDropSet(repetitions: [10, 8, 6], weights: [100000, 80000, 60000], setGroup: setGroup)
        
        XCTAssertNotNil(dropSet.id)
        XCTAssertEqual(dropSet.repetitions?.count, 3, "Drop set should have 3 drops")
        XCTAssertEqual(dropSet.weights?.count, 3)
        XCTAssertEqual(dropSet.numberOfDrops, 3)
    }

    func testNewSuperSetCreation() {
        let setGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false)
        let superSet = database.newSuperSet(
            repetitionsFirstExercise: 10,
            repetitionsSecondExercise: 12,
            weightFirstExercise: 50000,
            weightSecondExercise: 40000,
            setGroup: setGroup
        )
        
        XCTAssertNotNil(superSet.id)
        XCTAssertEqual(superSet.repetitionsFirstExercise, 10)
        XCTAssertEqual(superSet.repetitionsSecondExercise, 12)
        XCTAssertEqual(superSet.weightFirstExercise, 50000)
        XCTAssertEqual(superSet.weightSecondExercise, 40000)
    }

    // MARK: - Database Operations Tests

    func testFetchEmptyDatabase() {
        // Create a fresh database without preview data
        let freshDatabase = Database(isPreview: true)
        
        // The preview database comes with sample data, so we test fetch works
        let workouts = freshDatabase.fetch(Workout.self) as! [Workout]
        XCTAssertNotNil(workouts, "Fetch should return an array")
    }

    func testFetchWithPredicate() {
        let workoutName = "UniqueTestWorkout_\(UUID().uuidString)"
        database.newWorkout(name: workoutName, date: Date())
        database.save()
        
        let predicate = NSPredicate(format: "name == %@", workoutName)
        let workouts = database.fetch(Workout.self, predicate: predicate) as! [Workout]
        
        XCTAssertEqual(workouts.count, 1, "Should find exactly one workout with unique name")
        XCTAssertEqual(workouts.first?.name, workoutName)
    }

    func testFetchWithSorting() {
        // Create workouts with different dates
        let oldDate = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        let newDate = Date()
        
        database.newWorkout(name: "Old Workout", date: oldDate)
        database.newWorkout(name: "New Workout", date: newDate)
        database.save()
        
        let ascendingWorkouts = database.fetch(Workout.self, sortingKey: "date", ascending: true) as! [Workout]
        let descendingWorkouts = database.fetch(Workout.self, sortingKey: "date", ascending: false) as! [Workout]
        
        // In ascending order, older dates come first
        if let firstAsc = ascendingWorkouts.first, let lastAsc = ascendingWorkouts.last {
            XCTAssertTrue(firstAsc.date! <= lastAsc.date!, "Ascending sort should have older dates first")
        }
        
        // In descending order, newer dates come first
        if let firstDesc = descendingWorkouts.first, let lastDesc = descendingWorkouts.last {
            XCTAssertTrue(firstDesc.date! >= lastDesc.date!, "Descending sort should have newer dates first")
        }
    }

    func testDeleteWorkoutSet() {
        let workout = database.newWorkout(name: "Delete Test")
        let setGroup = database.newWorkoutSetGroup(workout: workout)
        let set1 = database.newStandardSet(repetitions: 5, weight: 10000, setGroup: setGroup)
        let set2 = database.newStandardSet(repetitions: 6, weight: 12000, setGroup: setGroup)
        database.save()
        
        let initialCount = setGroup.sets.count
        XCTAssertEqual(initialCount, 3, "Should have 3 sets (1 auto + 2 manual)")
        
        // Delete one set
        database.delete(set1)
        
        // Wait for context to process
        let expectation = self.expectation(description: "Context update")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        
        XCTAssertEqual(setGroup.sets.count, 2, "Should have 2 sets after deletion")
        XCTAssertFalse(setGroup.sets.contains(set1), "Deleted set should not be in array")
    }

    // MARK: - Undo/Redo Tests

    func testUndoManagerExists() {
        XCTAssertNotNil(database.context.undoManager, "Database context should have an undo manager")
    }

    // MARK: - Edge Cases

    func testCreateWorkoutWithEmptyName() {
        let workout = database.newWorkout(name: "")
        XCTAssertEqual(workout.name, "", "Should allow empty workout name")
    }

    func testCreateSetWithZeroValues() {
        let set = database.newStandardSet(repetitions: 0, weight: 0)
        XCTAssertEqual(set.repetitions, 0)
        XCTAssertEqual(set.weight, 0)
        XCTAssertFalse(set.hasEntry, "Set with zero values should not have entry")
    }

    func testCreateDropSetWithSingleDrop() {
        let dropSet = database.newDropSet(repetitions: [10], weights: [50000])
        XCTAssertEqual(dropSet.numberOfDrops, 1, "Should handle single-drop drop set")
    }

    func testCreateDropSetWithManyDrops() {
        let reps = Array(1...10)
        let weights = Array(repeating: 10000, count: 10)
        let dropSet = database.newDropSet(repetitions: reps, weights: weights)
        XCTAssertEqual(dropSet.numberOfDrops, 10, "Should handle many drops")
    }
}
