//
//  PinnedExerciseE1RMTile.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 04.06.26.
//

import Charts
import SwiftUI

struct PinnedExerciseE1RMTile: View {
    let exercise: Exercise
    let workoutSets: [WorkoutSet]

    var body: some View {
        let groupedWorkoutSets = Dictionary(grouping: workoutSets) {
            Calendar.current.startOfDay(for: $0.workout?.date ?? .now)
        }.sorted { $0.key < $1.key }
        let maxDailySets = maxE1RMDailySets(in: groupedWorkoutSets.map { $0.1 })
        VStack(spacing: 0) {
            VStack {
                HStack {
                    Text(exercise.displayName)
                        .tileHeaderStyle()
                    Spacer()
                    NavigationChevron()
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading) {
                        VStack(alignment: .leading) {
                            Text(NSLocalizedString("estimatedOneRepMax", comment: ""))
                                .foregroundStyle(.secondary)
                                .font(.footnote)
                                .fontWeight(.semibold)
                            UnitView(
                                value: currentBestE1RM(workoutSets) != nil ? formatEstimatedOneRepMax(currentBestE1RM(workoutSets)!) : "––",
                                unit: WeightUnit.used.rawValue,
                                configuration: .large
                            )
                            .foregroundStyle((exercise.muscleGroup?.color ?? Color.label).gradient)
                        }
                    }
                    Spacer()
                    Chart {
                        tileSparklineMarks(
                            points: maxDailySets.map {
                                TileSparklinePoint(
                                    date: $0.workout?.date ?? .now,
                                    value: convertWeightForDisplayingDecimal(Int64($0.estimatedOneRepMax(for: exercise)))
                                )
                            },
                            color: exerciseMuscleGroupColor
                        )
                    }
                    .chartXScale(domain: xDomain)
                    .chartYScale(domain: 0 ... ((Double(allTimeE1RMPREntry(in: workoutSets).0) ?? 0) * 1.1))
                    .chartXAxis {}
                    .chartYAxis {}
                    .tileSparklineChartStyle()
                }
            }
            .padding(CELL_PADDING)
        }
        .tileStyle()
    }

    // MARK: - Private Methods

    private var xDomain: some ScaleDomain {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        return thirtyDaysAgo ... Date()
    }

    private var exerciseMuscleGroupColor: Color {
        exercise.muscleGroup?.color ?? Color.label
    }

    private func maxE1RMDailySets(in groupedWorkoutSets: [[WorkoutSet]]) -> [WorkoutSet] {
        groupedWorkoutSets.compactMap { workoutSetsOnDay in
            workoutSetsOnDay.max { $0.estimatedOneRepMax(for: exercise) < $1.estimatedOneRepMax(for: exercise) }
        }
    }

    private func currentBestE1RM(_ workoutSets: [WorkoutSet]) -> Int? {
        exercise.currentBestSet(for: .estimatedOneRepMax, in: workoutSets)
            .map { $0.estimatedOneRepMax(for: exercise) }
    }

    private func allTimeE1RMPREntry(in workoutSets: [WorkoutSet]) -> (String, Int?, Date?) {
        if let maxSet = workoutSets.max(by: { $0.estimatedOneRepMax(for: exercise) < $1.estimatedOneRepMax(for: exercise) }) {
            let maxE1RM = maxSet.estimatedOneRepMax(for: exercise)
            return (formatEstimatedOneRepMax(maxE1RM), maxE1RM, maxSet.workout?.date)
        }
        return ("––", nil, nil)
    }
}

struct PinnedExerciseE1RMTile_Previews: PreviewProvider {
    @EnvironmentObject static var database: Database

    static var previews: some View {
        PinnedExerciseE1RMTile(exercise: database.getExercises().first!, workoutSets: database.getExercises().flatMap { $0.sets })
            .previewEnvironmentObjects()
    }
}
