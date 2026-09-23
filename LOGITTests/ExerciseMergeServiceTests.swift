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

// MARK: - Duplicate Merge (sync copies sharing one id)

/// `Database+DuplicateMerge`: copies of one exercise or template that CloudKit sync leaves behind
/// fold back into one object, with nothing lost and the same survivor on every device.
final class DuplicateMergeTests: XCTestCase {

    private var database: Database!

    override func setUp() {
        super.setUp()
        database = Database(inMemory: true)
    }

    override func tearDown() {
        database = nil
        super.tearDown()
    }

    // MARK: Exercises

    /// Both copies collected history; afterwards one exercise holds all of it, oldest first, and
    /// not a single set group, set or entry is gone.
    func testMergeMovesAllHistoryOntoOneExercise() throws {
        let (first, second) = makeCopies(of: "_default.exercise.pullups")
        let older = logWorkout(on: first, date: .daysAgo(9), sets: 2)
        let newest = logWorkout(on: first, date: .daysAgo(1), sets: 1)
        let middle = logWorkout(on: second, date: .daysAgo(4), sets: 3)
        let template = database.newTemplate(name: "Back")
        let templateGroup = database.newTemplateSetGroup(
            createFirstSetAutomatically: false, exercise: second, template: template
        )
        database.newTemplateStandardSet(repetitions: 8, setGroup: templateGroup)
        try database.context.save()
        let counts = storeCounts()
        let id = first.id!

        let merged = Database.performDuplicateMerge(
            in: database.context, identity: recordNames([first: "B", second: "A"])
        )

        XCTAssertEqual(merged.exercises, 1)
        let survivors = exercises(withID: id)
        XCTAssertEqual(survivors, [second], "the copy with the lowest record name survives")
        XCTAssertEqual(second.setGroups, [older, middle, newest], "all history, oldest first")
        XCTAssertEqual(second.sets.count, 6)
        XCTAssertEqual(templateGroup.exercise, second)
        XCTAssertEqual(second.templateSetGroups_ as? Set<TemplateSetGroup>, [templateGroup])
        let entries = second.sets.flatMap(\.entries)
        XCTAssertEqual(entries.count, 6)
        XCTAssertTrue(entries.allSatisfy { $0.exercise == second }, "every entry names the survivor")
        XCTAssertEqual(storeCounts().removingExercises, counts.removingExercises, "no set group, set or entry lost")
    }

    /// Two devices hold the same two copies but created them in opposite order, so their local
    /// object ids rank them differently. Both must still keep the same copy — keeping "their own"
    /// would make each delete the other's, leaving none.
    func testEveryDeviceKeepsTheCopyWithTheLowestRecordName() throws {
        for lowestCreatedFirst in [true, false] {
            database = Database(inMemory: true)
            let id = UUID()
            let firstCreated = makeExercise(named: "_default.exercise.squat", id: id)
            let secondCreated = makeExercise(named: "_default.exercise.squat", id: id)
            let (low, high) = lowestCreatedFirst
                ? (firstCreated, secondCreated) : (secondCreated, firstCreated)
            logWorkout(on: low, date: .daysAgo(3), sets: 1)
            logWorkout(on: high, date: .daysAgo(2), sets: 1)
            try database.context.save()

            Database.performDuplicateMerge(
                in: database.context, identity: recordNames([low: "0A", high: "0B"])
            )

            XCTAssertEqual(exercises(withID: id), [low], "lowest created first: \(lowestCreatedFirst)")
            XCTAssertEqual(low.setGroups.count, 2)
        }
    }

    /// A copy that hasn't been exported has no record name — and might yet sort first once it
    /// has one. Until then nothing is merged.
    func testCopyWithoutRecordNameWaits() throws {
        let (first, second) = makeCopies(of: "_default.exercise.dips")
        logWorkout(on: first, date: .daysAgo(2), sets: 1)
        try database.context.save()

        let merged = Database.performDuplicateMerge(
            in: database.context, identity: recordNames([first: "A"])
        )

        XCTAssertEqual(merged.exercises, 0)
        XCTAssertEqual(Set(exercises(withID: first.id!)), [first, second])
    }

    /// A super set pairing both copies keeps both lanes: its order list already names the id
    /// twice, which is how a super set of one exercise is stored.
    func testSuperSetPairingBothCopiesKeepsBothLanes() throws {
        let (first, second) = makeCopies(of: "_default.exercise.pushups")
        let workout = database.newWorkout(name: "Pairs", date: .daysAgo(1))
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false, exercise: first, workout: workout
        )
        setGroup.secondaryExercise = second
        database.newSuperSet(repetitionsFirstExercise: 10, repetitionsSecondExercise: 12, setGroup: setGroup)
        try database.context.save()

