//
//  Template+.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 02.04.22.
//

import Foundation

extension Template {
    var workouts: [Workout] {
        get {
            (workouts_?.allObjects as? [Workout] ?? .emptyList)
                .sorted {
                    $0.date ?? .now < $1.date ?? .now
                }
        }
        set {
            workouts_ = NSSet(array: newValue)
        }
    }

    var lastUsed: Date? {
        return workouts.last?.date
    }

    var sets: [TemplateSet] {
        var result = [TemplateSet]()
        for setGroup in setGroups {
            result.append(contentsOf: setGroup.sets)
        }
        return result
    }

    var setGroups: [TemplateSetGroup] {
        get {
            return (templateSetGroupOrder ?? .emptyList)
                .compactMap { id in
                    (setGroups_?.allObjects as? [TemplateSetGroup])?
                        .first { templateSetGroup in
                            templateSetGroup.id == id
                        }
                }
        }
        set {
            templateSetGroupOrder = newValue.map { $0.id! }
            setGroups_ = NSSet(array: newValue)
        }
    }

    var numberOfSetGroups: Int {
        setGroups.count
    }

    var exercises: [Exercise] {
        var result = [Exercise]()
        for setGroup in setGroups {
            if let exercise = setGroup.exercise {
                result.append(exercise)
            }
            if setGroup.setType == .superSet, let secondaryExercise = setGroup.secondaryExercise {
                result.append(secondaryExercise)
            }
        }
        return result
    }

    func index(of templateSetGroup: TemplateSetGroup) -> Int? {
        setGroups.firstIndex(of: templateSetGroup)
    }

    var muscleGroups: [MuscleGroup] {
        let uniqueMuscleGroups = Array(Set(exercises.compactMap { $0.muscleGroup }))
        return uniqueMuscleGroups.sorted {
            guard let leftIndex = MuscleGroup.allCases.firstIndex(of: $0),
                  let rightIndex = MuscleGroup.allCases.firstIndex(of: $1)
            else {
                return false
            }
            return leftIndex < rightIndex
        }
    }
}
