//
//  Workout+.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 01.07.21.
//

import Foundation


extension Workout {
    
    var numberOfSets: Int {
        sets.count
    }
    var numberOfSetGroups: Int {
        setGroups?.array.count ?? 0
    }
    
    var isEmpty: Bool {
        setGroups?.array.isEmpty ?? true
    }
    
    var exercises: [Exercise] {
        var result = [Exercise]()
        if let array = setGroups?.array as? [WorkoutSetGroup] {
            for setGroup in array {
                if let exercise = setGroup.exercise {
                    result.append(exercise)
                }
            }
        }
        return result
    }
    
    var sets: [WorkoutSet] {
        var result = [WorkoutSet]()
        if let array = setGroups?.array as? [WorkoutSetGroup] {
            for setGroup in array {
                if let workoutSets = setGroup.sets?.array as? [WorkoutSet] {
                    result.append(contentsOf: workoutSets)
                }
            }
        }
        return result
    }
    
    var muscleGroups: [MuscleGroup] {
        exercises
            .compactMap { $0.muscleGroup }
    }
    
    func remove(setGroup: WorkoutSetGroup) {
        setGroups = NSOrderedSet(array: ((setGroups?.array as? [WorkoutSetGroup]) ?? .emptyList).filter { $0 != setGroup } )
    }
    
    func index(of setGroup: WorkoutSetGroup) -> Int? {
        (setGroups?.array as? [WorkoutSetGroup] ?? .emptyList).firstIndex(of: setGroup)
    }
    
    static func getStandardName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        let weekday = formatter.string(from: date)
        let hour = Calendar.current.component(.hour, from: date)
        let daytime: String
        switch hour {
        case 6..<12: daytime = NSLocalizedString("morning", comment: "")
        case 12..<14: daytime = NSLocalizedString("noon", comment: "")
        case 14..<17: daytime = NSLocalizedString("afternoon", comment: "")
        case 17..<22: daytime = NSLocalizedString("evening", comment: "")
        default: daytime = NSLocalizedString("night", comment: "")
        }
        return "\(weekday) \(daytime) Workout"
    }
    
}
