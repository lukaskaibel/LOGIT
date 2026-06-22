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

    var body: some View {
        ExerciseBestMetricTile(
            exercise: exercise,
            workoutSets: workoutSets,
            title: NSLocalizedString("weight", comment: ""),
            unit: WeightUnit.used.rawValue,
            requiresPro: true,
            metricValue: { $0.maximum(.weight, for: exercise) },
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
