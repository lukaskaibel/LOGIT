//
//  ExerciseSetVolumeTile.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 11.06.26.
//

import SwiftUI

struct ExerciseSetVolumeTile: View {
    let exercise: Exercise
    let workoutSets: [WorkoutSet]
    /// Leads the tile with the exercise name (the pinned Summary grid); see `ExerciseBestMetricTile`.
    var showsExerciseName: Bool = false

    var body: some View {
        ExerciseBestMetricTile(
            exercise: exercise,
            workoutSets: workoutSets,
            title: NSLocalizedString("setVolume", comment: ""),
            unit: WeightUnit.used.rawValue,
            requiresPro: true,
            showsExerciseName: showsExerciseName,
            metricValue: { $0.volume(for: exercise) },
            formattedValue: { formatWeightForDisplay($0) },
            chartValue: { convertWeightForDisplayingDecimal($0) }
        )
    }
}

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database

    var body: some View {
        NavigationStack {
            ExerciseSetVolumeTile(exercise: database.getExercises().first!, workoutSets: database.getExercises().flatMap { $0.sets })
        }
    }
}

struct ExerciseSetVolumeTileView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
            .padding()
    }
}
