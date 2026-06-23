//
//  PinnedExerciseRepetitionsTile.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 30.11.24.
//

import Charts
import SwiftUI

struct PinnedExerciseRepetitionsTile: View {
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
                    Text(exercise.displayName)
                        .tileHeaderStyle()
                    Spacer()
                    NavigationChevron()
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading) {
                        VStack(alignment: .leading) {
                            Text(NSLocalizedString("repetitions", comment: ""))
                                .foregroundStyle(.secondary)
                                .font(.footnote)
                                .fontWeight(.semibold)
                            UnitView(
                                value: currentBestRepetitions(workoutSets) != nil ? String(currentBestRepetitions(workoutSets)!) : "––",
                                unit: NSLocalizedString("rps", comment: ""),
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
                                    value: Double($0.maximum(.repetitions, for: exercise))
                                )
                            },
                            color: exerciseMuscleGroupColor
                        )
                    }
                    .chartXScale(domain: xDomain)
                    .chartXAxis {}
                    .chartYScale(domain: 0 ... (Double(allTimeRepetitionsPREntry(in: workoutSets).0) * 1.1))
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

    private func currentBestRepetitions(_ workoutSets: [WorkoutSet]) -> Int? {
        exercise.currentBestSet(for: .repetitions, in: workoutSets)
            .map { $0.maximum(.repetitions, for: exercise) }
    }

    private func allTimeRepetitionsPREntry(in workoutSets: [WorkoutSet]) -> (Int, String, Date?) {
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
        return (Int(maxRepetitions), formatWeightForDisplay(weightOfMaxRepetitions), maxRepetitionsDate)
    }
}

struct PinnedExerciseRepetitionsTile_Previews: PreviewProvider {
    @EnvironmentObject static var database: Database

    static var previews: some View {
        PinnedExerciseRepetitionsTile(exercise: database.getExercises().first!, workoutSets: database.getExercises().flatMap { $0.sets })
            .previewEnvironmentObjects()
    }
}
