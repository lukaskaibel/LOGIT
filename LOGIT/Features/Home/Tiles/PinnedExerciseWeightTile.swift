//
//  PinnedExerciseWeightTile.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 30.11.24.
//

import Charts
import SwiftUI

struct PinnedExerciseWeightTile: View {
    let exercise: Exercise
    let workoutSets: [WorkoutSet]

    var body: some View {
        let groupedWorkoutSets = Dictionary(grouping: workoutSets) {
            Calendar.current.startOfDay(for: $0.workout?.date ?? .now)
        }.sorted { $0.key < $1.key }
        let maxDailySets = maxWeightDailySets(in: groupedWorkoutSets.map { $0.1 })
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
                            Text(NSLocalizedString("weight", comment: ""))
                                .foregroundStyle(.secondary)
                                .font(.footnote)
                                .fontWeight(.semibold)
                            UnitView(
                                value: currentBestWeight(workoutSets) != nil ? formatWeightForDisplay(currentBestWeight(workoutSets)!) : "––",
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
                                    value: convertWeightForDisplayingDecimal($0.maximum(.weight, for: exercise))
                                )
                            },
                            color: exerciseMuscleGroupColor
                        )
                    }
                    .chartXScale(domain: xDomain)
                    .chartYScale(domain: 0 ... ((Double(allTimeWeightPREntry(in: workoutSets).0) ?? 0) * 1.1))
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

    private func maxWeightDailySets(in groupedWorkoutSets: [[WorkoutSet]]) -> [WorkoutSet] {
        groupedWorkoutSets.compactMap { workoutSetsOnDay in
            workoutSetsOnDay.max { $0.maximum(.weight, for: exercise) < $1.maximum(.weight, for: exercise) }
        }
    }

    private func currentBestWeight(_ workoutSets: [WorkoutSet]) -> Int? {
        exercise.currentBestSet(for: .weight, in: workoutSets)
            .map { $0.maximum(.weight, for: exercise) }
    }

    private func allTimeWeightPREntry(in workoutSets: [WorkoutSet]) -> (String, Int?, Date?) {
        if let maxWeightSet = workoutSets.max(by: { $0.maximum(.weight, for: exercise) < $1.maximum(.weight, for: exercise) }) {
            let maxWeight = maxWeightSet.maximum(.weight, for: exercise)
            return (formatWeightForDisplay(maxWeight), maxWeight, maxWeightSet.workout?.date)
        }
        return ("––", nil, nil)
    }
}

struct PinnedExerciseWeightTile_Previews: PreviewProvider {
    @EnvironmentObject static var database: Database

    static var previews: some View {
        PinnedExerciseWeightTile(exercise: database.getExercises().first!, workoutSets: database.getExercises().flatMap { $0.sets })
            .previewEnvironmentObjects()
    }
}
