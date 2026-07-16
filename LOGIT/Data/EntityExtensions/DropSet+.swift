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
                duration: 0,
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

    // MARK: Legacy-field fallbacks (see WorkoutSet.hasEntry & friends)

    internal override var legacyHasEntry: Bool {
        (repetitions?.reduce(0, +) ?? 0) > 0 || (weights?.reduce(0, +) ?? 0) > 0
    }

    internal override var legacyHasRepetitionEntry: Bool {
        (repetitions?.reduce(0, +) ?? 0) > 0
    }

    internal override func legacyClearEntries() {
        repetitions = Array(repeating: 0, count: repetitions?.count ?? 0)
        weights = Array(repeating: 0, count: weights?.count ?? 0)
    }
}
