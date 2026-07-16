//
//  TemplateDropSet+.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 15.05.22.
//

import Foundation

public extension TemplateDropSet {
    /// Appends an empty drop — see `DropSet.addDrop()`.
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
        last.templateSet = nil
        managedObjectContext?.delete(last)
    }

    // MARK: Legacy-field fallbacks (see TemplateSet.hasEntry)

    internal override var legacyHasEntry: Bool {
        (repetitions?.reduce(0, +) ?? 0) + (weights?.reduce(0, +) ?? 0) > 0
    }
}
