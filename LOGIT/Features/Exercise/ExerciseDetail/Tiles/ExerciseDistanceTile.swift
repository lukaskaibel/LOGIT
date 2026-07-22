//
//  ExerciseDistanceTile.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 21.07.26.
//

import SwiftUI

struct ExerciseDistanceTile: View {
    let exercise: Exercise
    let workoutSets: [WorkoutSet]
    /// Leads the tile with the exercise name (the pinned Summary grid); see `ExerciseBestMetricTile`.
    var showsExerciseName: Bool = false

    var body: some View {
        let style = exercise.distanceStyle
        ExerciseBestMetricTile(
            exercise: exercise,
            workoutSets: workoutSets,
            title: ExercisePrimaryMetric.distance.shortTitle,
            unit: distanceUnitTitle(for: style),
            showsExerciseName: showsExerciseName,
            metricValue: { $0.maximum(.distance, for: exercise) },
            formattedValue: { formatDistanceForDisplay(Int64($0), style: style) },
            chartValue: { distanceChartValue($0, style: style) }
        )
    }
}

/// A stored distance (meters) as the number the charts plot — km/mi decimal for the long scale,
/// whole m/yd for the short one, matching the formatted values beside the chart.
func distanceChartValue(_ meters: Int, style: SetMeasurementType.DistanceStyle) -> Double {
    switch style {
    case .long: return convertDistanceForDisplayingDecimal(Int64(meters))
    case .short: return Double(convertShortDistanceForDisplaying(Int64(meters)))
    }
}

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database

    var body: some View {
        NavigationStack {
            ExerciseDistanceTile(exercise: database.getExercises().first!, workoutSets: database.getExercises().flatMap { $0.sets })
        }
    }
}

struct ExerciseDistanceTileView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
            .padding()
    }
}
