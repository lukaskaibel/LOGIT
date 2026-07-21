//
//  WorkoutDTO.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 04.02.26.
//

import Foundation

/// Data Transfer Object for sharing workouts between users
struct WorkoutDTO: Codable {
    /// Format version for future compatibility. Version 2 added per-set `entries` (measurement
    /// types, durations); the legacy per-type fields stay populated so version-1 receivers can
    /// still import the reps-and-weight portion.
    static let formatVersion = 2
    
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

    /// Format-version-2 entries: one per performed entry, carrying its measurement type and
    /// duration. Absent in version-1 files; importers fall back to the legacy fields then.
    let entries: [SetEntryDTO]?

    init(from workoutSet: WorkoutSet) {
        let values = workoutSet.entryValues
        self.restDuration = workoutSet.restDurationSeconds
        self.entries = values.enumerated().map { index, value in
            SetEntryDTO(from: value, exerciseIndex: workoutSet is SuperSet ? index : 0)
        }
        if workoutSet is SuperSet {
            self.type = .superSet
            self.repetitions = nil
            self.weight = nil
            self.repetitionsFirstExercise = Int(values.value(at: 0)?.repetitions ?? 0)
            self.repetitionsSecondExercise = Int(values.value(at: 1)?.repetitions ?? 0)
            self.weightFirstExercise = Int(values.value(at: 0)?.weight ?? 0)
            self.weightSecondExercise = Int(values.value(at: 1)?.weight ?? 0)
            self.dropSetRepetitions = nil
            self.dropSetWeights = nil
        } else if workoutSet is DropSet {
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
}

/// One performed (or planned) entry in the version-2 share format.
struct SetEntryDTO: Codable {
    let type: String?
    let repetitions: Int?
    let weight: Int?
    let duration: Int?
    /// Index into the set group's exercises (0 = primary); meaningful for compound sets.
    let exerciseIndex: Int?

    init(from values: SetEntryValues, exerciseIndex: Int) {
        self.type = values.type.rawValue
        self.repetitions = Int(values.repetitions)
        self.weight = Int(values.weight)
        self.duration = Int(values.duration)
        self.exerciseIndex = exerciseIndex
    }
}
