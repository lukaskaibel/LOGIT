//
//  WorkoutSetPredicateFactory.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 24.01.25.
//

import CoreData
import Foundation


struct WorkoutSetPredicateFactory {
    
    static func getWorkoutSets(
        with exercise: Exercise? = nil,
        from startDate: Date? = nil,
        to endDate: Date? = nil,
        excludeFromWorkout workoutID: UUID? = nil
    ) -> NSPredicate? {
        var subpredicates = [NSPredicate]()
        
        if let exerciseId = exercise?.id {
            let exercisePredicate = NSPredicate(format: "ANY setGroup.exercises_.id == %@", exerciseId.uuidString)
            subpredicates.append(exercisePredicate)
        }
        
        if let startDate = startDate {
            let startDatePredicate = NSPredicate(format: "setGroup.workout.date >= %@", startDate as NSDate)
            subpredicates.append(startDatePredicate)
        }
        
        if let endDate = endDate {
            let endDatePredicate = NSPredicate(format: "setGroup.workout.date <= %@", endDate as NSDate)
            subpredicates.append(endDatePredicate)
        }

        if let workoutID = workoutID {
            let excludeWorkoutPredicate = NSPredicate(format: "setGroup.workout.id != %@", workoutID.uuidString)
            subpredicates.append(excludeWorkoutPredicate)
        }
        
        if subpredicates.isEmpty {
            return nil
        } else {
            return NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)
        }
    }
    
}
