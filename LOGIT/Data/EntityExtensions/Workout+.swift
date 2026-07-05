//
//  Workout+.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 01.07.21.
//

import Foundation
import Ifrit

// MARK: - Fuzzy Search Properties

extension Workout {
    var searchProperties: [FuseProp] {
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

// MARK: - Ordered Relationship Resolution

/// Common shape of every entity that lives in an ordered to-many
/// relationship: the id its parent's persisted order list refers to.
protocol UUIDOrderable: NSObject {
    var id: UUID? { get }
}

extension WorkoutSetGroup: UUIDOrderable {}
extension WorkoutSet: UUIDOrderable {}
extension Exercise: UUIDOrderable {}
extension TemplateSetGroup: UUIDOrderable {}
extension TemplateSet: UUIDOrderable {}

/// Resolves a parent's persisted id-order list against its unordered to-many
/// relationship in linear time. The straightforward per-id
/// `allObjects.first { $0.id == id }` lookup is quadratic — it bridges the
/// NSSet to an array and scans it once per id — which made every read of an
/// ordered relationship a hot spot: the workout recorder walks these
/// relationships on each UI update, and exercises accumulate hundreds of set
/// groups over time.
func resolvedOrder<Entity: UUIDOrderable>(of members: NSSet?, by order: [UUID]?) -> [Entity] {
    guard let order, !order.isEmpty, let members, members.count > 0 else { return [] }
    var byId = [UUID: Entity](minimumCapacity: members.count)
    for case let member as Entity in members {
        guard let id = member.id, byId[id] == nil else { continue }
        byId[id] = member
    }
    return order.compactMap { byId[$0] }
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
            resolvedOrder(of: setGroups_, by: setGroupOrder)
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

    /// Whether the workout holds enough to be saved to history from the editor: a start date (its
    /// place in the timeline) and at least one set group.
    ///
    /// Duration is deliberately *not* required. A workout with no end date simply has no duration —
    /// every consumer (history cell, detail screen, duration stat) already omits it when `endDate`
    /// is nil — so forcing one would only fabricate a value the user never entered.
    var canBeSavedToHistory: Bool {
        date != nil && !setGroups.isEmpty
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
