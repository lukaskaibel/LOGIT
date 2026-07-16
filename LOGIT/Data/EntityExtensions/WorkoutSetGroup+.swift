//
//  WorkoutSetGroup+.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 01.03.22.
//

import Foundation

public extension WorkoutSetGroup {
    enum SetType: String {
        case standard, superSet, dropSet

        var description: String {
            NSLocalizedString(rawValue, comment: "")
        }
    }

    internal var sets: [WorkoutSet] {
        get {
            resolvedOrder(of: sets_, by: setOrder)
        }
        set {
            setOrder = newValue.map { $0.id! }
            sets_ = NSSet(array: newValue)
        }
    }

    var isEmpty: Bool {
        sets.isEmpty
    }

    var numberOfSets: Int {
        sets.count
    }

    private var exercises: [Exercise] {
        get {
            resolvedOrder(of: exercises_, by: exerciseOrder)
        }
        set {
            exerciseOrder = newValue.map { $0.id! }
            exercises_ = NSSet(array: newValue)
        }
    }

    var exercise: Exercise? {
        get {
            exercises.first
        }
        set {
            guard let newExercise = newValue else { return }
            var currentExercises = exercises

            if currentExercises.isEmpty {
                currentExercises = [newExercise]
            } else {
                currentExercises[0] = newExercise
            }
            exercises = currentExercises

            // Ensure inverse ordered relationship on Exercise is kept in sync
            // (Needed because weight / repetitions screens rely on exercise.sets -> exercise.setGroups order list)
            if let id = id {
                var order = newExercise.setGroupOrder ?? []
                if !order.contains(id) { // append if missing
                    order.append(id)
                    newExercise.setGroupOrder = order
                    // also update raw setGroups_ NSSet so Core Data inverse is aware
                    let existing = (newExercise.setGroups_?.allObjects as? [WorkoutSetGroup]) ?? []
                    if !existing.contains(where: { $0 == self }) {
                        newExercise.setGroups_ = NSSet(array: existing + [self])
                    }
                }
            }
            reattributeEntries()
        }
    }

    var secondaryExercise: Exercise? {
        get {
            return exercises.value(at: 1)
        }
        set {
            guard let exercise = newValue else { return }
            var currentExercises = exercises
            if currentExercises.count == 0 {
                currentExercises = [exercise, exercise]
            } else if currentExercises.count == 1 {
                currentExercises.append(exercise)
            } else {
                currentExercises.replaceValue(at: 1, with: exercise)
            }
            exercises = currentExercises

            // Maintain ordered inverse relationship for secondary exercise as well
            if let id = id {
                var order = exercise.setGroupOrder ?? []
                if !order.contains(id) {
                    order.append(id)
                    exercise.setGroupOrder = order
                    let existing = (exercise.setGroups_?.allObjects as? [WorkoutSetGroup]) ?? []
                    if !existing.contains(where: { $0 == self }) {
                        exercise.setGroups_ = NSSet(array: existing + [self])
                    }
                }
            }
            reattributeEntries()
        }
    }

    /// Repairs entry → exercise attribution (and empty entries' measurement type) after the
    /// group's exercises change. Entries denormalize their exercise so compound sets stay
    /// robust when a group's exercises are reordered or swapped — which makes the exercise
    /// setters the one place responsible for keeping those links true. Recorded values keep
    /// their stored type: what was performed never gets reinterpreted.
    internal func reattributeEntries() {
        for set in sets {
            for entry in set.entries {
                let owner = set.positionalExercise(forOrder: entry.order)
                entry.exercise = owner
                if !entry.hasValue, let type = owner?.measurementType {
                    entry.type = type
                }
            }
        }
    }

    internal var muscleGroups: [MuscleGroup] {
        Array(Set(exercises.compactMap { $0.muscleGroup }))
    }

    var setType: SetType {
        let firstSet = sets.first
        if let _ = firstSet as? DropSet {
            return .dropSet
        } else if let _ = firstSet as? SuperSet {
            return .superSet
        } else {
            return .standard
        }
    }

    /// The group's effective measurement type: the first entry's stored type (a group's sets
    /// share one), falling back to the exercise default.
    internal var measurementType: SetMeasurementType {
        sets.first?.entryValues.first?.type ?? exercise?.measurementType ?? .repsAndWeight
    }

    /// Re-types every entry in the group — the per-set override on top of the exercise
    /// default. Values are never cleared: fields the new type doesn't track stay stored (and
    /// invisible), so switching back restores them — recorded data is never lost to a re-type.
    internal func overrideMeasurementType(_ type: SetMeasurementType) {
        for set in sets {
            set.ensureEntries()
            set.entries.forEach { $0.type = type }
        }
    }

    subscript(index: Int) -> WorkoutSet { sets[index] }

    func index(of set: WorkoutSet) -> Int? {
        sets.firstIndex(of: set)
    }
}
