//
//  ExerciseDurationTile.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 16.07.26.
//

import SwiftUI

struct ExerciseDurationTile: View {
    let exercise: Exercise
    let workoutSets: [WorkoutSet]
    /// Leads the tile with the exercise name (the pinned Summary grid); see `ExerciseBestMetricTile`.
    var showsExerciseName: Bool = false

    var body: some View {
        ExerciseBestMetricTile(
            exercise: exercise,
            workoutSets: workoutSets,
            title: ExercisePrimaryMetric.duration.shortTitle,
            unit: "",
            showsExerciseName: showsExerciseName,
            metric: .duration,
            metricValue: { $0.metricValue(.duration, for: exercise) },
            formattedValue: { formatDurationForDisplay(milliseconds: Int64($0)) },
            chartValue: { Double($0) }
        )
    }
}

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database

    var body: some View {
        NavigationStack {
            ExerciseDurationTile(exercise: database.getExercises().first!, workoutSets: database.getExercises().flatMap { $0.sets })
        }
    }
}

struct ExerciseDurationTileView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
            .padding()
    }
}
