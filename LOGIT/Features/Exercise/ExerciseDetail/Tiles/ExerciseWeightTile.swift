//
//  ExerciseWeightTile.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 03.12.24.
//

import Charts
import SwiftUI

struct ExerciseWeightTile: View {
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
                    Text(NSLocalizedString("weight", comment: ""))
                        .tileHeaderStyle()
                    Spacer()
                    NavigationChevron()
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading) {
                        VStack(alignment: .leading) {
                            Text(NSLocalizedString("bestThisMonth", comment: ""))
                                .foregroundStyle(.secondary)
                                .font(.footnote)
                                .fontWeight(.semibold)
                            UnitView(
                                value: bestWeightThisMonth(workoutSets) != nil ? String(convertWeightForDisplaying(bestWeightThisMonth(workoutSets)!)) : "––",
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
                                    y: .value("Max weight on day", convertWeightForDisplaying(workoutSet.maximum(.weight, for: exercise)))
                                )
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(exerciseMuscleGroupColor.gradient)
                                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                            }
                            LineMark(
                                x: .value("Date", workoutSet.workout?.date ?? .now, unit: .day),
                                y: .value("Max weight on day", convertWeightForDisplaying(workoutSet.maximum(.weight, for: exercise)))
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
                                y: .value("Max weight on day", convertWeightForDisplaying(workoutSet.maximum(.weight, for: exercise)))
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(Gradient(colors: [
                                exerciseMuscleGroupColor.opacity(0.3),
                                exerciseMuscleGroupColor.opacity(0.1),
                                exerciseMuscleGroupColor.opacity(0),
                            ]))
                        }
                        if let lastSet = maxDailySets.last, let lastDate = lastSet.workout?.date, !Calendar.current.isDateInToday(lastDate) {
                            let weightDisplayed = convertWeightForDisplaying(lastSet.maximum(.weight, for: exercise))
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
                    .chartYScale(domain: 0 ... (Double(allTimeWeightPREntry(in: workoutSets).0) * 1.1))
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
            .padding([.horizontal, .top], CELL_PADDING)
            .padding(.bottom, CELL_PADDING / 2)
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(.black)
            HStack {
                let allTimeWeightPREntry = allTimeWeightPREntry(in: workoutSets)
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(NSLocalizedString("personalBest", comment: ""))
                            .fontWeight(.semibold)
                        Spacer()
                        if let allTimeWeightPRDate = allTimeWeightPREntry.2 {
                            Text(allTimeWeightPRDate.formatted(.dateTime.day().month().year()))
                        }
                    }
                    .foregroundStyle(.tertiary)
                    .font(.caption)
                    UnitView(value: "\(allTimeWeightPREntry.0)", unit: WeightUnit.used.rawValue, unitColor: .tertiaryLabel)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, CELL_PADDING)
            .padding(.vertical, CELL_PADDING / 2)
        }
        .tileStyle()
    }

    // MARK: - Private Methods

    private var xDomain: some ScaleDomain {
        let startDate = Calendar.current.date(byAdding: .weekOfYear, value: -4, to: .now)!.startOfWeek
        return startDate ... Date.now
    }

    private func maxWeightDailySets(in groupedWorkoutSets: [[WorkoutSet]]) -> [WorkoutSet] {
        let maxSetsPerDay = groupedWorkoutSets.compactMap { setsPerDay -> WorkoutSet? in
            return setsPerDay.max(by: { $0.maximum(.weight, for: exercise) < $1.maximum(.weight, for: exercise) })
        }
        return maxSetsPerDay
    }

    private var exerciseMuscleGroupColor: Color {
        exercise.muscleGroup?.color ?? Color.accentColor
    }

    private var visibleChartDomainInSeconds: Int {
        3600 * 24 * 35
    }

    private func bestWeightThisMonth(_ workoutSets: [WorkoutSet]) -> Int? {
        let startDate = Calendar.current.date(byAdding: .second, value: -visibleChartDomainInSeconds, to: .now)!
        let setsInTimeFrame = workoutSets.filter { $0.workout?.date ?? .distantPast >= startDate }
        guard !setsInTimeFrame.isEmpty else {
            return 0
        }
        return setsInTimeFrame
            .map { $0.maximum(.weight, for: exercise) }
            .max()
    }

    private func allTimeWeightPREntry(in workoutSets: [WorkoutSet]) -> (Int, Int, Date?) {
        let workoutSet = workoutSets
            .max(by: { $0.maximum(.weight, for: exercise) < $1.maximum(.weight, for: exercise) })
        var maxWeight: Int64 = 0
        var repetitionsOfMaxWeight: Int64 = 0
        var maxWeightDate: Date?
        if let standardSet = workoutSet as? StandardSet {
            maxWeight = standardSet.weight
            repetitionsOfMaxWeight = standardSet.repetitions
            maxWeightDate = standardSet.workout?.date
        } else if let superSet = workoutSet as? SuperSet {
            if superSet.exercise == exercise {
                maxWeight = superSet.weightFirstExercise
                repetitionsOfMaxWeight = superSet.repetitionsFirstExercise
                maxWeightDate = superSet.workout?.date
            }
            if superSet.secondaryExercise == exercise, superSet.weightSecondExercise > maxWeight {
                maxWeight = superSet.weightSecondExercise
                repetitionsOfMaxWeight = superSet.repetitionsSecondExercise
                maxWeightDate = superSet.workout?.date
            }
        } else if let dropSet = workoutSet as? DropSet {
            for item in zip(dropSet.weights ?? [], dropSet.repetitions ?? []) {
                let shouldUpdate = item.0 > maxWeight
                maxWeight = shouldUpdate ? item.0 : maxWeight
                repetitionsOfMaxWeight = shouldUpdate ? item.1 : repetitionsOfMaxWeight
                maxWeightDate = dropSet.workout?.date
            }
        }
        return (convertWeightForDisplaying(maxWeight), Int(repetitionsOfMaxWeight), maxWeightDate)
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
