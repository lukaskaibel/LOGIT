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
        XCTAssertEqual(standardSet.entryValues.map { $0.repetitions }, [10])
        XCTAssertEqual(standardSet.entryValues.map { $0.weight }, [50000])
        XCTAssertEqual(standardSet.entries.first?.type, .repsAndWeight)
        XCTAssertTrue(setGroup.sets.contains(standardSet))
    }

    func testNewDropSetCreation() {
        let setGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false)
        let dropSet = database.newDropSet(repetitions: [10, 8, 6], weights: [100000, 80000, 60000], setGroup: setGroup)
        
        XCTAssertNotNil(dropSet.id)
        XCTAssertEqual(dropSet.numberOfDrops, 3, "Drop set should have 3 drops")
        XCTAssertEqual(dropSet.entryValues.map { $0.repetitions }, [10, 8, 6])
        XCTAssertEqual(dropSet.entryValues.map { $0.weight }, [100000, 80000, 60000])
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
        XCTAssertEqual(superSet.entryValues.map { $0.repetitions }, [10, 12])
        XCTAssertEqual(superSet.entryValues.map { $0.weight }, [50000, 40000])
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
        _ = database.newStandardSet(repetitions: 6, weight: 12000, setGroup: setGroup)
        database.save()
        
        let initialCount = setGroup.sets.count
        XCTAssertEqual(initialCount, 3, "Should have 3 sets (1 auto + 2 manual)")
        
        // Delete one set
        database.delete(set1)
        
        // Wait for context to process. The fulfillment normally lands after ~0.1s;
        // the generous cap only matters on loaded CI runners, where a 1s timeout
        // flaked repeatedly (failed twice in a row on PR #93's runs).
        let expectation = self.expectation(description: "Context update")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 10.0)
        
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

    func testDuplicateTemplateSetPreservesRestDurationAndInsertsAfterSource() {
        let template = database.newTemplate(name: "Template")
        let setGroup = database.newTemplateSetGroup(
            createFirstSetAutomatically: false,
            template: template
        )
        let firstSet = database.newTemplateStandardSet(
            repetitions: 10,
            weight: 60000,
            restDuration: 90,
            setGroup: setGroup
        )
        let secondSet = database.newTemplateStandardSet(
            repetitions: 8,
            weight: 65000,
            restDuration: 45,
            setGroup: setGroup
        )

        database.duplicateSet(firstSet)

        XCTAssertEqual(setGroup.sets.count, 3)
        XCTAssertEqual(setGroup.sets[0].objectID, firstSet.objectID)
        XCTAssertEqual(setGroup.sets[2].objectID, secondSet.objectID)

        let duplicatedSet = setGroup.sets[1] as? TemplateStandardSet
        XCTAssertNotNil(duplicatedSet)
        XCTAssertNotEqual(duplicatedSet?.objectID, firstSet.objectID)
        XCTAssertEqual(duplicatedSet?.repetitions, firstSet.repetitions)
        XCTAssertEqual(duplicatedSet?.weight, firstSet.weight)
        XCTAssertEqual(duplicatedSet?.restDurationSeconds, firstSet.restDurationSeconds)
    }

    func testDuplicateLastTemplateSetPreservesRestDuration() {
        let setGroup = database.newTemplateSetGroup(createFirstSetAutomatically: false)
        _ = database.newTemplateStandardSet(
            repetitions: 10,
            weight: 60000,
            restDuration: 75,
            setGroup: setGroup
        )

        database.duplicateLastSet(from: setGroup)

        XCTAssertEqual(setGroup.sets.count, 2)
        XCTAssertEqual(setGroup.sets.last?.restDurationSeconds, 75)
    }

    // MARK: - Predicate Factory Tests

    /// @FetchRequest evaluates *pending* (unsaved) objects in memory, where a UUID attribute never
    /// equals a uuidString. The factories must therefore compare against the UUID itself, or a
    /// just-edited workout stays invisible on the exercise detail screen until it is persisted.
    func testEditorPredicatesMatchPendingUnsavedObjects() throws {
        let exercise = database.newExercise(name: "Benchpress", muscleGroup: .chest)
        let workout = database.newWorkout(name: "Push Day")
        let setGroup = database.newWorkoutSetGroup(exercise: exercise, workout: workout)
        let workoutSet = try XCTUnwrap(setGroup.sets.first)

        let setGroupPredicate = try XCTUnwrap(
            WorkoutSetGroupPredicateFactory.getWorkoutSetGroups(withExercise: exercise)
        )
        XCTAssertTrue(
            setGroupPredicate.evaluate(with: setGroup),
            "Pending set group must match the exercise-detail predicate before it is saved"
        )

        let setPredicate = try XCTUnwrap(WorkoutSetPredicateFactory.getWorkoutSets(with: exercise))
        XCTAssertTrue(
            setPredicate.evaluate(with: workoutSet),
            "Pending workout set must match the per-exercise predicate before it is saved"
        )

        let workoutSetPredicate = try XCTUnwrap(WorkoutSetPredicateFactory.getWorkoutSets(in: workout))
        XCTAssertTrue(
            workoutSetPredicate.evaluate(with: workoutSet),
            "Pending workout set must match the per-workout predicate before it is saved"
        )
    }

    /// The flip side of the pending-object test: the same predicates still match through SQLite
    /// once the objects are persisted (the store must accept the UUID argument).
    func testEditorPredicatesMatchPersistedObjectsThroughStore() throws {
        let exercise = database.newExercise(name: "Benchpress", muscleGroup: .chest)
        let workout = database.newWorkout(name: "Push Day")
        let setGroup = database.newWorkoutSetGroup(exercise: exercise, workout: workout)
        try database.context.save()

        let fetchedSetGroups = database.fetch(
            WorkoutSetGroup.self,
            predicate: WorkoutSetGroupPredicateFactory.getWorkoutSetGroups(withExercise: exercise)
        ) as? [WorkoutSetGroup]
        XCTAssertEqual(fetchedSetGroups?.contains(setGroup), true)

        let fetchedSets = database.fetch(
            WorkoutSet.self,
            predicate: WorkoutSetPredicateFactory.getWorkoutSets(with: exercise)
        ) as? [WorkoutSet]
        XCTAssertEqual(fetchedSets?.contains(where: { $0.setGroup == setGroup }), true)
    }

    // MARK: - Save Conflict Tests

    /// Reproduces the on-device data loss: another writer (the CloudKit mirroring delegate in
    /// production) updates a row behind the view context's back, making its snapshot stale. With
    /// the default error merge policy the next save throws an unresolved merge conflict, which
    /// used to be swallowed — the workout lived on in memory and vanished with the next launch.
    /// The context must resolve the conflict in favor of the local edit and actually persist it.
    func testSaveSurvivesConcurrentStoreWriteToSameObject() throws {
        let workout = database.newWorkout(name: "Original")
        try database.context.save()
        let workoutID = workout.objectID

        // Local pending edit, made while the row is about to go stale underneath us
        workout.name = "Local Edit"

        // Simulate the CloudKit mirroring delegate: a direct store write from another context
        let coordinator = try XCTUnwrap(database.context.persistentStoreCoordinator)
        let backgroundContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        backgroundContext.persistentStoreCoordinator = coordinator
        try backgroundContext.performAndWait {
            let backgroundWorkout = try XCTUnwrap(
                backgroundContext.existingObject(with: workoutID) as? Workout
            )
            backgroundWorkout.name = "Remote Edit"
            try backgroundContext.save()
        }

        database.save()

        // save() runs async on the context's queue; perform blocks execute in order,
        // so an expectation enqueued after it fires once the save has finished.
        let saveCompleted = expectation(description: "save block completed")
        database.context.perform { saveCompleted.fulfill() }
        wait(for: [saveCompleted], timeout: 5)
        // The failure flag is published via the main queue; drain it before asserting.
        let mainQueueDrained = expectation(description: "main queue drained")
        DispatchQueue.main.async { mainQueueDrained.fulfill() }
        wait(for: [mainQueueDrained], timeout: 5)

        XCTAssertFalse(database.lastSaveFailed, "The conflicting save must be resolved, not dropped")

        // The store — not the in-memory context — must hold the local edit: verify through a
        // fresh context so a silently failed save can't masquerade as success.
        let verificationContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        verificationContext.persistentStoreCoordinator = coordinator
        try verificationContext.performAndWait {
            let persistedWorkout = try XCTUnwrap(
                verificationContext.existingObject(with: workoutID) as? Workout
            )
            XCTAssertEqual(persistedWorkout.name, "Local Edit")
        }
    }
}

