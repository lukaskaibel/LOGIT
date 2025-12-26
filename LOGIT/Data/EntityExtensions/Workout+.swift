//
//  Workout+.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 01.07.21.
//

import Foundation
import Ifrit

// MARK: - Searchable Conformance

extension Workout: Searchable {
    public var properties: [FuseProp] {
        var props: [FuseProp] = []
        if let name = name {
            props.append(FuseProp(name, weight: 1.0))
        }
        let exerciseNames = exercises.compactMap { $0.displayName }.joined(separator: " ")
        if !exerciseNames.isEmpty {
            props.append(FuseProp(exerciseNames, weight: 0.5))
        }
        return props.isEmpty ? [FuseProp("")] : props
    }
}

// MARK: - Workout Extension

extension Workout {
    var numberOfSets: Int {
        sets.count
    }

    var numberOfSetGroups: Int {
        setGroups.count
    }

    var isEmpty: Bool {
        setGroups.isEmpty
    }

    var setGroups: [WorkoutSetGroup] {
        get {
            return (setGroupOrder ?? .emptyList)
                .compactMap { id in
                    (setGroups_?.allObjects as? [WorkoutSetGroup])?
                        .first { setGroup in
                            setGroup.id == id
                        }
                }
        }
        set {
            setGroupOrder = newValue.map { $0.id! }
            setGroups_ = NSSet(array: newValue)
        }
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

    var sets: [WorkoutSet] {
        var result = [WorkoutSet]()
        for setGroup in setGroups {
            result.append(contentsOf: setGroup.sets)
        }
        return result
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

    func remove(setGroup: WorkoutSetGroup) {
        setGroups = setGroups.filter { $0 != setGroup }
    }

    func index(of setGroup: WorkoutSetGroup) -> Int? {
        setGroups.firstIndex(of: setGroup)
    }

    var hasEntries: Bool {
        sets.filter { !$0.hasEntry }.count != numberOfSets
    }

    var allSetsHaveEntries: Bool {
        sets.filter { !$0.hasEntry }.isEmpty
    }

    static func getStandardName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        let weekday = formatter.string(from: date)
        let hour = Calendar.current.component(.hour, from: date)
        let daytime: String
        switch hour {
        case 6 ..< 12: daytime = NSLocalizedString("morning", comment: "")
        case 12 ..< 14: daytime = NSLocalizedString("noon", comment: "")
        case 14 ..< 17: daytime = NSLocalizedString("afternoon", comment: "")
        case 17 ..< 22: daytime = NSLocalizedString("evening", comment: "")
        default: daytime = NSLocalizedString("night", comment: "")
        }
        return "\(weekday) \(daytime) Workout"
    }
}
