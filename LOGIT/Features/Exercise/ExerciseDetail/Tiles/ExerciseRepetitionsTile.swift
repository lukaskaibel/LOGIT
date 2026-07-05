//
//  ExerciseRepetitionsTile.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 04.06.26.
//

import SwiftUI

struct ExerciseRepetitionsTile: View {
    let exercise: Exercise
    let workoutSets: [WorkoutSet]
    /// Leads the tile with the exercise name (the pinned Summary grid); see `ExerciseBestMetricTile`.
    var showsExerciseName: Bool = false

    var body: some View {
        ExerciseBestMetricTile(
            exercise: exercise,
            workoutSets: workoutSets,
            title: ExercisePrimaryMetric.repetitions.shortTitle,
            unit: NSLocalizedString("rps", comment: ""),
            showsExerciseName: showsExerciseName,
            metricValue: { $0.maximum(.repetitions, for: exercise) },
            formattedValue: { String($0) },
            chartValue: { Double($0) }
        )
    }
}

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database

    var body: some View {
        NavigationStack {
            ExerciseRepetitionsTile(exercise: database.getExercises().first!, workoutSets: database.getExercises().flatMap { $0.sets })
        }
    }
}

struct ExerciseRepetitionsTileView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
            .padding()
    }
}
