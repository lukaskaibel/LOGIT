//
//  VolumeCalculator.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 28.09.23.
//

import Foundation

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
                if exercise == superSet.setGroup?.exercise {
                    return Int(superSet.repetitionsFirstExercise * superSet.weightFirstExercise)
                }
                if exercise == superSet.setGroup?.secondaryExercise {
                    return Int(superSet.repetitionsSecondExercise * superSet.weightSecondExercise)
                }
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
            .map { groupedWorkoutSets in
                groupedWorkoutSets
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
            .map { convertWeightForDisplaying($0) }
    ))
}
