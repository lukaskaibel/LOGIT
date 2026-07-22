//
//  SetEntryMigrationTests.swift
//  LOGITTests
//
//  Created by Lukas Kaibel on 16.07.26.
//

import CoreData
import XCTest

@testable import LOGIT

/// The no-data-loss proof for the v7 → v8 model migration and the set-entry backfill.
///
/// The fixture `LOGIT-v7-legacy.sqlite` is a real store created with the compiled v7 model by
/// `Fixtures/make_v7_fixture.swift` (run in a separate process, so this test process never
/// loads a second model copy — the +entity ambiguity hazard). It contains deterministic UUIDs
/// (`00000000-0000-0000-0000-0000000000NN`) and every legacy edge case:
/// standard sets (filled, empty), drop sets (normal, reps-longer, weights-longer, nil arrays,
/// empty arrays), super sets (filled, empty, group missing its secondary exercise), orphan sets
/// without a set group, and the template mirrors including a desynced template drop set.
final class SetEntryMigrationTests: XCTestCase {
    private var storeURL: URL!
    private var container: NSPersistentContainer?

    override func setUpWithError() throws {
        let fixtureURL = try XCTUnwrap(
            Bundle(for: SetEntryMigrationTests.self)
                .url(forResource: "LOGIT-v7-legacy", withExtension: "sqlite"),
            "Fixture missing from the test bundle — is it registered as a test resource?"
        )
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SetEntryMigrationTests-\(UUID().uuidString).sqlite")
        try FileManager.default.copyItem(at: fixtureURL, to: storeURL)
    }

