//
//  ExercisePredicateFactory.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 24.01.25.
//

import CoreData
import Foundation


struct ExercisePredicateFactory {
    
    static func getExercises(
        nameIncluding nameSubstring: String = "",
        withMuscleGroup muscleGroup: MuscleGroup? = nil
    ) -> NSPredicate? {
        var predicates: [NSPredicate] = []
        if !nameSubstring.isEmpty {
            predicates.append(NSPredicate(format: "name CONTAINS[c] %@", nameSubstring))
        }
        if let muscleGroup = muscleGroup {
            predicates.append(NSPredicate(format: "muscleGroupString == %@", muscleGroup.rawValue))
        }
        if predicates.count > 1 {
            return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        } else {
            return predicates.first
        }
    }
    
}