        Database.performDuplicateMerge(
            in: database.context, identity: recordNames([first: "A", second: "B"])
        )

        XCTAssertEqual(setGroup.exercise, first)
        XCTAssertEqual(setGroup.secondaryExercise, first)
        XCTAssertEqual(setGroup.exerciseOrder, [first.id!, first.id!])
        let entries = setGroup.sets.flatMap(\.entries)
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.allSatisfy { $0.exercise == first })
    }

    /// The survivor takes on the settings of the copy the user actually logged with — the
    /// measurement type and formats their habit was built on.
    func testSurvivorAdoptsSettingsOfTheMostUsedCopy() throws {
        let (first, second) = makeCopies(of: "_default.exercise.running")
        first.measurementType = .distanceAndDuration
        second.measurementType = .duration
        second.durationStyleString = "clock"
        logWorkout(on: second, date: .daysAgo(5), sets: 1)
        try database.context.save()

        Database.performDuplicateMerge(
            in: database.context, identity: recordNames([first: "A", second: "B"])
        )

        XCTAssertEqual(exercises(withID: first.id!), [first])
        XCTAssertEqual(first.measurementType, .duration)
        XCTAssertEqual(first.durationStyleString, "clock")
        XCTAssertEqual(first.setGroups.count, 1)
    }

    /// Something saved from elsewhere after the merge read its copies (an import, a background
    /// sweep) aborts the merge instead of being overwritten; nothing changes.
    func testConcurrentStoreWriteAbortsTheMerge() throws {
        let (first, second) = makeCopies(of: "_default.exercise.deadlift")
        logWorkout(on: second, date: .daysAgo(2), sets: 1)
        try database.context.save()
        let secondID = second.objectID
        _ = second.setGroups  // the view context now holds the copy as read at this moment

        let background = database.setEntryBackfillContext
        try background.performAndWait {
            let copy = try background.existingObject(with: secondID) as! Exercise
            copy.durationStyleString = "clock"
            try background.save()
        }

        let merged = Database.performDuplicateMerge(
            in: database.context, identity: recordNames([first: "A", second: "B"])
        )

        XCTAssertEqual(merged.exercises, 0)
        XCTAssertFalse(database.context.hasChanges, "the attempt was rolled back")
        let request = NSFetchRequest<NSManagedObject>(entityName: "Exercise")
        request.predicate = NSPredicate(format: "id == %@", first.id! as CVarArg)
        XCTAssertEqual(try background.performAndWait { try background.count(for: request) }, 2)
    }

    /// The merge saves the view context, so it never runs under unsaved edits — it would commit
    /// them, or delete an object an editor holds. It runs once they're saved, and drops the undo
    /// history, whose steps could reach for a merged-away copy.
    func testMergeWaitsForUnsavedEditsInTheViewContext() throws {
        let (first, _) = makeCopies(of: "_default.exercise.squat")
        let id = first.id!
        try database.context.save()
        first.durationStyleString = "clock"  // an editor's pending change

        database.mergeDuplicates()
        drainMainQueue()
        XCTAssertEqual(exercises(withID: id).count, 2, "nothing merged under the pending edit")
        XCTAssertTrue(database.context.hasChanges, "and the edit is still pending, not committed")

        try database.context.save()
        XCTAssertEqual(database.context.undoManager?.canUndo, true)
        database.mergeDuplicates()
        drainMainQueue()
        XCTAssertEqual(exercises(withID: id).count, 1)
        XCTAssertEqual(database.context.undoManager?.canUndo, false)
    }

    // MARK: Templates

    /// Identical copies of a starter template merge; workouts started from either stay linked.
    func testIdenticalTemplateCopiesMergeKeepingTheirWorkouts() throws {
        let exercise = makeExercise(named: "_default.exercise.benchPress", id: UUID())
        let id = UUID()
        let first = makeTemplate(id: id, exercise: exercise, created: .daysAgo(3))
        let second = makeTemplate(id: id, exercise: exercise, created: .daysAgo(1))
        let fromSecond = database.newWorkout(name: "Push", date: .daysAgo(1))
        fromSecond.template = second
        try database.context.save()

        let merged = Database.performDuplicateMerge(
            in: database.context, identity: recordNames([first: "A", second: "B"])
        )

        XCTAssertEqual(merged.templates, 1)
        XCTAssertEqual(templates(withID: id), [first])
        XCTAssertEqual(fromSecond.template, first)
        XCTAssertEqual(first.setGroups.count, 1)
        XCTAssertEqual(first.sets.count, 3)
    }

    /// A copy that just appeared may be about to be edited on the device that seeded it; merging
    /// waits until that edit has had time to sync (and make the copies differ).
    func testFreshTemplateCopyWaitsBeforeMerging() throws {
        let exercise = makeExercise(named: "_default.exercise.benchPress", id: UUID())
        let id = UUID()
        let first = makeTemplate(id: id, exercise: exercise, created: .daysAgo(3))
        let second = makeTemplate(id: id, exercise: exercise, created: Date().addingTimeInterval(-5 * 60))
        try database.context.save()
        let identity = recordNames([first: "A", second: "B"])

        XCTAssertEqual(Database.performDuplicateMerge(in: database.context, identity: identity).templates, 0)
        XCTAssertEqual(templates(withID: id).count, 2)

        let later = Date().addingTimeInterval(Database.templateSettlingInterval)
        XCTAssertEqual(
            Database.performDuplicateMerge(in: database.context, identity: identity, now: later).templates, 1
        )
        XCTAssertEqual(templates(withID: id), [first])
    }

    /// Copies that differ mean someone edited one; neither edit may be thrown away.
    func testEditedTemplateCopiesAreBothKept() throws {
        let exercise = makeExercise(named: "_default.exercise.benchPress", id: UUID())
        let id = UUID()
        let first = makeTemplate(id: id, exercise: exercise, created: .daysAgo(3))
        let second = makeTemplate(id: id, exercise: exercise, created: .daysAgo(3))
        second.setGroups.first?.sets.first?.restDuration = 150
        try database.context.save()

        Database.performDuplicateMerge(
            in: database.context, identity: recordNames([first: "A", second: "B"])
        )

        XCTAssertEqual(Set(templates(withID: id)), [first, second])
    }

    /// A set group a drifted order list hides is still part of its template, so a copy holding
    /// one is not "identical" to a copy without it.
    func testTemplateFingerprintSeesMembersHiddenByADriftedList() throws {
        let exercise = makeExercise(named: "_default.exercise.benchPress", id: UUID())
        let id = UUID()
        let first = makeTemplate(id: id, exercise: exercise, created: .daysAgo(3))
        let second = makeTemplate(id: id, exercise: exercise, created: .daysAgo(3))
        XCTAssertEqual(Database.contentFingerprint(of: first), Database.contentFingerprint(of: second))

        let hidden = database.newTemplateSetGroup(
            createFirstSetAutomatically: false, exercise: exercise, template: second
        )
        database.newTemplateStandardSet(repetitions: 5, setGroup: hidden)
        second.templateSetGroupOrder = second.templateSetGroupOrder?.filter { $0 != hidden.id }
        XCTAssertEqual(second.setGroups.count, 1, "precondition: the extra group is hidden")

        XCTAssertNotEqual(Database.contentFingerprint(of: first), Database.contentFingerprint(of: second))
    }

    // MARK: Re-linking by id

    /// Another device merged away the copy this device logged against: the import deletes it,
    /// and the group and its entries lose their exercise. The group's order list still names the
    /// id, so the repair hands them to the copy that survived.
    func testRepairRelinksHistoryCutLooseByAMergeElsewhere() throws {
        let (merged, survivor) = makeCopies(of: "_default.exercise.pullups")
        let setGroup = logWorkout(on: merged, date: .daysAgo(1), sets: 2)
        try database.context.save()

        database.context.delete(merged)  // as the import of the peer's deletion would
        try database.context.save()
        XCTAssertNil(setGroup.exercise, "precondition: the group lost its exercise")
        XCTAssertTrue(setGroup.sets.flatMap(\.entries).allSatisfy { $0.exercise == nil })

        Database.performRelationshipRepair(in: database.context)

        XCTAssertEqual(setGroup.exercise, survivor)
        XCTAssertEqual(survivor.setGroups, [setGroup])
        XCTAssertTrue(setGroup.sets.flatMap(\.entries).allSatisfy { $0.exercise == survivor })
    }

    /// A super set that lost only its second exercise gets that one back.
    func testRepairRelinksMissingSuperSetPartner() throws {
        let partner = makeExercise(named: "Face Pulls", id: UUID())
        let (lost, survivor) = makeCopies(of: "_default.exercise.lateralRaises")
        let workout = database.newWorkout(name: "Shoulders", date: .daysAgo(1))
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false, exercise: partner, workout: workout
        )
        setGroup.secondaryExercise = lost
        database.newSuperSet(repetitionsFirstExercise: 12, repetitionsSecondExercise: 15, setGroup: setGroup)
        try database.context.save()

        database.context.delete(lost)
        try database.context.save()
        XCTAssertNil(setGroup.secondaryExercise, "precondition: the partner is gone")

        Database.performRelationshipRepair(in: database.context)

        XCTAssertEqual(setGroup.exercise, partner)
        XCTAssertEqual(setGroup.secondaryExercise, survivor)
        let entries = setGroup.sets.flatMap(\.entries).sorted { $0.order < $1.order }
        XCTAssertEqual(entries.map(\.exercise), [partner, survivor])
    }

    /// A group whose exercise was really deleted — no copy left — stays as it was.
    func testRepairLeavesGroupOfADeletedExerciseAlone() throws {
        let exercise = makeExercise(named: "Old Custom Exercise", id: UUID())
        let setGroup = logWorkout(on: exercise, date: .daysAgo(1), sets: 1)
        let listedID = exercise.id!
        try database.context.save()

        database.context.delete(exercise)
        try database.context.save()

        Database.performRelationshipRepair(in: database.context)

        XCTAssertNil(setGroup.exercise)
        XCTAssertEqual(setGroup.exerciseOrder, [listedID], "the id stays for a copy that may still arrive")
        XCTAssertEqual(setGroup.sets.count, 1)
    }

    // MARK: Helpers

    /// `mergeDuplicates()` queues its work on the main-queue view context.
    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 5)
    }

    private func makeExercise(named name: String, id: UUID) -> Exercise {
        let exercise = Exercise(context: database.context)
        exercise.id = id
        exercise.name = name
        exercise.muscleGroup = .back
        return exercise
    }

    private func makeCopies(of name: String) -> (Exercise, Exercise) {
        let id = UUID()
        return (makeExercise(named: name, id: id), makeExercise(named: name, id: id))
    }

    @discardableResult
    private func logWorkout(on exercise: Exercise, date: Date, sets: Int) -> WorkoutSetGroup {
        let workout = database.newWorkout(name: "Workout", date: date)
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false, exercise: exercise, workout: workout
        )
        for index in 0..<sets {
            database.newStandardSet(repetitions: 8 + index, weight: 20000, setGroup: setGroup)
        }
        return setGroup
    }

    /// Built the way `DefaultTemplateService` seeds a starter template.
    private func makeTemplate(id: UUID, exercise: Exercise, created: Date) -> Template {
        let template = database.newTemplate(name: "_default.template.pushDay")
        template.id = id
        template.descriptionText = "_default.template.pushDay.description"
        template.creationDate = created
        let setGroup = database.newTemplateSetGroup(
            createFirstSetAutomatically: false, exercise: exercise, template: template
        )
        for _ in 0..<3 {
            database.newTemplateStandardSet(repetitions: 10, weight: 0, restDuration: 90, setGroup: setGroup)
        }
        return template
    }

    private func recordNames(_ names: [NSManagedObject: String]) -> DuplicateMergeIdentity {
        let byID = Dictionary(uniqueKeysWithValues: names.map { ($0.key.objectID, $0.value) })
        return .cloudKit { objectIDs in
            byID.filter { objectIDs.contains($0.key) }
        }
    }

    private func exercises(withID id: UUID) -> [Exercise] {
        let request = NSFetchRequest<Exercise>(entityName: "Exercise")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return (try? database.context.fetch(request)) ?? []
    }

    private func templates(withID id: UUID) -> [Template] {
        let request = NSFetchRequest<Template>(entityName: "Template")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return (try? database.context.fetch(request)) ?? []
    }

    private struct StoreCounts: Equatable {
        var exercises: Int
        var removingExercises: [Int]
    }

    private func storeCounts() -> StoreCounts {
        func count(_ entity: String) -> Int {
            (try? database.context.count(for: NSFetchRequest<NSManagedObject>(entityName: entity))) ?? -1
        }
        return StoreCounts(
            exercises: count("Exercise"),
            removingExercises: ["Workout", "WorkoutSetGroup", "WorkoutSet", "SetEntry", "TemplateSetGroup", "TemplateSet"]
                .map(count)
        )
    }
}
