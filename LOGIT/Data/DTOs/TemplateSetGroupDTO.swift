//
//  TemplateSetGroupDTO.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 05.10.23.
//

import Foundation

struct TemplateSetGroupDTO: Codable {
    let exercise: ExerciseDTO
    let secondaryExercise: ExerciseDTO?
    let setType: String?
    let sets: [TemplateSetDTO]
    
    /// Initialize from a Core Data TemplateSetGroup entity for sharing
    init(from setGroup: TemplateSetGroup) {
        self.exercise = ExerciseDTO(from: setGroup.exercise)
        self.secondaryExercise = setGroup.secondaryExercise.map { ExerciseDTO(from: $0) }
        self.setType = setGroup.setType.rawValue
        self.sets = setGroup.sets.map { TemplateSetDTO(from: $0) }
    }
    
    /// Initialize for decoding (used by AI generation and import)
    init(exercise: ExerciseDTO, sets: [TemplateSetDTO], secondaryExercise: ExerciseDTO? = nil, setType: String? = nil) {
        self.exercise = exercise
        self.secondaryExercise = secondaryExercise
        self.setType = setType
        self.sets = sets
    }
}
