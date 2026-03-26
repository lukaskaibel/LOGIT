//
//  DatabaseRollbackTests.swift
//  LOGITTests
//
//  Regression tests for synchronous rollback on Cancel flows.
//

import XCTest

@testable import LOGIT

final class DatabaseRollbackTests: XCTestCase {
    private var database: Database!

    override func setUp() {
        super.setUp()
        database = Database(isPreview: true)
    }

    override func tearDown() {
        database = nil
        super.tearDown()
    }

    func testDiscardUnsavedChanges_rollsBackTemplateNameSynchronously() {
        let template = database.newTemplate(name: "Original Name")
        database.save()

        template.name = "Edited Name"
        XCTAssertTrue(database.context.hasChanges, "Precondition: editing should mark context dirty")

        database.discardUnsavedChanges()

        XCTAssertFalse(database.context.hasChanges, "Rollback should clear pending changes")
        XCTAssertEqual(template.name, "Original Name", "Template name should revert immediately after rollback")
    }

    func testDiscardUnsavedChanges_rollsBackTemplateSetGroupsSynchronously() {
        let exercise = database.newExercise(name: "Benchpress", muscleGroup: .chest)
        let template = database.newTemplate(name: "My Template")
        database.save()

        XCTAssertEqual(template.setGroups.count, 0, "Precondition: template should start with no set groups")

        _ = database.newTemplateSetGroup(createFirstSetAutomatically: false, exercise: exercise, template: template)
        XCTAssertEqual(template.setGroups.count, 1, "Precondition: edit should be visible before rollback")
        XCTAssertTrue(database.context.hasChanges, "Precondition: adding a set group should mark context dirty")

        database.discardUnsavedChanges()

        XCTAssertFalse(database.context.hasChanges, "Rollback should clear pending changes")
        XCTAssertEqual(template.setGroups.count, 0, "Template set groups should revert immediately after rollback")
    }

    func testDiscardUnsavedChanges_rollsBackWorkoutNameSynchronously() {
        let workout = database.newWorkout(name: "Original Workout")
        database.save()

        workout.name = "Edited Workout"
        XCTAssertTrue(database.context.hasChanges, "Precondition: editing should mark context dirty")

        database.discardUnsavedChanges()

        XCTAssertFalse(database.context.hasChanges, "Rollback should clear pending changes")
        XCTAssertEqual(workout.name, "Original Workout", "Workout name should revert immediately after rollback")
    }

    func testDiscardUnsavedChanges_rollsBackWorkoutSetGroupsSynchronously() {
        let exercise = database.newExercise(name: "Deadlift", muscleGroup: .back)
        let workout = database.newWorkout(name: "My Workout")
        database.save()

        XCTAssertEqual(workout.setGroups.count, 0, "Precondition: workout should start with no set groups")

        _ = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: exercise, workout: workout)
        XCTAssertEqual(workout.setGroups.count, 1, "Precondition: edit should be visible before rollback")
        XCTAssertTrue(database.context.hasChanges, "Precondition: adding a set group should mark context dirty")

        database.discardUnsavedChanges()

        XCTAssertFalse(database.context.hasChanges, "Rollback should clear pending changes")
        XCTAssertEqual(workout.setGroups.count, 0, "Workout set groups should revert immediately after rollback")
    }

    func testDiscardUnsavedChanges_rollsBackExerciseFieldsSynchronously() {
        let exercise = database.newExercise(name: "Original Exercise", muscleGroup: .chest)
        database.save()

        exercise.name = "Edited Exercise"
        exercise.muscleGroup = .back
        XCTAssertTrue(database.context.hasChanges, "Precondition: editing should mark context dirty")

        database.discardUnsavedChanges()

        XCTAssertFalse(database.context.hasChanges, "Rollback should clear pending changes")
        XCTAssertEqual(exercise.name, "Original Exercise", "Exercise name should revert immediately after rollback")
        XCTAssertEqual(exercise.muscleGroup, .chest, "Exercise muscle group should revert immediately after rollback")
    }
}

