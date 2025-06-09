//
//  WorkoutSetGroupPredicateFactory.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 24.01.25.
//

import CoreData
import Foundation

enum WorkoutSetGroupPredicateFactory {
    static func getWorkoutSetGroups(
        withExercise exercise: Exercise? = nil,
        excludeCurrentWorkout: Bool = true
    ) -> NSPredicate? {
        var subpredicates = [NSPredicate]()

        if let exerciseId = exercise?.id {
            let exercisePredicate = NSPredicate(
                format: "ANY exercises_.id == %@",
                exerciseId.uuidString
            )
            subpredicates.append(exercisePredicate)
        }

        if excludeCurrentWorkout {
            let excludeCurrentWorkoutPredicate = NSPredicate(format: "workout.isCurrentWorkout == nil OR workout.isCurrentWorkout == NO")
            subpredicates.append(excludeCurrentWorkoutPredicate)
        }

        if subpredicates.isEmpty {
            return nil
        } else {
            return NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)
        }
    }
}
