//
//  WorkoutPredicateFactory.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 24.01.25.
//

import CoreData
import Foundation

struct WorkoutPredicateFactory {
    
    static func getWorkouts(
        nameIncluding nameSubstring: String = "",
        withMuscleGroup muscleGroup: MuscleGroup? = nil,
        from startDate: Date? = nil,
        to endDate: Date? = nil,
        excludingWorkoutWithId excludedWorkoutID: UUID? = nil
    ) -> NSPredicate? {
        // Initialize an array for subpredicates
        var subpredicates = [NSPredicate]()

        // 1. Filter by name (case-insensitive, contains substring)
        if !nameSubstring.isEmpty {
            let namePredicate = NSPredicate(format: "name CONTAINS[c] %@", nameSubstring)
            subpredicates.append(namePredicate)
        }

        // 2. Filter by muscle group
        if let muscleGroup = muscleGroup {
            let muscleGroupPredicate = NSPredicate(format: "ANY setGroups_.exercises_.muscleGroupString == %@", muscleGroup.rawValue)
            //subpredicates.append(muscleGroupPredicate)
        }
        
        if let startDate = startDate {
            let startDatePredicate = NSPredicate(format: "date >= %@", startDate as NSDate)
            subpredicates.append(startDatePredicate)
        }
        
        if let endDate = endDate {
            let endDatePredicate = NSPredicate(format: "date <= %@", endDate as NSDate)
            subpredicates.append(endDatePredicate)
        }

        // 3. Exclude current workout
        if let excludedWorkoutID = excludedWorkoutID {
            let excludeCurrentWorkoutPredicate = NSPredicate(format: "id != %@", excludedWorkoutID.uuidString)
            subpredicates.append(excludeCurrentWorkoutPredicate)
        }

        // Combine all subpredicates with AND logic
        if subpredicates.isEmpty {
            return nil // No filtering, return nil to match all workouts
        } else {
            return NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)
        }
    }

    
}
