//
//  PinnedExerciseSetVolumeTile.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 11.06.26.
//

import Charts
import SwiftUI

struct PinnedExerciseSetVolumeTile: View {
    let exercise: Exercise
    let workoutSets: [WorkoutSet]

    var body: some View {
        let groupedWorkoutSets = Dictionary(grouping: workoutSets) {
            Calendar.current.startOfDay(for: $0.workout?.date ?? .now)
        }.sorted { $0.key < $1.key }
        let maxDailySets = maxSetVolumeDailySets(in: groupedWorkoutSets.map { $0.1 })
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
                            Text(NSLocalizedString("setVolume", comment: ""))
                                .foregroundStyle(.secondary)
                                .font(.footnote)
                                .fontWeight(.semibold)
                            UnitView(
                                value: currentBestSetVolume(workoutSets) != nil ? formatWeightForDisplay(currentBestSetVolume(workoutSets)!) : "––",
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
                                    value: convertWeightForDisplayingDecimal($0.volume(for: exercise))
                                )
                            },
                            color: exerciseMuscleGroupColor
                        )
                    }
                    .chartXScale(domain: xDomain)
                    .chartYScale(domain: 0 ... (convertWeightForDisplayingDecimal(allTimeSetVolumePR(in: workoutSets)) * 1.1))
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

    private func maxSetVolumeDailySets(in groupedWorkoutSets: [[WorkoutSet]]) -> [WorkoutSet] {
        groupedWorkoutSets.compactMap { workoutSetsOnDay in
            workoutSetsOnDay.max { $0.volume(for: exercise) < $1.volume(for: exercise) }
        }
    }

    private func currentBestSetVolume(_ workoutSets: [WorkoutSet]) -> Int? {
        exercise.currentBestSetVolumeSet(in: workoutSets)
            .map { $0.volume(for: exercise) }
    }

    private func allTimeSetVolumePR(in workoutSets: [WorkoutSet]) -> Int {
        workoutSets.map { $0.volume(for: exercise) }.max() ?? 0
    }
}

struct PinnedExerciseSetVolumeTile_Previews: PreviewProvider {
    @EnvironmentObject static var database: Database

    static var previews: some View {
        PinnedExerciseSetVolumeTile(exercise: database.getExercises().first!, workoutSets: database.getExercises().flatMap { $0.sets })
            .previewEnvironmentObjects()
    }
}
