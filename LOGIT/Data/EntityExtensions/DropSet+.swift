//
//  DropSet+.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 13.05.22.
//

import Foundation

public extension DropSet {
    var numberOfDrops: Int {
        entryValues.count
    }

    /// Appends an empty drop. Materializes entries first so a not-yet-swept legacy set keeps
    /// every legacy value before its structure changes.
    func addDrop() {
        ensureEntries()
        let entries = entries
        insertEntry(
            from: SetEntryValues(
                type: entries.last?.type ?? setGroup?.exercise?.measurementType ?? .repsAndWeight,
                order: (entries.last?.order ?? -1) + 1,
                repetitions: 0,
                weight: 0,
                durationMs: 0,
                exercise: setGroup?.exercise
            )
        )
    }

    /// Removes the last drop — a drop set always keeps at least one.
    func removeLastDrop() {
        ensureEntries()
        let entries = entries
        guard entries.count > 1, let last = entries.last else { return }
        last.workoutSet = nil
        managedObjectContext?.delete(last)
    }

    // MARK: Legacy repetition arrays

    /// The per-drop repetitions, wherever they currently live.
    ///
    /// `dropRepetitions` is the field this app writes; `repetitions` is the pre-v11 one it is
    /// being moved off. The two never hold a value at the same time — `Database.migrateDropSetRepetitions`
    /// moves each set across exactly once and clears the old field — so reading the new one first
    /// is unambiguous rather than a merge.
    ///
    /// The move exists because CloudKit flattens Core Data inheritance: `DropSet` and
    /// `StandardSet` share one record type, where `CD_repetitions` was already claimed as
    /// `NUMBER_INT64` by `StandardSet`. A drop set's array of reps could never be written to it,
    /// so drop sets could not sync at all. The differently-named field is the fix.
    var resolvedRepetitions: [Int64]? {
        dropRepetitions ?? repetitions
    }

    // MARK: Legacy-field fallbacks (see WorkoutSet.hasEntry & friends)

    internal override var legacyHasEntry: Bool {
        (resolvedRepetitions?.reduce(0, +) ?? 0) > 0 || (weights?.reduce(0, +) ?? 0) > 0
    }

    internal override var legacyHasRepetitionEntry: Bool {
        (resolvedRepetitions?.reduce(0, +) ?? 0) > 0
    }

    internal override func legacyClearEntries() {
        dropRepetitions = Array(repeating: 0, count: resolvedRepetitions?.count ?? 0)
        repetitions = nil
        weights = Array(repeating: 0, count: weights?.count ?? 0)
    }
}
