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
            // Compare against the UUID itself, not its string. SQLite coerces a string to the
            // UUID attribute, but pending (unsaved) objects are matched in memory, where
            // UUID == String is always false — set groups would stay invisible until persisted.
            let exercisePredicate = NSPredicate(
                format: "ANY exercises_.id == %@",
                exerciseId as CVarArg
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
