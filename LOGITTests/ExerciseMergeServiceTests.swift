//
//  ExerciseMergeServiceTests.swift
//  LOGITTests
//
//  Tests for ExerciseMergeService
//

import XCTest
import CoreData

@testable import LOGIT

final class ExerciseMergeServiceTests: XCTestCase {

    private var database: Database!
    private var builder: TestDataBuilder!
    private var mergeService: ExerciseMergeService!
    private var defaultsHelper: UserDefaultsTestHelper!

    override func setUp() {
        super.setUp()
        let result = createTestBuilder()
        database = result.database
        builder = result.builder
        mergeService = ExerciseMergeService(database: database)
        defaultsHelper = UserDefaultsTestHelper()
    }

    override func tearDown() {
        defaultsHelper.restoreAll()
        database = nil
        builder = nil
        mergeService = nil
        defaultsHelper = nil
        super.tearDown()
    }

    // MARK: - Validation Tests

    func testMergeTwoDefaultExercisesThrows() {
        let defaultA = builder.createExercise(name: "_default.exercise.test_a")
        let defaultB = builder.createExercise(name: "_default.exercise.test_b")

        XCTAssertTrue(defaultA.isDefaultExercise)
        XCTAssertTrue(defaultB.isDefaultExercise)

        XCTAssertThrowsError(try mergeService.merge(source: defaultA, into: defaultB)) { error in
            XCTAssertEqual(error as? ExerciseMergeError, .bothAreDefaultExercises)
        }
    }

    func testMergeSameExerciseThrows() {
        let exercise = builder.createExercise(name: "Bench Press")

        XCTAssertThrowsError(try mergeService.merge(source: exercise, into: exercise)) { error in
            XCTAssertEqual(error as? ExerciseMergeError, .sameExercise)
        }
    }

    // MARK: - WorkoutSetGroup Reassignment Tests

    func testMergeTwoCustomExercises() {
        let source = builder.createExercise(name: "Flat Bench Press")
        let target = builder.createExercise(name: "Bench Press")

        let workout = builder.createWorkout(name: "Chest Day")
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: source,
            workout: workout
        )
        database.newStandardSet(repetitions: 10, weight: 60000, setGroup: setGroup)

        XCTAssertEqual(source.setGroups.count, 1)
        XCTAssertEqual(target.setGroups.count, 0)

        try! mergeService.merge(source: source, into: target)

