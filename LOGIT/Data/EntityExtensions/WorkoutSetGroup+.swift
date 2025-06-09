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
            return (setOrder ?? .emptyList)
                .compactMap { id in (sets_?.allObjects as? [WorkoutSet])?.first { $0.id == id } }
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
            return (exerciseOrder ?? .emptyList)
                .compactMap { id in (exercises_?.allObjects as? [Exercise])?.first { $0.id == id } }
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

    subscript(index: Int) -> WorkoutSet { sets[index] }

    func index(of set: WorkoutSet) -> Int? {
        sets.firstIndex(of: set)
    }
}
