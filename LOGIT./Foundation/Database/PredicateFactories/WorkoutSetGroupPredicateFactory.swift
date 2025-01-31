//
//  WorkoutSetGroupPredicateFactory.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 24.01.25.
//

import CoreData
import Foundation

struct WorkoutSetGroupPredicateFactory {
    
    static func getWorkoutSetGroups(
        withExercise exercise: Exercise? = nil,
        excludingWorkoutId workoutID: UUID? = nil
    ) -> NSPredicate? {
        var subpredicates = [NSPredicate]()

        if let exerciseId = exercise?.id {
            let exercisePredicate = NSPredicate(
                format: "ANY exercises_.id == %@",
                exerciseId.uuidString
            )
            subpredicates.append(exercisePredicate)
        }

        if let workoutID = workoutID {
            let excludeWorkoutPredicate = NSPredicate(
                format: "workout.id != %@", workoutID.uuidString
            )
            subpredicates.append(excludeWorkoutPredicate)
        }

        if subpredicates.isEmpty {
            return nil 
        } else {
            return NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)
        }
    }
    
}
