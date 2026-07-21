//
//  WorkoutSet+.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 06.05.22.
//

import CoreData
import Foundation

/// A value-level snapshot of one set entry — what was (or is planned to be) performed once.
///
/// This is the one shape every reader consumes: sets with `SetEntry` rows produce it from
/// those, and legacy-shaped sets (pre-v8 data or old-device sync arrivals the reconciliation
/// sweep hasn't reached yet) derive it from their per-subclass legacy fields. The legacy
/// derivation here is also what the backfill persists, so the two can never disagree.
struct SetEntryValues: Equatable {
    var type: SetMeasurementType
    var order: Int64
    var repetitions: Int64
    var weight: Int64
    var duration: Int64
    var exercise: Exercise?

    /// Mirror of `SetEntry.hasPerformanceValue` for value-level reads.
    var hasPerformanceValue: Bool {
        if type.usesRepetitions { return repetitions > 0 }
        if type.usesDuration { return duration > 0 }
        return false
    }
}

public extension WorkoutSet {
    enum Attribute: String {
        case repetitions, weight, duration
    }

    static func == (lhs: WorkoutSet, rhs: WorkoutSet) -> Bool {
        return lhs.objectID == rhs.objectID
    }

    /// Rest duration in seconds after completing this set. 0 means no rest defined.
    var restDurationSeconds: Int {
        get { Int(restDuration) }
        set { restDuration = Int64(newValue) }
    }

    var exercise: Exercise? {
        setGroup?.exercise
    }

    var workout: Workout? {
        setGroup?.workout
    }

    var previousSetInSetGroup: WorkoutSet? {
        setGroup?.sets.value(at: (setGroup?.sets.firstIndex(of: self) ?? 0) - 1)
    }

    // MARK: - Entries

    /// The set's entries in stable order. After the v8 backfill every set has at least one
    /// entry; legacy-shaped sets synced from devices on older app versions may briefly have
    /// none until the reconciliation sweep materializes them — readers must treat an empty
    /// list as "legacy fields are still the truth" (which `entryValues` does), never as
    /// "no data".
    var entries: [SetEntry] {
        ((entries_ as? Set<SetEntry>) ?? [])
            .sorted {
                ($0.order, $0.id?.uuidString ?? "") < ($1.order, $1.id?.uuidString ?? "")
            }
    }

    /// Value-level view of the set's entries, deriving from the legacy per-subclass fields
    /// when the set has no `SetEntry` rows yet. All metric and volume reads go through this,
    /// so an unswept legacy set reads identically to its backfilled self.
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

