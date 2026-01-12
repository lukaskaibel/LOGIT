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
                            Text(NSLocalizedString("bestLastMonth", comment: ""))
                                .foregroundStyle(.secondary)
                                .font(.footnote)
                                .fontWeight(.semibold)
                            UnitView(
                                value: bestWeightThisMonth(workoutSets) != nil ? formatWeightForDisplay(bestWeightThisMonth(workoutSets)!) : "––",
                                unit: WeightUnit.used.rawValue.uppercased(),
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
                                    y: .value("Max weight on day", convertWeightForDisplayingDecimal(workoutSet.maximum(.weight, for: exercise)))
                                )
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(exerciseMuscleGroupColor.gradient)
                                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                            }
                            LineMark(
                                x: .value("Date", workoutSet.workout?.date ?? .now, unit: .day),
                                y: .value("Max weight on day", convertWeightForDisplayingDecimal(workoutSet.maximum(.weight, for: exercise)))
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
                                y: .value("Max weight on day", convertWeightForDisplayingDecimal(workoutSet.maximum(.weight, for: exercise)))
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(Gradient(colors: [
                                exerciseMuscleGroupColor.opacity(0.3),
                                exerciseMuscleGroupColor.opacity(0.1),
                                exerciseMuscleGroupColor.opacity(0),
                            ]))
                        }
                        if let lastSet = maxDailySets.last, let lastDate = lastSet.workout?.date, !Calendar.current.isDateInToday(lastDate) {
                            let weightDisplayed = convertWeightForDisplayingDecimal(lastSet.maximum(.weight, for: exercise))
                            RuleMark(
                                xStart: .value("Start", lastDate),
                                xEnd: .value("End", Date()),
                                y: .value("Max weight on day", weightDisplayed)
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
                    .chartYScale(domain: 0 ... ((Double(allTimeWeightPREntry(in: workoutSets).0) ?? 0) * 1.1))
                    .chartXAxis {}
                    .chartYAxis {}
                    .frame(width: 120, height: 70)
                    .clipped()
                    .mask(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .black, location: 0.1),
                                .init(color: .black, location: 1.0),
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
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

    private func bestWeightThisMonth(_ workoutSets: [WorkoutSet]) -> Int? {
        workoutSets
            .filter { ($0.workout?.date ?? .distantPast) > (Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .distantPast) }
            .map { $0.maximum(.weight, for: exercise) }
            .max()
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
