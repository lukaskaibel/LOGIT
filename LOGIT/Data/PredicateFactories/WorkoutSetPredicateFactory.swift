//
//  WorkoutSetPredicateFactory.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 24.01.25.
//

import CoreData
import Foundation

enum WorkoutSetPredicateFactory {
    static func getWorkoutSets(
        with exercise: Exercise? = nil,
        from startDate: Date? = nil,
        to endDate: Date? = nil,
        in workout: Workout? = nil,
        excludeCurrentWorkout: Bool = true
    ) -> NSPredicate? {
        var subpredicates = [NSPredicate]()

        if let exerciseId = exercise?.id {
            // UUID, not uuidString: string comparison works in SQLite but never matches during
            // the in-memory evaluation of pending objects (see WorkoutSetGroupPredicateFactory).
            let exercisePredicate = NSPredicate(format: "ANY setGroup.exercises_.id == %@", exerciseId as CVarArg)
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
        
        if let workoutId = workout?.id {
            let workoutPredicate = NSPredicate(format: "setGroup.workout.id == %@", workoutId as CVarArg)
            subpredicates.append(workoutPredicate)
        }

        if excludeCurrentWorkout {
            let excludeCurrentWorkoutPredicate = NSPredicate(format: "setGroup.workout.isCurrentWorkout == nil OR setGroup.workout.isCurrentWorkout == NO")
            subpredicates.append(excludeCurrentWorkoutPredicate)
        }

        if subpredicates.isEmpty {
            return nil
        } else {
            return NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)
        }
    }
}