    override func tearDownWithError() throws {
        if let container {
            for store in container.persistentStoreCoordinator.persistentStores {
                try? container.persistentStoreCoordinator.remove(store)
            }
        }
        container = nil
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(
                at: URL(fileURLWithPath: storeURL.path + suffix)
            )
        }
    }

    // MARK: - Helpers

    /// Opens the copied legacy store under the current (v8) model with lightweight migration —
    /// exactly what `Database` does on a real device after the app update.
    private func openMigratedStore() throws -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "LOGIT", managedObjectModel: Database.model)
        let description = NSPersistentStoreDescription(url: storeURL)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        self.container = container
        return container
    }

    /// The deterministic fixture UUID scheme — mirrors `make_v7_fixture.swift`.
    private func fixtureUUID(_ suffix: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", suffix))!
    }

    private func fetch<T: NSManagedObject>(
        _ entityName: String, fixtureId: Int, in context: NSManagedObjectContext
    ) throws -> T {
        let request = NSFetchRequest<T>(entityName: entityName)
        request.predicate = NSPredicate(format: "id == %@", fixtureUUID(fixtureId) as CVarArg)
        let results = try context.fetch(request)
        return try XCTUnwrap(
            results.first, "No \(entityName) with fixture id \(fixtureId) in the store"
        )
    }

    private func entityCount(_ entityName: String, in context: NSManagedObjectContext) -> Int {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        return (try? context.count(for: request)) ?? -1
    }

    private func runBackfill(on context: NSManagedObjectContext) {
        context.performAndWait {
            Database.performSetEntryBackfill(in: context)
        }
    }

    /// Asserts one entry's full contents.
    private func assertEntry(
        _ entry: SetEntry,
        order: Int64,
        repetitions: Int64,
        weight: Int64,
        exercise: Exercise?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(entry.order, order, "entry order", file: file, line: line)
        XCTAssertEqual(entry.repetitions, repetitions, "entry repetitions", file: file, line: line)
        XCTAssertEqual(entry.weight, weight, "entry weight", file: file, line: line)
        XCTAssertEqual(entry.duration, 0, "backfilled entries never have a duration", file: file, line: line)
        XCTAssertEqual(entry.type, .repsAndWeight, "backfilled entries are reps+weight", file: file, line: line)
        XCTAssertNotNil(entry.id, "entry id", file: file, line: line)
        XCTAssertEqual(entry.exercise, exercise, "entry exercise", file: file, line: line)
    }

    /// Asserts every legacy value in the fixture is present and unchanged — run both directly
    /// after migration and again after the backfill, since the backfill must be copy-only.
    private func assertLegacyValuesIntact(
        in context: NSManagedObjectContext, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let workout: Workout = try fetch("Workout", fixtureId: 10, in: context)
        XCTAssertEqual(workout.name, "Push Day Legacy", file: file, line: line)
        XCTAssertEqual(
            workout.date?.timeIntervalSince1970, 1_780_315_200, file: file, line: line
        )
        XCTAssertEqual(workout.setGroups.count, 4, file: file, line: line)

        let benchPress: Exercise = try fetch("Exercise", fixtureId: 1, in: context)
        let cableFly: Exercise = try fetch("Exercise", fixtureId: 2, in: context)
        let squat: Exercise = try fetch("Exercise", fixtureId: 3, in: context)
        XCTAssertEqual(benchPress.name, "Bench Press", file: file, line: line)
        XCTAssertEqual(benchPress.muscleGroup, .chest, file: file, line: line)
        XCTAssertEqual(squat.muscleGroup, .legs, file: file, line: line)

        // G1 — standard sets
        let group1: WorkoutSetGroup = try fetch("WorkoutSetGroup", fixtureId: 11, in: context)
        XCTAssertEqual(group1.exercise, benchPress, file: file, line: line)
        XCTAssertEqual(group1.sets.count, 3, file: file, line: line)
        let standard1: StandardSet = try fetch("StandardSet", fixtureId: 21, in: context)
        XCTAssertEqual(standard1.repetitions, 12, file: file, line: line)
        XCTAssertEqual(standard1.weight, 80000, file: file, line: line)
        XCTAssertEqual(standard1.restDuration, 90, file: file, line: line)
        let standard2: StandardSet = try fetch("StandardSet", fixtureId: 22, in: context)
        XCTAssertEqual(standard2.repetitions, 0, file: file, line: line)
        XCTAssertEqual(standard2.weight, 0, file: file, line: line)
        let standard3: StandardSet = try fetch("StandardSet", fixtureId: 23, in: context)
        XCTAssertEqual(standard3.repetitions, 8, file: file, line: line)
        XCTAssertEqual(standard3.weight, 102_500, file: file, line: line)

        // G2 — drop sets, including malformed shapes
        let drop1: DropSet = try fetch("DropSet", fixtureId: 31, in: context)
        XCTAssertEqual(drop1.repetitions, [10, 8, 6], file: file, line: line)
        XCTAssertEqual(drop1.weights, [140_000, 120_000, 100_000], file: file, line: line)
        XCTAssertEqual(drop1.restDuration, 120, file: file, line: line)
        let drop2: DropSet = try fetch("DropSet", fixtureId: 32, in: context)
        XCTAssertEqual(drop2.repetitions, [10, 8], file: file, line: line)
        XCTAssertEqual(drop2.weights, [60000], file: file, line: line)
        let drop3: DropSet = try fetch("DropSet", fixtureId: 33, in: context)
        XCTAssertEqual(drop3.repetitions, [12], file: file, line: line)
        XCTAssertEqual(drop3.weights, [50000, 40000], file: file, line: line)
        let drop4: DropSet = try fetch("DropSet", fixtureId: 34, in: context)
        XCTAssertNil(drop4.repetitions, file: file, line: line)
        XCTAssertNil(drop4.weights, file: file, line: line)
        let drop5: DropSet = try fetch("DropSet", fixtureId: 35, in: context)
        XCTAssertEqual(drop5.repetitions, [], file: file, line: line)
        XCTAssertEqual(drop5.weights, [], file: file, line: line)

        // G3/G4 — super sets
        let group3: WorkoutSetGroup = try fetch("WorkoutSetGroup", fixtureId: 13, in: context)
        XCTAssertEqual(group3.exercise, benchPress, file: file, line: line)
        XCTAssertEqual(group3.secondaryExercise, cableFly, file: file, line: line)
        let superSet1: SuperSet = try fetch("SuperSet", fixtureId: 41, in: context)
        XCTAssertEqual(superSet1.repetitionsFirstExercise, 10, file: file, line: line)
        XCTAssertEqual(superSet1.weightFirstExercise, 80000, file: file, line: line)
        XCTAssertEqual(superSet1.repetitionsSecondExercise, 12, file: file, line: line)
        XCTAssertEqual(superSet1.weightSecondExercise, 25000, file: file, line: line)
        XCTAssertEqual(superSet1.restDuration, 180, file: file, line: line)
        let superSet3: SuperSet = try fetch("SuperSet", fixtureId: 43, in: context)
        XCTAssertEqual(superSet3.repetitionsFirstExercise, 8, file: file, line: line)
        XCTAssertEqual(superSet3.weightFirstExercise, 30000, file: file, line: line)
        XCTAssertEqual(superSet3.repetitionsSecondExercise, 15, file: file, line: line)
        XCTAssertEqual(superSet3.weightSecondExercise, 10000, file: file, line: line)
        XCTAssertNil(superSet3.setGroup?.secondaryExercise, file: file, line: line)

        // Orphan sets
        let orphanStandard: StandardSet = try fetch("StandardSet", fixtureId: 51, in: context)
        XCTAssertNil(orphanStandard.setGroup, file: file, line: line)
        XCTAssertEqual(orphanStandard.repetitions, 5, file: file, line: line)
        XCTAssertEqual(orphanStandard.weight, 200_000, file: file, line: line)
        let orphanDrop: DropSet = try fetch("DropSet", fixtureId: 52, in: context)
        XCTAssertNil(orphanDrop.setGroup, file: file, line: line)
        XCTAssertEqual(orphanDrop.repetitions, [3, 2], file: file, line: line)
        XCTAssertEqual(orphanDrop.weights, [180_000, 190_000], file: file, line: line)

        // Template mirrors
        let template: Template = try fetch("Template", fixtureId: 60, in: context)
        XCTAssertEqual(template.name, "Push Template Legacy", file: file, line: line)
        XCTAssertEqual(template.setGroups.count, 3, file: file, line: line)
        let templateStandard: TemplateStandardSet =
            try fetch("TemplateStandardSet", fixtureId: 71, in: context)
        XCTAssertEqual(templateStandard.repetitions, 10, file: file, line: line)
        XCTAssertEqual(templateStandard.weight, 77500, file: file, line: line)
        XCTAssertEqual(templateStandard.restDuration, 60, file: file, line: line)
        let templateDrop: TemplateDropSet =
            try fetch("TemplateDropSet", fixtureId: 72, in: context)
        XCTAssertEqual(templateDrop.repetitions, [9, 7], file: file, line: line)
        XCTAssertEqual(templateDrop.weights, [130_000], file: file, line: line)
        let templateSuper: TemplateSuperSet =
            try fetch("TemplateSuperSet", fixtureId: 73, in: context)
        XCTAssertEqual(templateSuper.repetitionsFirstExercise, 8, file: file, line: line)
        XCTAssertEqual(templateSuper.weightFirstExercise, 70000, file: file, line: line)
        XCTAssertEqual(templateSuper.repetitionsSecondExercise, 10, file: file, line: line)
        XCTAssertEqual(templateSuper.weightSecondExercise, 20000, file: file, line: line)
    }

    // MARK: - Migration

    func testLegacyStoreOpensUnderCurrentModelViaLightweightMigration() throws {
        let container = try openMigratedStore()
        let context = container.viewContext

        XCTAssertEqual(entityCount("WorkoutSet", in: context), 13)
        XCTAssertEqual(entityCount("StandardSet", in: context), 4)
        XCTAssertEqual(entityCount("DropSet", in: context), 6)
        XCTAssertEqual(entityCount("SuperSet", in: context), 3)
        XCTAssertEqual(entityCount("TemplateSet", in: context), 3)
        XCTAssertEqual(entityCount("Exercise", in: context), 3)
        // The schema migration itself must not invent any rows — entries only ever come
        // from the explicit backfill.
        XCTAssertEqual(entityCount("SetEntry", in: context), 0)
        XCTAssertEqual(entityCount("TemplateSetEntry", in: context), 0)
    }

    func testMigrationPreservesEveryLegacyValue() throws {
        let container = try openMigratedStore()
        try assertLegacyValuesIntact(in: container.viewContext)
    }

    // MARK: - Backfill

    func testBackfillCreatesEntriesForEveryLegacySet() throws {
        let container = try openMigratedStore()
        let context = container.viewContext
        runBackfill(on: context)

        XCTAssertEqual(entityCount("SetEntry", in: context), 21)
        XCTAssertEqual(entityCount("TemplateSetEntry", in: context), 5)

        let benchPress: Exercise = try fetch("Exercise", fixtureId: 1, in: context)
        let cableFly: Exercise = try fetch("Exercise", fixtureId: 2, in: context)
        let squat: Exercise = try fetch("Exercise", fixtureId: 3, in: context)

        // Standard sets → one entry each
        let standard1: StandardSet = try fetch("StandardSet", fixtureId: 21, in: context)
        XCTAssertEqual(standard1.entries.count, 1)
        assertEntry(standard1.entries[0], order: 0, repetitions: 12, weight: 80000, exercise: benchPress)
        let standard2: StandardSet = try fetch("StandardSet", fixtureId: 22, in: context)
        XCTAssertEqual(standard2.entries.count, 1)
        assertEntry(standard2.entries[0], order: 0, repetitions: 0, weight: 0, exercise: benchPress)

        // Drop sets → one entry per drop, malformed arrays padded, never truncated
        let drop1: DropSet = try fetch("DropSet", fixtureId: 31, in: context)
        XCTAssertEqual(drop1.entries.count, 3)
        assertEntry(drop1.entries[0], order: 0, repetitions: 10, weight: 140_000, exercise: squat)
        assertEntry(drop1.entries[1], order: 1, repetitions: 8, weight: 120_000, exercise: squat)
        assertEntry(drop1.entries[2], order: 2, repetitions: 6, weight: 100_000, exercise: squat)
        let drop2: DropSet = try fetch("DropSet", fixtureId: 32, in: context)
        XCTAssertEqual(drop2.entries.count, 2, "reps-longer drop set keeps every recorded value")
        assertEntry(drop2.entries[0], order: 0, repetitions: 10, weight: 60000, exercise: squat)
        assertEntry(drop2.entries[1], order: 1, repetitions: 8, weight: 0, exercise: squat)
        let drop3: DropSet = try fetch("DropSet", fixtureId: 33, in: context)
        XCTAssertEqual(drop3.entries.count, 2, "weights-longer drop set keeps every recorded value")
        assertEntry(drop3.entries[0], order: 0, repetitions: 12, weight: 50000, exercise: squat)
        assertEntry(drop3.entries[1], order: 1, repetitions: 0, weight: 40000, exercise: squat)
        let drop4: DropSet = try fetch("DropSet", fixtureId: 34, in: context)
        XCTAssertEqual(drop4.entries.count, 1, "nil-array drop set gets its placeholder entry")
        assertEntry(drop4.entries[0], order: 0, repetitions: 0, weight: 0, exercise: squat)
        let drop5: DropSet = try fetch("DropSet", fixtureId: 35, in: context)
        XCTAssertEqual(drop5.entries.count, 1, "empty-array drop set gets its placeholder entry")

        // Super sets → two entries, attributed to primary/secondary exercise
        let superSet1: SuperSet = try fetch("SuperSet", fixtureId: 41, in: context)
        XCTAssertEqual(superSet1.entries.count, 2)
        assertEntry(superSet1.entries[0], order: 0, repetitions: 10, weight: 80000, exercise: benchPress)
        assertEntry(superSet1.entries[1], order: 1, repetitions: 12, weight: 25000, exercise: cableFly)
        let superSet2: SuperSet = try fetch("SuperSet", fixtureId: 42, in: context)
        XCTAssertEqual(superSet2.entries.count, 2)
        assertEntry(superSet2.entries[0], order: 0, repetitions: 0, weight: 0, exercise: benchPress)
        assertEntry(superSet2.entries[1], order: 1, repetitions: 0, weight: 0, exercise: cableFly)
        // The group without a secondary exercise: second-slot values survive with no exercise
        let superSet3: SuperSet = try fetch("SuperSet", fixtureId: 43, in: context)
        XCTAssertEqual(superSet3.entries.count, 2)
        assertEntry(superSet3.entries[0], order: 0, repetitions: 8, weight: 30000, exercise: cableFly)
        assertEntry(superSet3.entries[1], order: 1, repetitions: 15, weight: 10000, exercise: nil)

        // Orphan sets: entries exist, no exercise attribution
        let orphanStandard: StandardSet = try fetch("StandardSet", fixtureId: 51, in: context)
        XCTAssertEqual(orphanStandard.entries.count, 1)
        assertEntry(orphanStandard.entries[0], order: 0, repetitions: 5, weight: 200_000, exercise: nil)
        let orphanDrop: DropSet = try fetch("DropSet", fixtureId: 52, in: context)
        XCTAssertEqual(orphanDrop.entries.count, 2)
        assertEntry(orphanDrop.entries[0], order: 0, repetitions: 3, weight: 180_000, exercise: nil)
        assertEntry(orphanDrop.entries[1], order: 1, repetitions: 2, weight: 190_000, exercise: nil)

        // Template mirrors
        let templateStandard: TemplateStandardSet =
            try fetch("TemplateStandardSet", fixtureId: 71, in: context)
        XCTAssertEqual(templateStandard.entries.count, 1)
        XCTAssertEqual(templateStandard.entries[0].repetitions, 10)
        XCTAssertEqual(templateStandard.entries[0].weight, 77500)
        XCTAssertEqual(templateStandard.entries[0].exercise, benchPress)
        XCTAssertEqual(templateStandard.entries[0].type, .repsAndWeight)
        let templateDrop: TemplateDropSet =
            try fetch("TemplateDropSet", fixtureId: 72, in: context)
        XCTAssertEqual(templateDrop.entries.count, 2)
        XCTAssertEqual(templateDrop.entries[0].repetitions, 9)
        XCTAssertEqual(templateDrop.entries[0].weight, 130_000)
        XCTAssertEqual(templateDrop.entries[1].repetitions, 7)
        XCTAssertEqual(templateDrop.entries[1].weight, 0)
        let templateSuper: TemplateSuperSet =
            try fetch("TemplateSuperSet", fixtureId: 73, in: context)
        XCTAssertEqual(templateSuper.entries.count, 2)
        XCTAssertEqual(templateSuper.entries[0].repetitions, 8)
        XCTAssertEqual(templateSuper.entries[0].weight, 70000)
        XCTAssertEqual(templateSuper.entries[0].exercise, benchPress)
        XCTAssertEqual(templateSuper.entries[1].repetitions, 10)
        XCTAssertEqual(templateSuper.entries[1].weight, 20000)
        XCTAssertEqual(templateSuper.entries[1].exercise, cableFly)

        // Every set — workout and template — now has at least one entry
        let allSets: [WorkoutSet] =
            try context.fetch(NSFetchRequest<WorkoutSet>(entityName: "WorkoutSet"))
        XCTAssertTrue(allSets.allSatisfy { !$0.entries.isEmpty })
        let allTemplateSets: [TemplateSet] =
            try context.fetch(NSFetchRequest<TemplateSet>(entityName: "TemplateSet"))
        XCTAssertTrue(allTemplateSets.allSatisfy { !$0.entries.isEmpty })
    }

    func testBackfillLeavesLegacyFieldsUntouched() throws {
        let container = try openMigratedStore()
        runBackfill(on: container.viewContext)
        // The backfill is copy-only: after it ran, every legacy value must still read exactly
        // as it did before.
        try assertLegacyValuesIntact(in: container.viewContext)
    }

    func testBackfillIsIdempotent() throws {
        let container = try openMigratedStore()
        let context = container.viewContext
        runBackfill(on: context)
        runBackfill(on: context)
        runBackfill(on: context)

        XCTAssertEqual(entityCount("SetEntry", in: context), 21)
        XCTAssertEqual(entityCount("TemplateSetEntry", in: context), 5)
        let drop1: DropSet = try fetch("DropSet", fixtureId: 31, in: context)
        XCTAssertEqual(drop1.entries.count, 3)
    }

    func testBackfillPicksUpLateArrivingLegacySets() throws {
        // Old-version devices keep syncing legacy-shaped sets after the first sweep — the
        // reconciliation sweep must materialize entries for those, and only those.
        let container = try openMigratedStore()
        let context = container.viewContext
        runBackfill(on: context)
        XCTAssertEqual(entityCount("SetEntry", in: context), 21)

        try context.performAndWait {
            let group1: WorkoutSetGroup = try fetch("WorkoutSetGroup", fixtureId: 11, in: context)
            let standardEntity = try XCTUnwrap(
                NSEntityDescription.entity(forEntityName: "StandardSet", in: context)
            )
            let lateSet = StandardSet(entity: standardEntity, insertInto: context)
            lateSet.id = UUID()
            lateSet.repetitions = 9
            lateSet.weight = 55000
            lateSet.setGroup = group1

            let templateSuperEntity = try XCTUnwrap(
                NSEntityDescription.entity(forEntityName: "TemplateSuperSet", in: context)
            )
            let lateTemplateSet = TemplateSuperSet(
                entity: templateSuperEntity, insertInto: context
            )
            lateTemplateSet.id = UUID()
            lateTemplateSet.repetitionsFirstExercise = 6
            lateTemplateSet.weightFirstExercise = 42000
            try context.save()
        }

        runBackfill(on: context)
        XCTAssertEqual(entityCount("SetEntry", in: context), 22)
        XCTAssertEqual(entityCount("TemplateSetEntry", in: context), 7)

        let lateSets: [StandardSet] = try context.fetch(
            {
                let request = NSFetchRequest<StandardSet>(entityName: "StandardSet")
                request.predicate = NSPredicate(format: "repetitions == 9 AND weight == 55000")
                return request
            }()
        )
        let lateSet = try XCTUnwrap(lateSets.first)
        XCTAssertEqual(lateSet.entries.count, 1)
        XCTAssertEqual(lateSet.entries[0].repetitions, 9)
        XCTAssertEqual(lateSet.entries[0].weight, 55000)
    }

    func testBackfillDoesNotTouchSetsThatAlreadyHaveEntries() throws {
        // A set that already has entries is new-format data — the sweep must never add to or
        // alter it, no matter what its legacy fields say.
        let container = try openMigratedStore()
        let context = container.viewContext

        let newFormatSetID: NSManagedObjectID = try context.performAndWait {
            let standardEntity = try XCTUnwrap(
                NSEntityDescription.entity(forEntityName: "StandardSet", in: context)
            )
            let newFormatSet = StandardSet(entity: standardEntity, insertInto: context)
            newFormatSet.id = UUID()
            newFormatSet.repetitions = 1
            newFormatSet.weight = 1000

            let entryEntity = try XCTUnwrap(
                NSEntityDescription.entity(forEntityName: "SetEntry", in: context)
            )
            let entry = SetEntry(entity: entryEntity, insertInto: context)
            entry.id = UUID()
            entry.order = 0
            entry.typeString = SetMeasurementType.repsAndWeight.rawValue
            entry.repetitions = 99
            entry.weight = 999_000
            entry.workoutSet = newFormatSet
            try context.save()
            return newFormatSet.objectID
        }

        runBackfill(on: context)

        let newFormatSet = try XCTUnwrap(
            try context.existingObject(with: newFormatSetID) as? StandardSet
        )
        XCTAssertEqual(newFormatSet.entries.count, 1)
        XCTAssertEqual(newFormatSet.entries[0].repetitions, 99)
        XCTAssertEqual(newFormatSet.entries[0].weight, 999_000)
        // 21 fixture entries + the one we created — the sweep added nothing for this set.
        XCTAssertEqual(entityCount("SetEntry", in: context), 22)
    }
}
