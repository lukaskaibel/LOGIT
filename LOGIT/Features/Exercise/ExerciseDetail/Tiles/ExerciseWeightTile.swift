//
//  ExerciseWeightTile.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 03.12.24.
//

import SwiftUI

struct ExerciseWeightTile: View {
    let exercise: Exercise
    let workoutSets: [WorkoutSet]
    /// Leads the tile with the exercise name (the pinned Summary grid); see `ExerciseBestMetricTile`.
    var showsExerciseName: Bool = false
    /// The span the value covers — four weeks (the app-wide "current best") on the detail screen, the
    /// Summary's selected window when pinned. See `ExerciseBestMetricTile`.
    var window: TrendWindow = .fourWeeks

    var body: some View {
        ExerciseBestMetricTile(
            exercise: exercise,
            workoutSets: workoutSets,
            title: NSLocalizedString("weight", comment: ""),
            unit: WeightUnit.used.rawValue,
            requiresPro: true,
            showsExerciseName: showsExerciseName,
            window: window,
            metric: .weight,
            metricValue: { $0.metricValue(.weight, for: exercise) },
            formattedValue: { formatWeightForDisplay($0) },
            chartValue: { convertWeightForDisplayingDecimal($0) }
        )
    }
}

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database

    var body: some View {
        NavigationStack {
            ExerciseWeightTile(exercise: database.getExercises().first!, workoutSets: database.getExercises().flatMap { $0.sets })
        }
    }
}

struct ExerciseWeightTileView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
            .padding()
    }
}
