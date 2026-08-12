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

    // MARK: - History Survival

    /// The 2026-07-28 data loss, reduced to its mechanism: a set group whose `exerciseOrder` id
    /// list no longer resolves answers "no exercise" to `setGroup.exercise`, so the old
    /// reassignment skipped it and left it attached to the source — which the cascade delete rule
    /// then took down, erasing that workout's history. Reassignment now walks the relationship,
    /// and the relationship no longer cascades.
    func testMergeReassignsSetGroupWithDriftedExerciseOrder() {
        let source = builder.createExercise(name: "Benchpress")
        let target = builder.createExercise(name: "_default.exercise.barbellBenchPress")

        let workout = builder.createWorkout(name: "Push Day", date: .daysAgo(30))
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: source,
            workout: workout
        )
        database.newStandardSet(repetitions: 8, weight: 90000, setGroup: setGroup)

        // Drift: the relationship still holds source, the id list no longer names it.
        setGroup.exerciseOrder = []
        XCTAssertNil(setGroup.exercise, "precondition: the group can no longer name its exercise")

        try! mergeService.merge(source: source, into: target)

        XCTAssertEqual(setGroup.exercise, target, "the group must survive and follow the merge")
        XCTAssertEqual(setGroup.sets.count, 1)
        XCTAssertEqual(setGroup.sets.first?.maximum(.weight, for: target), 90000)
        XCTAssertEqual(target.setGroups.count, 1, "and be visible through the target's order list")
        XCTAssertEqual(workout.setGroups.count, 1, "and still be part of its workout")
    }

    /// Whatever else goes wrong, deleting an exercise must never delete a past workout's sets.
    /// This is the guarantee the Cascade→Nullify change buys, and it holds even when the group is
    /// still fully attached to the exercise being deleted.
    func testDeletingExerciseKeepsWorkoutHistory() {
        let exercise = builder.createExercise(name: "Barbell Row")
        let workout = builder.createWorkout(name: "Pull Day", date: .daysAgo(10))
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: exercise,
            workout: workout
        )
        database.newStandardSet(repetitions: 10, weight: 70000, setGroup: setGroup)
        let setGroupID = setGroup.id!

        database.context.delete(exercise)
        // Delete rules are applied here, not at `delete(_:)` — this is the moment the old
        // Cascade rule would have taken the set group and its sets.
        database.context.processPendingChanges()

        let surviving = database.fetch(
            WorkoutSetGroup.self, predicate: NSPredicate(format: "id == %@", setGroupID as CVarArg)
        ) as? [WorkoutSetGroup] ?? []
        XCTAssertEqual(surviving.count, 1, "the set group must outlive its exercise")
        XCTAssertEqual(surviving.first?.sets.count, 1, "with its sets intact")
        XCTAssertEqual(workout.setGroups.count, 1, "and still belong to the workout")
    }

    /// A merged-away exercise leaves entries naming the target; if the group's own link is lost
    /// (a peer's delete racing the reassignment), the repair sweep puts it back.
    func testRepairAdoptsOrphanedSetGroupFromItsEntries() {
        let exercise = builder.createExercise(name: "Overhead Press")
        let workout = builder.createWorkout(name: "Shoulders", date: .daysAgo(5))
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: exercise,
            workout: workout
        )
        database.newStandardSet(repetitions: 6, weight: 45000, setGroup: setGroup)

        // Sever only the group→exercise link, as a nullify from a remote delete would.
        setGroup.exercises_ = NSSet()
        setGroup.exerciseOrder = []
        XCTAssertNil(setGroup.exercise)

        Database.performRelationshipRepair(in: database.context)

        XCTAssertEqual(setGroup.exercise, exercise, "the entries still knew what this group trained")
        XCTAssertEqual(exercise.setGroups.count, 1)
    }

    /// A set group missing from its exercise's id list is invisible everywhere that reads
    /// `exercise.sets` — the Summary strength tile, records, the in-workout comparison. The sweep
    /// relists it without touching ids it cannot account for.
    func testRepairRelistsSetGroupMissingFromOrderList() {
        let exercise = builder.createExercise(name: "Squat")
        let workout = builder.createWorkout(name: "Legs", date: .daysAgo(3))
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: exercise,
            workout: workout
        )
        database.newStandardSet(repetitions: 5, weight: 120000, setGroup: setGroup)

        let strangerID = UUID()
        exercise.setGroupOrder = [strangerID]
        XCTAssertEqual(exercise.setGroups.count, 0, "precondition: the group is invisible")

        Database.performRelationshipRepair(in: database.context)

        XCTAssertEqual(exercise.setGroups.count, 1, "the group is visible again")
        XCTAssertEqual(exercise.sets.count, 1)
        XCTAssertTrue(
            exercise.setGroupOrder?.contains(strangerID) ?? false,
            "ids the sweep cannot account for are left alone — pruning them would flap between devices"
        )
    }

    /// Duplicated ids show one set group twice and double-count its volume.
    func testRepairCollapsesDuplicatedOrderEntries() {
        let exercise = builder.createExercise(name: "Deadlift")
        let workout = builder.createWorkout(name: "Pull", date: .daysAgo(2))
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: exercise,
            workout: workout
        )
        database.newStandardSet(repetitions: 3, weight: 140000, setGroup: setGroup)

        exercise.setGroupOrder = [setGroup.id!, setGroup.id!]
        XCTAssertEqual(exercise.setGroups.count, 2, "precondition: counted twice")

        Database.performRelationshipRepair(in: database.context)

        XCTAssertEqual(exercise.setGroups.count, 1)
    }

    /// Deleting the last set of a group whose `setOrder` has drifted must not take the group —
    /// and its other sets — with it.
    func testDeletingSetKeepsGroupWhenSetOrderDrifted() {
        let exercise = builder.createExercise(name: "Lat Pulldown")
        let workout = builder.createWorkout(name: "Back", date: .daysAgo(1))
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: exercise,
            workout: workout
        )
        let first = database.newStandardSet(repetitions: 12, weight: 40000, setGroup: setGroup)
        database.newStandardSet(repetitions: 10, weight: 45000, setGroup: setGroup)

        // Drift: the group reports zero sets while still holding two.
        setGroup.setOrder = []
        XCTAssertEqual(setGroup.numberOfSets, 0, "precondition: the group looks empty")

        database.delete(first)
        drainContext()

        let remaining = ((setGroup.sets_?.allObjects as? [WorkoutSet]) ?? [])
            .filter { !$0.isDeleted }
        XCTAssertFalse(setGroup.isDeleted, "the group must survive")
        XCTAssertEqual(remaining.count, 1, "only the deleted set is gone")
    }

    // MARK: - Helpers

    /// `Database.delete` enqueues its work on the context's queue, which on the main-queue view
    /// context lands on the next run-loop turn. Same drain the other database tests use.
    private func drainContext() {
        let drained = expectation(description: "context drained")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { drained.fulfill() }
        waitForExpectations(timeout: 10.0)
        database.context.processPendingChanges()
    }
}
