//
//  ExerciseRepetitionsTile.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 03.12.24.
//

import Charts
import SwiftUI

struct ExerciseRepetitionsTile: View {
    let exercise: Exercise
    let workoutSets: [WorkoutSet]

    var body: some View {
        let groupedWorkoutSets = Dictionary(grouping: workoutSets) {
            Calendar.current.startOfDay(for: $0.workout?.date ?? .now)
        }.sorted { $0.key < $1.key }
        let maxDailySets = maxRepetitionsDailySets(in: groupedWorkoutSets.map { $0.1 })
        VStack(spacing: 0) {
            VStack {
                HStack {
                    Text(NSLocalizedString("repetitions", comment: ""))
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
                                value: bestRepetitionsThisMonth(workoutSets) != nil ? String(bestRepetitionsThisMonth(workoutSets)!) : "––",
                                unit: NSLocalizedString("rps", comment: ""),
                                configuration: .large
                            )
                            .foregroundStyle((exercise.muscleGroup?.color ?? Color.label).gradient)
                        }
                    }
                    Spacer()
                    Chart {
                        if let firstEntry = maxDailySets.first {
                            LineMark(
                                x: .value("Date", Date.distantPast, unit: .day),
                                y: .value("Max repetitions on day", firstEntry.maximum(.repetitions, for: exercise))
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(exerciseMuscleGroupColor.gradient)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                        }
                        ForEach(maxDailySets) { workoutSet in
                            LineMark(
                                x: .value("Date", workoutSet.workout?.date ?? .now, unit: .day),
                                y: .value("Max repetitions on day", workoutSet.maximum(.repetitions, for: exercise))
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
                                y: .value("Max repetitions on day", workoutSet.maximum(.repetitions, for: exercise))
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(Gradient(colors: [
                                exerciseMuscleGroupColor.opacity(0.3),
                                exerciseMuscleGroupColor.opacity(0.1),
                                exerciseMuscleGroupColor.opacity(0),
                            ]))
                        }
                        if let lastSet = maxDailySets.last, let lastDate = lastSet.workout?.date, !Calendar.current.isDateInToday(lastDate) {
                            let repetitionsDisplayed = lastSet.maximum(.repetitions, for: exercise)
                            RuleMark(
                                xStart: .value("Start", lastDate),
                                xEnd: .value("End", Date()),
                                y: .value("Max repetitions on day", repetitionsDisplayed)
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
                    .chartXAxis {}
                    .chartYScale(domain: 0 ... (Double(allTimeRepetitionsPREntry(in: workoutSets).0) * 1.1))
                    .chartYAxis {}
                    .frame(width: 120, height: 70)
                    .clipped()
                    .mask(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .black, location: 0.1),
                                .init(color: .black, location: 1.0)
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
                let allTimeRepeitionsPrEntry = allTimeRepetitionsPREntry(in: workoutSets)
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(NSLocalizedString("personalBest", comment: ""))
                            .fontWeight(.semibold)
                        Spacer()
                        if let allTimeRepetitionsPRDate = allTimeRepeitionsPrEntry.2 {
                            Text(allTimeRepetitionsPRDate.formatted(.dateTime.day().month().year()))
                        }
                    }
                    .foregroundStyle(.tertiary)
                    .font(.caption)
                    UnitView(value: "\(allTimeRepeitionsPrEntry.0)", unit: NSLocalizedString("rps", comment: ""), unitColor: .tertiaryLabel)
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
        let startDate = Calendar.current.date(byAdding: .second, value: -visibleChartDomainInSeconds, to: .now)!
        return startDate ... Date.now
    }

    private func maxRepetitionsDailySets(in groupedWorkoutSets: [[WorkoutSet]]) -> [WorkoutSet] {
        let maxSetsPerDay = groupedWorkoutSets.compactMap { setsPerDay -> WorkoutSet? in
            return setsPerDay.max(by: { $0.maximum(.repetitions, for: exercise) < $1.maximum(.repetitions, for: exercise) })
        }
        return maxSetsPerDay
    }

    private var exerciseMuscleGroupColor: Color {
        exercise.muscleGroup?.color ?? Color.accentColor
    }

    private var visibleChartDomainInSeconds: Int {
        3600 * 24 * 35
    }

    private func bestRepetitionsThisMonth(_ workoutSets: [WorkoutSet]) -> Int? {
        let startDate = Calendar.current.date(byAdding: .second, value: -visibleChartDomainInSeconds, to: .now)!
        let setsInTimeFrame = workoutSets.filter { $0.workout?.date ?? .distantPast >= startDate }
        guard !setsInTimeFrame.isEmpty else {
            return 0
        }
        return setsInTimeFrame
            .map { $0.maximum(.repetitions, for: exercise) }
            .max()
    }

    private func allTimeRepetitionsPREntry(in workoutSets: [WorkoutSet]) -> (Int, Int, Date?) {
        let workoutSet = workoutSets
            .max(by: { $0.maximum(.repetitions, for: exercise) < $1.maximum(.repetitions, for: exercise) })
        var maxRepetitions: Int64 = 0
        var weightOfMaxRepetitions: Int64 = 0
        var maxRepetitionsDate: Date?
        if let standardSet = workoutSet as? StandardSet {
            maxRepetitions = standardSet.repetitions
            weightOfMaxRepetitions = standardSet.weight
            maxRepetitionsDate = standardSet.workout?.date
        } else if let superSet = workoutSet as? SuperSet {
            if superSet.exercise == exercise {
                maxRepetitions = superSet.repetitionsFirstExercise
                weightOfMaxRepetitions = superSet.weightFirstExercise
                maxRepetitionsDate = superSet.workout?.date
            }
            if superSet.secondaryExercise == exercise, superSet.weightSecondExercise > maxRepetitions {
                maxRepetitions = superSet.repetitionsSecondExercise
                weightOfMaxRepetitions = superSet.weightSecondExercise
                maxRepetitionsDate = superSet.workout?.date
            }
        } else if let dropSet = workoutSet as? DropSet {
            for item in zip(dropSet.repetitions ?? [], dropSet.weights ?? []) {
                let shouldUpdate = item.0 > maxRepetitions
                maxRepetitions = shouldUpdate ? item.0 : maxRepetitions
                weightOfMaxRepetitions = shouldUpdate ? item.1 : weightOfMaxRepetitions
                maxRepetitionsDate = dropSet.workout?.date
            }
        }
        return (Int(maxRepetitions), convertWeightForDisplaying(weightOfMaxRepetitions), maxRepetitionsDate)
    }
}

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database

    var body: some View {
        NavigationStack {
            ExerciseRepetitionsTile(exercise: database.getExercises().first!, workoutSets: database.getExercises().flatMap { $0.sets })
        }
    }
}

struct ExerciseRepetitionsTileView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
            .padding()
    }
}
