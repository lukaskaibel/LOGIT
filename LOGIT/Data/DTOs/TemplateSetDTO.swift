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

    /// Format-version-2 entries — see `WorkoutSetDTO.entries`.
    let entries: [SetEntryDTO]?

    /// Initialize from a Core Data TemplateSet entity for sharing
    init(from templateSet: TemplateSet) {
        let values = templateSet.entryValues
        self.restDuration = templateSet.restDurationSeconds
        self.entries = values.enumerated().map { index, value in
            SetEntryDTO(from: value, exerciseIndex: templateSet is TemplateSuperSet ? index : 0)
        }
        if templateSet is TemplateSuperSet {
            self.type = .superSet
            self.repetitions = nil
            self.weight = nil
            self.repetitionsFirstExercise = Int(values.value(at: 0)?.repetitions ?? 0)
            self.repetitionsSecondExercise = Int(values.value(at: 1)?.repetitions ?? 0)
            self.weightFirstExercise = Int(values.value(at: 0)?.weight ?? 0)
            self.weightSecondExercise = Int(values.value(at: 1)?.weight ?? 0)
            self.dropSetRepetitions = nil
            self.dropSetWeights = nil
        } else if templateSet is TemplateDropSet {
            self.type = .dropSet
            self.repetitions = nil
            self.weight = nil
            self.repetitionsFirstExercise = nil
            self.repetitionsSecondExercise = nil
            self.weightFirstExercise = nil
            self.weightSecondExercise = nil
            self.dropSetRepetitions = values.map { Int($0.repetitions) }
            self.dropSetWeights = values.map { Int($0.weight) }
        } else {
            self.type = .standard
            self.repetitions = Int(values.first?.repetitions ?? 0)
            self.weight = Int(values.first?.weight ?? 0)
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
        dropSetWeights: [Int]? = nil,
        entries: [SetEntryDTO]? = nil
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
        self.entries = entries
    }
}
