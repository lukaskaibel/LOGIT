//
//  ExerciseDTO.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 04.10.23.
//

import Foundation

struct ExerciseDTO: Codable {
    let name: String?
    // Had to use 'type' instead of 'muscleGroup', because ChatGPT would always make up new muscle groups
    let type: MuscleGroup?
    /// Flag to indicate if this is a default exercise (uses localization key as name)
    let isDefaultExercise: Bool?
    
    /// Initialize from a Core Data Exercise entity
    /// Uses the raw `name` (not `displayName`) so default exercises can be properly matched on import
    init(from exercise: Exercise?) {
        self.name = exercise?.name
        self.type = exercise?.muscleGroup
        self.isDefaultExercise = exercise?.isDefaultExercise
    }
    
    /// Initialize for decoding (used by AI generation and import)
    init(name: String?, type: MuscleGroup?, isDefaultExercise: Bool? = nil) {
        self.name = name
        self.type = type
        self.isDefaultExercise = isDefaultExercise
    }
}
