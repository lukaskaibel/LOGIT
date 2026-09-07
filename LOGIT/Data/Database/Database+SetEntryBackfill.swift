//
//  Database+SetEntryBackfill.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 16.07.26.
//

import CoreData
import OSLog

/// Materializes `SetEntry`/`TemplateSetEntry` rows from the legacy per-subclass set fields
/// (`StandardSet.repetitions/weight`, the `DropSet` arrays, the four `SuperSet` fields, and
/// their template mirrors). The mapping itself lives in `WorkoutSet.legacyEntryValues` /
/// `TemplateSet.legacyEntryValues` and is applied via `ensureEntries()` — the same code path
/// readers fall back to, so backfilled entries can never disagree with how an unswept set reads.
///
/// Invariants — these are what "no data loss" rests on:
/// - **Copy-only.** Legacy fields are never modified or cleared; they remain in the store (and
///   the CloudKit schema, which forbids removal anyway) as the permanent original.
/// - **Idempotent.** Only sets with zero entries are touched, and every touched set receives at
///   least one entry, so a set can never be backfilled twice. Re-running is always safe.
/// - **Lossless for malformed data.** Mismatched drop-set arrays are padded, never truncated:
///   every recorded value ends up in an entry.
/// - **Re-runnable forever.** Devices on pre-v8 app versions keep syncing legacy-shaped sets;
///   the sweep re-runs on remote store changes (see `Database.startSetEntryReconciliation`).
///
/// One accepted asymmetry, inherent to shipping without dual-writes: if an old-version device
/// *edits* a set that already has entries, the edit lands in the legacy fields only, and the
/// entries keep the values from backfill time. Both representations stay persisted — nothing is
/// lost — but the new UI shows the entry values until the set is edited there.
extension Database {
    /// Runs a backfill sweep asynchronously on the serialized backfill context.
    func backfillSetEntries() {
        let context = setEntryBackfillContext
        context.perform {
            Self.performSetEntryBackfill(in: context)
        }
    }

    /// Runs a backfill sweep synchronously — for tests and call sites that need completion.
    func backfillSetEntriesAndWait() {
        let context = setEntryBackfillContext
        context.performAndWait {
            Self.performSetEntryBackfill(in: context)
        }
    }

    /// The sweep itself, callable against any context (tests run it against migrated stores).
    /// Must run on `context`'s queue.
    static func performSetEntryBackfill(in context: NSManagedObjectContext) {
        do {
            migrateDropSetRepetitions(in: context)
            let legacySets = try fetchSetsWithoutEntries(
                entityName: "WorkoutSet", as: WorkoutSet.self, in: context
            )
            let legacyTemplateSets = try fetchSetsWithoutEntries(
                entityName: "TemplateSet", as: TemplateSet.self, in: context
            )
            guard !legacySets.isEmpty || !legacyTemplateSets.isEmpty else { return }

            var processed = 0
            for set in legacySets {
                set.ensureEntries()
                processed += 1
                if processed % 500 == 0 { try context.save() }
            }
            for templateSet in legacyTemplateSets {
                templateSet.ensureEntries()
                processed += 1
                if processed % 500 == 0 { try context.save() }
            }
            if context.hasChanges { try context.save() }
            os_log(
                "Database: Set entry backfill materialized entries for %d legacy sets",
                type: .info, legacySets.count + legacyTemplateSets.count
            )
        } catch {
            // Leave the store untouched and try again on the next sweep — an aborted backfill
            // must never leave partially-entried sets, so roll the unsaved remainder back.
            context.rollback()
            os_log(
                "Database: Set entry backfill failed, will retry on next sweep: %{public}@",
                type: .error, String(describing: error)
            )
        }
    }

    /// Moves every drop set's repetition array off the pre-v11 `repetitions` field and onto
    /// `dropRepetitions`, clearing the old one.
    ///
    /// This is not cosmetic: CloudKit flattens Core Data inheritance, so `DropSet` and
    /// `StandardSet` share the `CD_WorkoutSet` record type, where `CD_repetitions` is defined as
    /// `NUMBER_INT64` because `StandardSet` claimed it. A drop set's array is `BYTES`, the server
    /// rejects it ("invalid attempt to set value type BYTES for field 'CD_repetitions'"), and
    /// because the mirroring delegate treats that as fatal, one such record stalls syncing for
    /// everything behind it. Clearing the old field is what lets those records export at all.
    ///
    /// Invariants, mirroring the entry backfill above:
    /// - **Entries first.** `ensureEntries()` runs before the move, so the values exist as
    ///   `SetEntry` rows — the representation everything reads — before either field changes.
    /// - **Idempotent.** Only sets whose old field is non-nil are touched, and each is left with
    ///   the old field nil, so a second pass finds nothing. Re-running is always safe.
    /// - **Re-runnable forever.** Devices on older app versions keep syncing drop sets shaped the
    ///   old way, so this rides the same remote-change sweep as the entry backfill.
    static func migrateDropSetRepetitions(in context: NSManagedObjectContext) {
        do {
            let dropSets = try context.fetch(NSFetchRequest<DropSet>(entityName: "DropSet"))
                .filter { $0.repetitions != nil }
            let templateDropSets = try context
                .fetch(NSFetchRequest<TemplateDropSet>(entityName: "TemplateDropSet"))
                .filter { $0.repetitions != nil }
            guard !dropSets.isEmpty || !templateDropSets.isEmpty else { return }

            for dropSet in dropSets {
                dropSet.ensureEntries()
                dropSet.dropRepetitions = dropSet.repetitions
                dropSet.repetitions = nil
            }
            for templateDropSet in templateDropSets {
                templateDropSet.ensureEntries()
                templateDropSet.dropRepetitions = templateDropSet.repetitions
                templateDropSet.repetitions = nil
            }
            if context.hasChanges { try context.save() }
            os_log(
                "Database: moved %d drop sets onto the CloudKit-safe repetitions field",
                type: .info, dropSets.count + templateDropSets.count
            )
        } catch {
            context.rollback()
            os_log(
                "Database: drop-set repetition migration failed, will retry on next sweep: %{public}@",
                type: .error, String(describing: error)
            )
        }
    }

    private static func fetchSetsWithoutEntries<T: NSManagedObject>(
        entityName: String,
        as type: T.Type,
        in context: NSManagedObjectContext
    ) throws -> [T] {
        let request = NSFetchRequest<T>(entityName: entityName)
        request.predicate = NSPredicate(format: "entries_.@count == 0")
        return try context.fetch(request)
    }
}
