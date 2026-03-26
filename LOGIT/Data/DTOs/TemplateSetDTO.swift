//
//  TemplateSetDTO.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 05.10.23.
//

import Foundation

struct TemplateSetDTO: Codable {
    enum SetType: String, Codable {
        case standard
        case superSet
        case dropSet
    }
    
    let type: SetType?
    let restDuration: Int?
    
    // StandardSet fields (also used for backward compatibility)
    let repetitions: Int?
    let weight: Int?
    
    // SuperSet fields
    let repetitionsFirstExercise: Int?
    let repetitionsSecondExercise: Int?
    let weightFirstExercise: Int?
    let weightSecondExercise: Int?
    
    // DropSet fields
    let dropSetRepetitions: [Int]?
    let dropSetWeights: [Int]?
    
    /// Initialize from a Core Data TemplateSet entity for sharing
    init(from templateSet: TemplateSet) {
        if let standardSet = templateSet as? TemplateStandardSet {
            self.type = .standard
            self.restDuration = Int(standardSet.restDuration)
            self.repetitions = Int(standardSet.repetitions)
            self.weight = Int(standardSet.weight)
            self.repetitionsFirstExercise = nil
            self.repetitionsSecondExercise = nil
            self.weightFirstExercise = nil
            self.weightSecondExercise = nil
            self.dropSetRepetitions = nil
            self.dropSetWeights = nil
        } else if let superSet = templateSet as? TemplateSuperSet {
            self.type = .superSet
            self.restDuration = Int(superSet.restDuration)
            self.repetitions = nil
            self.weight = nil
            self.repetitionsFirstExercise = Int(superSet.repetitionsFirstExercise)
            self.repetitionsSecondExercise = Int(superSet.repetitionsSecondExercise)
            self.weightFirstExercise = Int(superSet.weightFirstExercise)
            self.weightSecondExercise = Int(superSet.weightSecondExercise)
            self.dropSetRepetitions = nil
            self.dropSetWeights = nil
        } else if let dropSet = templateSet as? TemplateDropSet {
            self.type = .dropSet
            self.restDuration = Int(dropSet.restDuration)
            self.repetitions = nil
            self.weight = nil
            self.repetitionsFirstExercise = nil
            self.repetitionsSecondExercise = nil
            self.weightFirstExercise = nil
            self.weightSecondExercise = nil
            self.dropSetRepetitions = dropSet.repetitions?.map { Int($0) }
            self.dropSetWeights = dropSet.weights?.map { Int($0) }
        } else {
            // Fallback to standard
            self.type = .standard
            self.restDuration = Int(templateSet.restDuration)
            self.repetitions = 0
            self.weight = 0
            self.repetitionsFirstExercise = nil
            self.repetitionsSecondExercise = nil
            self.weightFirstExercise = nil
            self.weightSecondExercise = nil
            self.dropSetRepetitions = nil
            self.dropSetWeights = nil
        }
    }
    
    /// Initialize for decoding (used by AI generation and import)
    /// Backward compatible: if only repetitions/weight provided, assumes standard set
    init(
        repetitions: Int? = nil,
        weight: Int? = nil,
        type: SetType? = nil,
        restDuration: Int? = nil,
        repetitionsFirstExercise: Int? = nil,
        repetitionsSecondExercise: Int? = nil,
        weightFirstExercise: Int? = nil,
        weightSecondExercise: Int? = nil,
        dropSetRepetitions: [Int]? = nil,
        dropSetWeights: [Int]? = nil
    ) {
        self.type = type
        self.restDuration = restDuration
        self.repetitions = repetitions
        self.weight = weight
        self.repetitionsFirstExercise = repetitionsFirstExercise
        self.repetitionsSecondExercise = repetitionsSecondExercise
        self.weightFirstExercise = weightFirstExercise
        self.weightSecondExercise = weightSecondExercise
        self.dropSetRepetitions = dropSetRepetitions
        self.dropSetWeights = dropSetWeights
    }
}
