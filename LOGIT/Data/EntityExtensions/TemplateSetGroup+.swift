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
            return (setOrder ?? .emptyList)
                .compactMap { id in (sets_?.allObjects as? [TemplateSet])?.first { $0.id == id } }
        }
        set {
            setOrder = newValue.map { $0.id! }
            sets_ = NSSet(array: newValue)
        }
    }

    private var exercises: [Exercise] {
        get {
            return (exerciseOrder ?? .emptyList)
                .compactMap { id in (exercises_?.allObjects as? [Exercise])?.first { $0.id == id } }
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

    func index(of set: TemplateSet) -> Int? {
        sets.firstIndex(of: set)
    }
}
