//
//  TemplateSet+.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 21.05.22.
//

import CoreData
import Foundation

public extension TemplateSet {
    /// Rest duration in seconds after completing this set. 0 means no rest defined.
    var restDurationSeconds: Int {
        get { Int(restDuration) }
        set { restDuration = Int64(newValue) }
    }

    var exercise: Exercise? {
        setGroup?.exercise
    }

    // MARK: - Entries

    /// The set's entries in stable order. Mirrors `WorkoutSet.entries` — an empty list means
    /// the legacy per-subclass fields are still the truth (see `entryValues`), never "no data".
    var entries: [TemplateSetEntry] {
        ((entries_ as? Set<TemplateSetEntry>) ?? [])
            .sorted {
                ($0.order, $0.id?.uuidString ?? "") < ($1.order, $1.id?.uuidString ?? "")
            }
    }

    /// Value-level view of the set's entries — see `WorkoutSet.entryValues`.
    internal var entryValues: [SetEntryValues] {
        let entries = entries
        guard entries.isEmpty else {
            return entries.map {
                SetEntryValues(
                    type: $0.type,
                    order: $0.order,
                    repetitions: $0.repetitions,
                    weight: $0.weight,
                    duration: $0.duration,
                    exercise: owningExercise(of: $0)
                )
            }
        }
        return legacyEntryValues
    }

    /// The legacy fields expressed as entry values — template mirror of
    /// `WorkoutSet.legacyEntryValues`, with the identical mapping.
    internal var legacyEntryValues: [SetEntryValues] {
        func values(
            order: Int64, repetitions: Int64, weight: Int64, exercise: Exercise?
        ) -> SetEntryValues {
            SetEntryValues(
                type: .repsAndWeight,
                order: order,
                repetitions: repetitions,
                weight: weight,
                duration: 0,
                exercise: exercise
            )
        }
        if let dropSet = self as? TemplateDropSet {
            let repetitions = dropSet.repetitions ?? []
            let weights = dropSet.weights ?? []
            let dropCount = max(repetitions.count, weights.count, 1)
            return (0..<dropCount).map { index in
                values(
                    order: Int64(index),
                    repetitions: repetitions.value(at: index) ?? 0,
                    weight: weights.value(at: index) ?? 0,
                    exercise: setGroup?.exercise
                )
            }
        }
        if let superSet = self as? TemplateSuperSet {
            return [
                values(
                    order: 0,
                    repetitions: superSet.repetitionsFirstExercise,
                    weight: superSet.weightFirstExercise,
                    exercise: setGroup?.exercise
                ),
                values(
                    order: 1,
                    repetitions: superSet.repetitionsSecondExercise,
                    weight: superSet.weightSecondExercise,
                    exercise: setGroup?.secondaryExercise
                ),
            ]
        }
        let standardSet = self as? TemplateStandardSet
        return [
            values(
                order: 0,
                repetitions: standardSet?.repetitions ?? 0,
                weight: standardSet?.weight ?? 0,
                exercise: setGroup?.exercise
            )
        ]
    }

    /// The exercise an entry trains — see `WorkoutSet.owningExercise(of:)`.
    internal func owningExercise(of entry: TemplateSetEntry) -> Exercise? {
        entry.exercise ?? positionalExercise(forOrder: entry.order)
    }

    internal func positionalExercise(forOrder order: Int64) -> Exercise? {
        if self is TemplateSuperSet {
            return order == 0 ? setGroup?.exercise : setGroup?.secondaryExercise
        }
        return setGroup?.exercise
    }

    /// Inserts one `TemplateSetEntry` row from a value snapshot — see
    /// `WorkoutSet.insertEntry(from:)` for the entity-resolution rationale.
    @discardableResult
    internal func insertEntry(from values: SetEntryValues) -> TemplateSetEntry? {
        guard
            let context = managedObjectContext,
            let entity = NSEntityDescription.entity(forEntityName: "TemplateSetEntry", in: context)
        else { return nil }
        let entry = TemplateSetEntry(entity: entity, insertInto: context)
        entry.id = UUID()
        entry.order = values.order
        entry.type = values.type
        entry.repetitions = values.repetitions
        entry.weight = values.weight
        entry.duration = values.duration
        entry.exercise = values.exercise
        entry.templateSet = self
        return entry
    }

    /// Deletes all entries, severing the inverse first — see `WorkoutSet.removeAllEntries()`.
    internal func removeAllEntries() {
        for entry in entries {
            entry.templateSet = nil
            managedObjectContext?.delete(entry)
        }
    }

    /// Materializes `TemplateSetEntry` rows from the legacy fields if the set has none —
    /// see `WorkoutSet.ensureEntries()`.
    func ensureEntries() {
        guard entries.isEmpty else { return }
        legacyEntryValues.forEach { insertEntry(from: $0) }
    }

    // MARK: - Matching

    /// Copies another template set's entries into this set.
    func match(_ templateSet: TemplateSet) {
        removeAllEntries()
        for value in templateSet.entryValues {
            var resolved = value
            resolved.exercise = positionalExercise(forOrder: value.order) ?? value.exercise
            insertEntry(from: resolved)
        }
        restDuration = templateSet.restDuration
    }

    /// Adopts the source's entry structure with empty values — see
    /// `WorkoutSet.matchStructure(toEntryValues:)`.
    internal func matchStructure(toEntryValues sourceValues: [SetEntryValues]) {
        removeAllEntries()
        for value in sourceValues {
            insertEntry(
                from: SetEntryValues(
                    type: value.type,
                    order: value.order,
                    repetitions: 0,
                    weight: 0,
                    duration: 0,
                    exercise: positionalExercise(forOrder: value.order) ?? value.exercise
                )
            )
        }
    }

    /// The set's effective measurement type — its first entry's stored type.
    internal var measurementType: SetMeasurementType {
        entryValues.first?.type ?? .repsAndWeight
    }

    /// Re-types this one set's entries — see `WorkoutSet.overrideMeasurementType(_:)`.
    internal func overrideMeasurementType(_ type: SetMeasurementType) {
        ensureEntries()
        entries.forEach { $0.type = type }
    }

    /// True when any entry recorded a value. Legacy-shaped sets fall back to the subclass'
    /// legacy fields.
    @objc var hasEntry: Bool {
        let entries = entries
        guard entries.isEmpty else { return entries.contains { $0.hasValue } }
        return legacyHasEntry
    }

    @objc internal var legacyHasEntry: Bool {
        fatalError("TemplateSet+: legacyHasEntry must be implemented in subclass of TemplateSet")
    }
}
