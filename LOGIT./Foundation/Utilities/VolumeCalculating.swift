//
//  VolumeCalculator.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 28.09.23.
//

import Foundation

public func getVolume(of workoutSets: [WorkoutSet]) -> Int {
    workoutSets
        .map { workoutSet in
            if let standardSet = workoutSet as? StandardSet {
                return Int(standardSet.repetitions * standardSet.weight)
            }
            if let dropSet = workoutSet as? DropSet, let repetitions = dropSet.repetitions, let weights = dropSet.weights {
                return Int(zip(repetitions, weights).map(*).reduce(0, +))
            }
            if let superSet = workoutSet as? SuperSet {
                return Int(superSet.repetitionsFirstExercise * superSet.weightFirstExercise) + Int(superSet.repetitionsSecondExercise * superSet.weightSecondExercise)
            }
            return 0
        }
        .reduce(0, +)
}

public func getVolume(of workoutSets: [WorkoutSet], for exercise: Exercise) -> Int {
    workoutSets
        .map { workoutSet in
            if let standardSet = workoutSet as? StandardSet {
                return Int(standardSet.repetitions * standardSet.weight)
            }
            if let dropSet = workoutSet as? DropSet, let repetitions = dropSet.repetitions, let weights = dropSet.weights {
                return Int(zip(repetitions, weights).map(*).reduce(0, +))
            }
            if let superSet = workoutSet as? SuperSet {
                var volume = 0
                if exercise == superSet.setGroup?.exercise {
                    volume += Int(superSet.repetitionsFirstExercise * superSet.weightFirstExercise)
                }
                if exercise == superSet.setGroup?.secondaryExercise {
                    volume += Int(superSet.repetitionsSecondExercise * superSet.weightSecondExercise)
                }
                return volume
            }
            return 0
        }
        .reduce(0, +)
}

public func getVolume(of workoutSets: [WorkoutSet], for muscleGroup: MuscleGroup) -> Int {
    workoutSets
        .map { workoutSet in
            if let standardSet = workoutSet as? StandardSet, standardSet.exercise?.muscleGroup == muscleGroup {
                return Int(standardSet.repetitions * standardSet.weight)
            }
            if let dropSet = workoutSet as? DropSet, dropSet.exercise?.muscleGroup == muscleGroup, let repetitions = dropSet.repetitions, let weights = dropSet.weights {
                return Int(zip(repetitions, weights).map(*).reduce(0, +))
            }
            if let superSet = workoutSet as? SuperSet {
                var volume = 0
                if superSet.exercise?.muscleGroup == muscleGroup {
                    volume += Int(superSet.repetitionsFirstExercise * superSet.weightFirstExercise)
                }
                if superSet.secondaryExercise?.muscleGroup == muscleGroup {
                    volume += Int(superSet.repetitionsSecondExercise * superSet.weightSecondExercise)
                }
                return volume
            }
            return 0
        }
        .reduce(0, +)
}
    
public func getVolume(of groupedSets: [[WorkoutSet]], for exercise: Exercise) -> [(Date, Int)] {
    return Array(zip(
        groupedSets.map { $0.first?.setGroup?.workout?.date ?? Date.distantPast },
        groupedSets
            .map { groupedWorkoutSets in
                getVolume(of: groupedWorkoutSets, for: exercise)
            }
            .map { convertWeightForDisplaying($0) }
    ))
}

public func getVolume(of groupedSets: [[WorkoutSet]]) -> [(Date, Int)] {
    return Array(zip(
        groupedSets.map { $0.first?.setGroup?.workout?.date ?? Date.distantPast },
        groupedSets
            .map { workoutSets in
                getVolume(of: workoutSets)
            }
            .map { convertWeightForDisplaying($0) }
    ))
}
