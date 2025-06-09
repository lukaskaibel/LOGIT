//
//  MuscleGroupService.swift
//  LOGIT
//
//  Created by Volker Kaibel on 03.10.24.
//

import Foundation

final class MuscleGroupService: ObservableObject {
    // MARK: - Public

    func getMuscleGroupOccurances(in sets: [WorkoutSet]) -> [(MuscleGroup, Int)] {
        Array(
            sets
                .reduce(into: [MuscleGroup: Int]()) {
                    if let muscleGroup = $1.setGroup?.exercise?.muscleGroup {
                        $0[muscleGroup, default: 0] += 1
                    }
                    if let muscleGroup = $1.setGroup?.secondaryExercise?.muscleGroup {
                        $0[muscleGroup, default: 0] += 1
                    }
                }
                .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        )
    }

    func getMuscleGroupOccurances(in workouts: [Workout]) -> [(MuscleGroup, Int)] {
        getMuscleGroupOccurances(in: Array(workouts.map { $0.sets }.joined()))
    }

    func getMuscleGroupOccurances(in workout: Workout) -> [(MuscleGroup, Int)] {
        getMuscleGroupOccurances(in: [workout])
    }

    func getMuscleGroupOccurances(in sets: [TemplateSet]) -> [(MuscleGroup, Int)] {
        Array(
            sets
                .reduce(into: [MuscleGroup: Int]()) {
                    if let muscleGroup = $1.setGroup?.exercise?.muscleGroup {
                        $0[muscleGroup, default: 0] += 1
                    }
                    if let muscleGroup = $1.setGroup?.secondaryExercise?.muscleGroup {
                        $0[muscleGroup, default: 0] += 1
                    }
                }
                .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        )
    }

    func getMuscleGroupOccurances(in templates: [Template]) -> [(MuscleGroup, Int)] {
        getMuscleGroupOccurances(in: Array(templates.map { $0.sets }.joined()))
    }

    func getMuscleGroupOccurances(in template: Template) -> [(MuscleGroup, Int)] {
        getMuscleGroupOccurances(in: [template])
    }

    // MARK: - Private

    private var allMuscleGroupZeroDict: [MuscleGroup: Int] {
        MuscleGroup.allCases.reduce(into: [MuscleGroup: Int]()) { $0[$1, default: 0] = 0 }
    }
}