        XCTAssertEqual(target.setGroups.count, 1)
        XCTAssertEqual(setGroup.exercise, target)
        XCTAssertEqual(setGroup.sets.count, 1)
    }

    func testMergeCustomIntoDefault() {
        let custom = builder.createExercise(name: "My Push-ups")
        let defaultExercise = builder.createExercise(name: "_default.exercise.pushups")

        let workout = builder.createWorkout(name: "Bodyweight")
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: custom,
            workout: workout
        )
        database.newStandardSet(repetitions: 20, weight: 0, setGroup: setGroup)

        XCTAssertTrue(defaultExercise.isDefaultExercise)
        XCTAssertFalse(custom.isDefaultExercise)

        try! mergeService.merge(source: custom, into: defaultExercise)

        XCTAssertEqual(defaultExercise.setGroups.count, 1)
        XCTAssertEqual(setGroup.exercise, defaultExercise)

        let fetched = database.getExercise(byID: custom.id!)
        XCTAssertNil(fetched, "Source exercise should be deleted")
    }

    func testMergePreservesTargetExistingHistory() {
        let source = builder.createExercise(name: "DB Bench Press")
        let target = builder.createExercise(name: "Dumbbell Bench Press")

        let workout1 = builder.createWorkout(name: "Day 1", date: .daysAgo(7))
        let targetGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: target,
            workout: workout1
        )
        database.newStandardSet(repetitions: 10, weight: 50000, setGroup: targetGroup)

        let workout2 = builder.createWorkout(name: "Day 2", date: .daysAgo(1))
        let sourceGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: source,
            workout: workout2
        )
        database.newStandardSet(repetitions: 12, weight: 55000, setGroup: sourceGroup)

        XCTAssertEqual(target.setGroups.count, 1)
        XCTAssertEqual(source.setGroups.count, 1)

        try! mergeService.merge(source: source, into: target)

        XCTAssertEqual(target.setGroups.count, 2)
    }

    func testMergeDeletesSourceExercise() {
        let source = builder.createExercise(name: "Old Exercise")
        let target = builder.createExercise(name: "New Exercise")
        let sourceID = source.id!

        try! mergeService.merge(source: source, into: target)

        let fetched = database.getExercise(byID: sourceID)
        XCTAssertNil(fetched, "Source exercise should no longer exist in the database")
    }

    // MARK: - Superset / Secondary Exercise Tests

    func testMergeReassignsSecondaryExercise() {
        let primary = builder.createExercise(name: "Bench Press")
        let source = builder.createExercise(name: "Old Fly")
        let target = builder.createExercise(name: "Cable Fly")

        let workout = builder.createWorkout(name: "Chest Day")
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: primary,
            workout: workout
        )
        setGroup.secondaryExercise = source
        database.newSuperSet(
            repetitionsFirstExercise: 10,
            repetitionsSecondExercise: 12,
            weightFirstExercise: 60000,
            weightSecondExercise: 15000,
            setGroup: setGroup
        )

        XCTAssertEqual(setGroup.secondaryExercise, source)

        try! mergeService.merge(source: source, into: target)

        XCTAssertEqual(setGroup.secondaryExercise, target)
        XCTAssertEqual(setGroup.exercise, primary, "Primary exercise should be unchanged")
    }

    func testMergeReassignsBothPrimaryAndSecondary() {
        let source = builder.createExercise(name: "Old Exercise")
        let target = builder.createExercise(name: "New Exercise")

        let workout = builder.createWorkout(name: "Test")
        let setGroup1 = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: source,
            workout: workout
        )
        database.newStandardSet(repetitions: 10, weight: 50000, setGroup: setGroup1)

        let other = builder.createExercise(name: "Other Exercise")
        let setGroup2 = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: other,
            workout: workout
        )
        setGroup2.secondaryExercise = source
        database.newSuperSet(
            repetitionsFirstExercise: 10,
            repetitionsSecondExercise: 10,
            weightFirstExercise: 50000,
            weightSecondExercise: 50000,
            setGroup: setGroup2
        )

        try! mergeService.merge(source: source, into: target)

        XCTAssertEqual(setGroup1.exercise, target)
        XCTAssertEqual(setGroup2.secondaryExercise, target)
        XCTAssertEqual(setGroup2.exercise, other, "Unrelated primary should remain unchanged")
    }

    // MARK: - Template Tests

    func testMergeReassignsTemplateSetGroups() {
        let source = builder.createExercise(name: "Old Squat")
        let target = builder.createExercise(name: "Barbell Squat")

        let template = database.newTemplate(name: "Leg Day")
        let templateGroup = database.newTemplateSetGroup(
            createFirstSetAutomatically: false,
            exercise: source,
            template: template
        )
        database.newTemplateStandardSet(repetitions: 5, weight: 100000, setGroup: templateGroup)

        XCTAssertEqual(templateGroup.exercise, source)

        try! mergeService.merge(source: source, into: target)

        XCTAssertEqual(templateGroup.exercise, target)
    }

    func testMergeReassignsTemplateSecondaryExercise() {
        let primary = builder.createExercise(name: "Bench Press")
        let source = builder.createExercise(name: "Old Fly")
        let target = builder.createExercise(name: "New Fly")

        let template = database.newTemplate(name: "Chest Template")
        let templateGroup = database.newTemplateSetGroup(
            createFirstSetAutomatically: false,
            exercise: primary,
            template: template
        )
        templateGroup.secondaryExercise = source

        try! mergeService.merge(source: source, into: target)

        XCTAssertEqual(templateGroup.secondaryExercise, target)
        XCTAssertEqual(templateGroup.exercise, primary)
    }

    // MARK: - Pinned Exercise Tests

    func testMergeUpdatesPinnedExercises() {
        let source = builder.createExercise(name: "Pinned Exercise")
        let target = builder.createExercise(name: "Target Exercise")
        let sourceID = source.id!
        let targetID = target.id!

        let tiles = [
            PinnedExerciseTile(exerciseID: sourceID, tileType: .weight),
            PinnedExerciseTile(exerciseID: UUID(), tileType: .volume)
        ]
        let encoded = try! JSONEncoder().encode(tiles)
        defaultsHelper.setTestValue(encoded, forKey: "pinnedExercises")

        try! mergeService.merge(source: source, into: target)

        let data = UserDefaults.standard.data(forKey: "pinnedExercises")!
        let updatedTiles = try! JSONDecoder().decode([PinnedExerciseTile].self, from: data)

        XCTAssertEqual(updatedTiles.count, 2)
        XCTAssertEqual(updatedTiles[0].exerciseID, targetID)
        XCTAssertEqual(updatedTiles[0].tileType, .weight)
        XCTAssertEqual(updatedTiles[1].tileType, .volume, "Unrelated tile should be unchanged")
    }

    func testMergeWithNoPinnedExercises() {
        let source = builder.createExercise(name: "Source")
        let target = builder.createExercise(name: "Target")
        defaultsHelper.setTestValue(nil, forKey: "pinnedExercises")

        XCTAssertNoThrow(try mergeService.merge(source: source, into: target))
    }

    // MARK: - Combined Scenarios

    func testMergeReassignsWorkoutsAndTemplatesSimultaneously() {
        let source = builder.createExercise(name: "Source Exercise")
        let target = builder.createExercise(name: "Target Exercise")

        let workout = builder.createWorkout(name: "Workout")
        let workoutGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: source,
            workout: workout
        )
        database.newStandardSet(repetitions: 8, weight: 70000, setGroup: workoutGroup)

        let template = database.newTemplate(name: "Template")
        let templateGroup = database.newTemplateSetGroup(
            createFirstSetAutomatically: false,
            exercise: source,
            template: template
        )
        database.newTemplateStandardSet(repetitions: 8, weight: 70000, setGroup: templateGroup)

        try! mergeService.merge(source: source, into: target)

        XCTAssertEqual(workoutGroup.exercise, target)
        XCTAssertEqual(templateGroup.exercise, target)
        XCTAssertNil(database.getExercise(byID: source.id!))
    }

    func testMergeSourceWithNoHistory() {
        let source = builder.createExercise(name: "Empty Source")
        let target = builder.createExercise(name: "Target")

        let workout = builder.createWorkout(name: "Existing Workout")
        let existingGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: target,
            workout: workout
        )
        database.newStandardSet(repetitions: 5, weight: 100000, setGroup: existingGroup)

        XCTAssertNoThrow(try mergeService.merge(source: source, into: target))
        XCTAssertEqual(target.setGroups.count, 1)
        XCTAssertNil(database.getExercise(byID: source.id!))
    }
}
