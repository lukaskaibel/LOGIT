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
                        ForEach(maxDailySets) { workoutSet in
                            if maxDailySets.first == workoutSet {
                                LineMark(
                                    x: .value("Date", Date.distantPast, unit: .day),
                                    y: .value("Max set volume on day", convertWeightForDisplayingDecimal(workoutSet.volume(for: exercise)))
                                )
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(exerciseMuscleGroupColor.gradient)
                                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                            }
                            LineMark(
                                x: .value("Date", workoutSet.workout?.date ?? .now, unit: .day),
                                y: .value("Max set volume on day", convertWeightForDisplayingDecimal(workoutSet.volume(for: exercise)))
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(exerciseMuscleGroupColor.gradient)
                            .lineStyle(StrokeStyle(lineWidth: 3))
                            .symbol {
                                Circle()
                                    .frame(width: 6, height: 6)
                                    .foregroundStyle(exerciseMuscleGroupColor.gradient)
                                    .overlay {
                                        Circle()
                                            .frame(width: 2, height: 2)
                                            .foregroundStyle(Color.black)
                                    }
                            }
                            AreaMark(
                                x: .value("Date", workoutSet.workout?.date ?? .now, unit: .day),
                                y: .value("Max set volume on day", convertWeightForDisplayingDecimal(workoutSet.volume(for: exercise)))
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(Gradient(colors: [
                                exerciseMuscleGroupColor.opacity(0.3),
                                exerciseMuscleGroupColor.opacity(0.1),
                                exerciseMuscleGroupColor.opacity(0),
                            ]))
                        }
                        if let lastSet = maxDailySets.last, let lastDate = lastSet.workout?.date, !Calendar.current.isDateInToday(lastDate) {
                            let setVolumeDisplayed = convertWeightForDisplayingDecimal(lastSet.volume(for: exercise))
                            RuleMark(
                                xStart: .value("Start", lastDate),
                                xEnd: .value("End", Date()),
                                y: .value("Max set volume on day", setVolumeDisplayed)
                            )
                            .foregroundStyle(exerciseMuscleGroupColor.opacity(0.45))
                            .lineStyle(
                                StrokeStyle(
                                    lineWidth: 3,
                                    lineCap: .round,
                                    dash: [3, 6]
                                )
                            )
                        }
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