// MARK: - Model Version 7 Migration Tests

/// Proves that a store created with model version 6 opens under the current model via the same
/// automatic lightweight migration `Database.init` configures — existing user data must survive
/// the new `Template.id` / `Template.descriptionText` attributes.
final class TemplateModelMigrationTests: XCTestCase {

    private var storeURL: URL!

    override func setUp() {
        super.setUp()
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MigrationTest-\(UUID().uuidString).sqlite")
    }

    override func tearDown() {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: storeURL.path + suffix)
        }
        storeURL = nil
        super.tearDown()
    }

    func testLightweightMigrationFromModelVersion6PreservesTemplates() throws {
        let bundle = Bundle(for: Database.self)
        let momdURL = try XCTUnwrap(bundle.url(forResource: "LOGIT", withExtension: "momd"))
        let v6Model = try XCTUnwrap(
            NSManagedObjectModel(contentsOf: momdURL.appendingPathComponent("LOGIT 6.0.mom")),
            "Model version 6 must stay in the bundle for migration"
        )
        // This throwaway copy must not claim the NSManagedObject subclasses — a second claim
        // makes `+entity` ambiguous for every test that runs afterwards (see `Database.model`).
        // The v6 side only uses string-keyed inserts and KVC, so plain NSManagedObject suffices.
        // Version hashes come from the schema alone, so migration behavior is unaffected.
        v6Model.entities.forEach { $0.managedObjectClassName = "NSManagedObject" }
        // The current version must be the shared model, never a second loaded copy (same reason).
        let currentModel = Database.model
        XCTAssertNotNil(
            currentModel.entitiesByName["Template"]?.attributesByName["descriptionText"],
            "Current model must be version 7 with the new attributes"
        )

        // 1. Create a v6 store containing a template with a set group
        let v6Coordinator = NSPersistentStoreCoordinator(managedObjectModel: v6Model)
        try v6Coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL)
        let v6Context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        v6Context.persistentStoreCoordinator = v6Coordinator
        let v6Template = NSEntityDescription.insertNewObject(forEntityName: "Template", into: v6Context)
        v6Template.setValue("My Old Template", forKey: "name")
        v6Template.setValue(Date(), forKey: "creationDate")
        let v6SetGroup = NSEntityDescription.insertNewObject(forEntityName: "TemplateSetGroup", into: v6Context)
        v6SetGroup.setValue(UUID(), forKey: "id")
        v6SetGroup.setValue(v6Template, forKey: "workout")
        try v6Context.save()
        try v6Coordinator.remove(v6Coordinator.persistentStores[0])

        // 2. Reopen with the current model and the options Database.init uses
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: currentModel)
        try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: storeURL,
            options: [
                NSMigratePersistentStoresAutomaticallyOption: true,
                NSInferMappingModelAutomaticallyOption: true,
            ]
        )
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator

        // 3. The old data survived and the new attributes are usable
        let request = NSFetchRequest<NSManagedObject>(entityName: "Template")
        let migrated = try context.fetch(request)
        XCTAssertEqual(migrated.count, 1)
        let template = try XCTUnwrap(migrated.first)
        XCTAssertEqual(template.value(forKey: "name") as? String, "My Old Template")
        XCTAssertEqual((template.value(forKey: "setGroups_") as? NSSet)?.count, 1)
        XCTAssertNil(template.value(forKey: "id"), "Migrated templates start without an id (backfilled later)")
        XCTAssertNil(template.value(forKey: "descriptionText"))

        template.setValue(UUID(), forKey: "id")
        template.setValue("A description", forKey: "descriptionText")
        try context.save()
    }
}
