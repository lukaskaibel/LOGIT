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
