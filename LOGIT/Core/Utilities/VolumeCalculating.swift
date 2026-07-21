//
//  VolumeCalculating.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 28.09.23.
//

import Foundation

/// Volume is weight × repetitions, summed per entry. Entries that don't record both — duration
/// holds, bodyweight reps — contribute 0 by construction: volume stays an honest kg number and
/// never invents conversions. All reads go through `entryValues`, so legacy-shaped sets that
/// the backfill hasn't reached yet compute identically.

public func getVolume(of workoutSets: [WorkoutSet]) -> Int {
    workoutSets
        .map { workoutSet in
            workoutSet.entryValues.reduce(0) { $0 + Int($1.repetitions * $1.weight) }
        }
        .reduce(0, +)
}

public func getVolume(of workoutSets: [WorkoutSet], for exercise: Exercise) -> Int {
    workoutSets
        .map { workoutSet in
            workoutSet.entryValues
                .filter { $0.exercise == exercise }
                .reduce(0) { $0 + Int($1.repetitions * $1.weight) }
        }
        .reduce(0, +)
}

public func getVolume(of workoutSets: [WorkoutSet], for muscleGroup: MuscleGroup) -> Int {
    workoutSets
        .map { workoutSet in
            workoutSet.entryValues
                .filter { $0.exercise?.muscleGroup == muscleGroup }
                .reduce(0) { $0 + Int($1.repetitions * $1.weight) }
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