    /// The legacy fields expressed as entry values — the single definition of how pre-v8 set
    /// data maps onto entries. `ensureEntries()` (and with it the migration backfill) persists
    /// exactly this, so changing the mapping here changes it everywhere.
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
        if let dropSet = self as? DropSet {
            let repetitions = dropSet.repetitions ?? []
            let weights = dropSet.weights ?? []
            // Pad to the longer array so a malformed drop set (desynced lengths) keeps every
            // recorded value; a drop set with no arrays still reads as one placeholder entry.
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
        if let superSet = self as? SuperSet {
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
        // StandardSet — and any unknown future subclass, which still reads as one placeholder
        // entry so the "every set has at least one entry" invariant holds.
        let standardSet = self as? StandardSet
        return [
            values(
                order: 0,
                repetitions: standardSet?.repetitions ?? 0,
                weight: standardSet?.weight ?? 0,
                exercise: setGroup?.exercise
            )
        ]
    }

    /// The exercise an entry trains. Prefers the entry's own relationship; entries without one
    /// (backfilled from sets whose group had no exercise at sweep time) fall back positionally.
    internal func owningExercise(of entry: SetEntry) -> Exercise? {
        entry.exercise ?? positionalExercise(forOrder: entry.order)
    }

    /// Positional exercise attribution: compound sets map entry order to the group's exercise
    /// order, all other sets train the group's primary exercise.
    internal func positionalExercise(forOrder order: Int64) -> Exercise? {
        if self is SuperSet {
            return order == 0 ? setGroup?.exercise : setGroup?.secondaryExercise
        }
        return setGroup?.exercise
    }

    /// Inserts one `SetEntry` row from a value snapshot. Resolves the entity from the
    /// context's own model instead of `SetEntry(context:)`: the `+entity` lookup breaks as
    /// soon as a second model copy exists in the process, while this is always unambiguous.
    @discardableResult
    internal func insertEntry(from values: SetEntryValues) -> SetEntry? {
        guard
            let context = managedObjectContext,
            let entity = NSEntityDescription.entity(forEntityName: "SetEntry", in: context)
        else { return nil }
        let entry = SetEntry(entity: entity, insertInto: context)
        entry.id = UUID()
        entry.order = values.order
        entry.type = values.type
        entry.repetitions = values.repetitions
        entry.weight = values.weight
        entry.duration = values.duration
        entry.exercise = values.exercise
        entry.workoutSet = self
        return entry
    }

    /// Deletes all entries, severing the inverse first: a deleted object only leaves its
    /// relationships at `processPendingChanges`, so without severing, same-runloop readers
    /// (and the rebuild that follows a match or convert) would still see the dead entries.
    internal func removeAllEntries() {
        for entry in entries {
            entry.workoutSet = nil
            managedObjectContext?.delete(entry)
        }
    }

    /// Materializes `SetEntry` rows from the legacy fields if the set has none. Copy-only and
    /// idempotent — this is the per-set heart of the migration backfill, and mutating callers
    /// (cells, drop editing) run it first so a not-yet-swept legacy set can never lose its
    /// legacy values to a partial edit.
    func ensureEntries() {
        guard entries.isEmpty else { return }
        legacyEntryValues.forEach { insertEntry(from: $0) }
    }

    internal func isTraining(_ muscleGroup: MuscleGroup) -> Bool {
        setGroup?.exercise?.muscleGroup == muscleGroup
            || setGroup?.secondaryExercise?.muscleGroup == muscleGroup
    }

    // MARK: - Metrics

    /// The best value of `attribute` among this set's entries for the given exercise.
    /// Legacy-shaped sets read through the same derivation, so `.duration` is simply 0 there.
    internal func maximum(_ attribute: WorkoutSet.Attribute, for exercise: Exercise) -> Int {
        entryValues
            .filter { $0.exercise == exercise }
            .map { value in
                switch attribute {
                case .repetitions: return Int(value.repetitions)
                case .weight: return Int(value.weight)
                case .duration: return Int(value.duration)
                }
            }
            .max() ?? 0
    }

    /// Best estimated one-rep max achievable from this set's entries for the given exercise,
    /// in the same unit as `weight` (grams). Returns 0 when there is no usable weight ×
    /// repetitions entry — e.g. a pure bodyweight or duration set, or an empty set. The
    /// estimate itself comes from the shared `OneRepMax.estimated(weight:repetitions:)`.
    internal func estimatedOneRepMax(for exercise: Exercise) -> Int {
        estimatedOneRepMaxEntry(for: exercise).oneRepMax
    }

    /// The best e1RM for `exercise` together with the weight and repetitions that produced it.
    /// For drop sets the single drop with the highest estimate wins; for super sets the
    /// matching exercise's entry.
    internal func estimatedOneRepMaxEntry(
        for exercise: Exercise
    ) -> (oneRepMax: Int, weight: Int64, repetitions: Int64) {
        var best = (oneRepMax: 0, weight: Int64(0), repetitions: Int64(0))
        for value in entryValues where value.exercise == exercise {
            let oneRepMax = OneRepMax.estimated(weight: value.weight, repetitions: value.repetitions)
            if oneRepMax > best.oneRepMax {
                best = (oneRepMax, value.weight, value.repetitions)
            }
        }
        return best
    }

    /// Volume (weight × repetitions) of this single set for `exercise`, in the same unit as
    /// `weight` (grams). A drop set counts all its drops — it is logged as one set — and a super
    /// set counts only the matching exercise's entry, matching `getVolume(of:for:)`, which this
    /// delegates to. Returns 0 when the exercise isn't part of this set.
    internal func volume(for exercise: Exercise) -> Int {
        getVolume(of: [self], for: exercise)
    }

    /// The entry with the highest *weight* for `exercise`, together with the repetitions
    /// performed at that weight. The `weight` returned equals `maximum(.weight, for:)`.
    /// Returns (0, 0) when the exercise isn't part of this set or recorded no weight.
    internal func maxWeightEntry(for exercise: Exercise) -> (weight: Int64, repetitions: Int64) {
        var best = (weight: Int64(0), repetitions: Int64(0))
        for value in entryValues where value.exercise == exercise && value.weight > best.weight {
            best = (value.weight, value.repetitions)
        }
        return best
    }

    /// The entry with the highest *repetitions* for `exercise`, together with the weight used
    /// for those repetitions. Counterpart to `maxWeightEntry(for:)`; the `repetitions` returned
    /// equals `maximum(.repetitions, for:)`.
    internal func maxRepetitionsEntry(for exercise: Exercise) -> (repetitions: Int64, weight: Int64) {
        var best = (repetitions: Int64(0), weight: Int64(0))
        for value in entryValues
        where value.exercise == exercise && value.repetitions > best.repetitions {
            best = (value.repetitions, value.weight)
        }
        return best
    }

    var isSuperSet: Bool { (self as? SuperSet) != nil }
    var isDropSet: Bool { (self as? DropSet) != nil }

    /// The set's effective measurement type — its first entry's stored type.
    internal var measurementType: SetMeasurementType {
        entryValues.first?.type ?? .repsAndWeight
    }

    /// Re-types this one set's entries — the single-set override on top of the exercise or
    /// group default. Values are never cleared: fields the new type doesn't track stay stored
    /// (and invisible), so switching back restores them.
    internal func overrideMeasurementType(_ type: SetMeasurementType) {
        ensureEntries()
        entries.forEach { $0.type = type }
    }

    // MARK: - Matching

    /// Copies the template's planned entries into this set (recorder prefill / duplication).
    func match(_ templateSet: TemplateSet) {
        matchEntries(to: templateSet.entryValues)
        restDuration = templateSet.restDuration
    }

    /// Copies another workout set's entries into this set.
    func match(_ workoutSet: WorkoutSet) {
        matchEntries(to: workoutSet.entryValues)
        restDuration = workoutSet.restDuration
    }

    /// Rebuilds this set's entries as copies of the source values. Exercise attribution is
    /// re-resolved against *this* set's group — the source may live in another group (template,
    /// previous workout) whose exercise objects happen to match, but ours are the truth here.
    private func matchEntries(to sourceValues: [SetEntryValues]) {
        removeAllEntries()
        for value in sourceValues {
            var resolved = value
            resolved.exercise = positionalExercise(forOrder: value.order) ?? value.exercise
            insertEntry(from: resolved)
        }
    }

    /// Adopts the source's entry *structure* — count, order, and measurement types — with empty
    /// values. This is how an added set continues its group's shape: a 3-drop set is followed
    /// by a 3-drop set, a duration set by a duration set.
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

    // MARK: - Entry State

    /// True when any entry recorded a value. Legacy-shaped sets fall back to the subclass'
    /// legacy fields.
    @objc var hasEntry: Bool {
        let entries = entries
        guard entries.isEmpty else { return entries.contains { $0.hasValue } }
        return legacyHasEntry
    }

    /// True when the set has a recorded *performance* value — repetitions, or the duration for
    /// time-based entries. (The name predates duration entries; it drives the rest timer and
    /// Live Activity "set performed" signals.)
    @objc var hasRepetitionEntry: Bool {
        let entries = entries
        guard entries.isEmpty else { return entries.contains { $0.hasPerformanceValue } }
        return legacyHasRepetitionEntry
    }

    /// Zeroes all recorded values while keeping the set's structure (entry count and types).
    @objc func clearEntries() {
        let entries = entries
        guard entries.isEmpty else {
            entries.forEach { $0.clearValues() }
            return
        }
        legacyClearEntries()
    }

    // MARK: Legacy-field fallbacks, overridden per subclass

    @objc internal var legacyHasEntry: Bool {
        fatalError("WorkoutSet+: legacyHasEntry must be implemented in subclass of WorkoutSet")
    }

    @objc internal var legacyHasRepetitionEntry: Bool {
        fatalError("WorkoutSet+: legacyHasRepetitionEntry must be implemented in subclass of WorkoutSet")
    }

    @objc internal func legacyClearEntries() {
        fatalError("WorkoutSet+: legacyClearEntries must be implemented in subclass of WorkoutSet")
    }
}
