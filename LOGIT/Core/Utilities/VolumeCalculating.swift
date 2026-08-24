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

/// One entry's contribution to volume: reps × weight, with assistance counting as nothing.
///
/// A negative weight is help received, not work undone — an assisted set is a real set. Letting it
/// subtract would drain the workout, muscle-group and Summary totals that sum this, so it clamps at
/// zero instead. (The load the lifter actually moved is their bodyweight, which the app doesn't
/// know, so counting it as zero is the honest floor rather than an estimate.)
private func entryVolume(of value: SetEntryValues) -> Int {
    max(0, Int(value.repetitions * value.weight))
}

public func getVolume(of workoutSets: [WorkoutSet]) -> Int {
    workoutSets
        .map { workoutSet in
            workoutSet.entryValues.reduce(0) { $0 + entryVolume(of: $1) }
        }
        .reduce(0, +)
}

public func getVolume(of workoutSets: [WorkoutSet], for exercise: Exercise) -> Int {
    workoutSets
        .map { workoutSet in
            workoutSet.entryValues
                .filter { $0.exercise == exercise }
                .reduce(0) { $0 + entryVolume(of: $1) }
        }
        .reduce(0, +)
}

public func getVolume(of workoutSets: [WorkoutSet], for muscleGroup: MuscleGroup) -> Int {
    workoutSets
        .map { workoutSet in
            workoutSet.entryValues
                .filter { $0.exercise?.muscleGroup == muscleGroup }
                .reduce(0) { $0 + entryVolume(of: $1) }
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
