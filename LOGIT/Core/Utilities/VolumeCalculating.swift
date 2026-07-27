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

/// Compact volume for recap lines and highlight cards: "22k" past a thousand (one decimal below ten
/// thousand), the plain number under it. Takes a *display-unit* value; keeps tight spots short where
/// the full grouped figure would crowd the line — exact totals live on the volume screens.
public func abbreviatedVolume(_ value: Int) -> String {
    guard value >= 1000 else { return "\(value)" }
    let thousands = Double(value) / 1000
    if thousands >= 10 {
        return "\(Int(thousands.rounded()))k"
    }
    let formatted = String(format: "%.1f", thousands)
    return (formatted.hasSuffix(".0") ? String(formatted.dropLast(2)) : formatted) + "k"
}
