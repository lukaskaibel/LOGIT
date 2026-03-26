//
//  WorkoutDTO.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 04.02.26.
//

import Foundation

/// Data Transfer Object for sharing workouts between users
struct WorkoutDTO: Codable {
    /// Format version for future compatibility
    static let formatVersion = 1
    
    let formatVersion: Int
    let name: String?
    let date: Date?
    let endDate: Date?
    let setGroups: [WorkoutSetGroupDTO]
    
    /// App Store URL for users who don't have the app installed
    let appStoreURL: String
    
    init(from workout: Workout) {
        self.formatVersion = Self.formatVersion
        self.name = workout.name
        self.date = workout.date
        self.endDate = workout.endDate
        self.setGroups = workout.setGroups.map { WorkoutSetGroupDTO(from: $0) }
        self.appStoreURL = "https://apps.apple.com/app/logit-track-your-workouts/id6444813640"
    }
}

/// Data Transfer Object for workout set groups
struct WorkoutSetGroupDTO: Codable {
    let exercise: ExerciseDTO
    let secondaryExercise: ExerciseDTO?
    let setType: String
    let sets: [WorkoutSetDTO]
    
    init(from setGroup: WorkoutSetGroup) {
        self.exercise = ExerciseDTO(from: setGroup.exercise)
        self.secondaryExercise = setGroup.secondaryExercise.map { ExerciseDTO(from: $0) }
        self.setType = setGroup.setType.rawValue
        self.sets = setGroup.sets.map { WorkoutSetDTO(from: $0) }
    }
}

/// Data Transfer Object for workout sets (polymorphic)
struct WorkoutSetDTO: Codable {
    enum SetType: String, Codable {
        case standard
        case superSet
        case dropSet
    }
    
    let type: SetType?
    let restDuration: Int?
    
    // StandardSet fields
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
    
    init(from workoutSet: WorkoutSet) {
        if let standardSet = workoutSet as? StandardSet {
            self.type = .standard
            self.restDuration = standardSet.restDurationSeconds
            self.repetitions = Int(standardSet.repetitions)
            self.weight = Int(standardSet.weight)
            self.repetitionsFirstExercise = nil
            self.repetitionsSecondExercise = nil
            self.weightFirstExercise = nil
            self.weightSecondExercise = nil
            self.dropSetRepetitions = nil
            self.dropSetWeights = nil
        } else if let superSet = workoutSet as? SuperSet {
            self.type = .superSet
            self.restDuration = superSet.restDurationSeconds
            self.repetitions = nil
            self.weight = nil
            self.repetitionsFirstExercise = Int(superSet.repetitionsFirstExercise)
            self.repetitionsSecondExercise = Int(superSet.repetitionsSecondExercise)
            self.weightFirstExercise = Int(superSet.weightFirstExercise)
            self.weightSecondExercise = Int(superSet.weightSecondExercise)
            self.dropSetRepetitions = nil
            self.dropSetWeights = nil
        } else if let dropSet = workoutSet as? DropSet {
            self.type = .dropSet
            self.restDuration = dropSet.restDurationSeconds
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
            self.restDuration = workoutSet.restDurationSeconds
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
}
