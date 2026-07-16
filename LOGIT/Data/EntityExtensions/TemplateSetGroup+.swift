//
//  TemplateSetGroup+.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 02.04.22.
//

import Foundation

extension TemplateSetGroup {
    enum SetType: String {
        case standard, superSet, dropSet

        var description: String {
            NSLocalizedString(rawValue, comment: "")
        }
    }

    public var sets: [TemplateSet] {
        get {
            resolvedOrder(of: sets_, by: setOrder)
        }
        set {
            setOrder = newValue.map { $0.id! }
            sets_ = NSSet(array: newValue)
        }
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

    public var exercise: Exercise? {
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
            reattributeEntries()
        }
    }

    public var secondaryExercise: Exercise? {
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
            reattributeEntries()
        }
    }

    /// Mirror of `WorkoutSetGroup.reattributeEntries()` — see there.
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

    var muscleGroups: [MuscleGroup] {
        Array(Set(exercises.compactMap { $0.muscleGroup }))
    }

    var setType: SetType {
        let firstSet = sets.first
        if let _ = firstSet as? TemplateDropSet {
            return .dropSet
        } else if let _ = firstSet as? TemplateSuperSet {
            return .superSet
        } else {
            return .standard
        }
    }

    /// Mirror of `WorkoutSetGroup.measurementType`.
    var measurementType: SetMeasurementType {
        sets.first?.entryValues.first?.type ?? exercise?.measurementType ?? .repsAndWeight
    }

    /// Mirror of `WorkoutSetGroup.overrideMeasurementType(_:)` — values are never cleared.
    func overrideMeasurementType(_ type: SetMeasurementType) {
        for set in sets {
            set.ensureEntries()
            set.entries.forEach { $0.type = type }
        }
    }

    func index(of set: TemplateSet) -> Int? {
        sets.firstIndex(of: set)
    }
}
