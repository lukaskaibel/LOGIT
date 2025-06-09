//
//  ExercisePersonalBestsTile.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 17.01.25.
//

import SwiftUI

struct ExercisePersonalBestsTile: View {
    let exercise: Exercise
    let workoutSets: [WorkoutSet]

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text(NSLocalizedString("weightPR", comment: ""))
                    .textCase(.uppercase)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(alignment: .lastTextBaseline) {
                    UnitView(value: "\(allTimeWeightPREntry(in: workoutSets).0)", unit: WeightUnit.used.rawValue, configuration: .large)
                        .foregroundStyle(exerciseMuscleGroupColor.gradient)
                    Spacer()
                    HStack(spacing: 5) {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .fontDesign(.rounded)
                        UnitView(value: "\(allTimeWeightPREntry(in: workoutSets).1)", unit: NSLocalizedString("rps", comment: ""), configuration: .small)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(CELL_PADDING)
            VStack(alignment: .leading, spacing: 5) {
                Text(NSLocalizedString("repetitionsPR", comment: ""))
                    .textCase(.uppercase)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(alignment: .lastTextBaseline) {
                    UnitView(value: "\(allTimeRepetitionsPREntry(in: workoutSets).0)", unit: NSLocalizedString("rps", comment: ""), configuration: .large)
                        .foregroundStyle(exerciseMuscleGroupColor.gradient)
                    Spacer()
                    HStack(spacing: 5) {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .fontDesign(.rounded)
                        UnitView(value: "\(allTimeRepetitionsPREntry(in: workoutSets).1)", unit: WeightUnit.used.rawValue, configuration: .small)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(CELL_PADDING)
        }
        .tileStyle()
        .mask(
            HStack(spacing: 3) {
                Rectangle()
                Rectangle()
            }
        )
    }

    // MARK: - Private Methods

    private func allTimeWeightPREntry(in workoutSets: [WorkoutSet]) -> (Int, Int) {
        let workoutSet = workoutSets
            .max(by: { $0.maximum(.weight, for: exercise) < $1.maximum(.weight, for: exercise) })
        var maxWeight: Int64 = 0
        var repetitionsOfMaxWeight: Int64 = 0
        if let standardSet = workoutSet as? StandardSet {
            maxWeight = standardSet.weight
            repetitionsOfMaxWeight = standardSet.repetitions
        } else if let superSet = workoutSet as? SuperSet {
            if superSet.exercise == exercise {
                maxWeight = superSet.weightFirstExercise
                repetitionsOfMaxWeight = superSet.repetitionsFirstExercise
            }
            if superSet.secondaryExercise == exercise, superSet.weightSecondExercise > maxWeight {
                maxWeight = superSet.weightSecondExercise
                repetitionsOfMaxWeight = superSet.repetitionsSecondExercise
            }
        } else if let dropSet = workoutSet as? DropSet {
            for item in zip(dropSet.weights ?? [], dropSet.repetitions ?? []) {
                let shouldUpdate = item.0 > maxWeight
                maxWeight = shouldUpdate ? item.0 : maxWeight
                repetitionsOfMaxWeight = shouldUpdate ? item.1 : repetitionsOfMaxWeight
            }
        }
        return (convertWeightForDisplaying(maxWeight), Int(repetitionsOfMaxWeight))
    }

    private func allTimeRepetitionsPREntry(in workoutSets: [WorkoutSet]) -> (Int, Int) {
        let workoutSet = workoutSets
            .max(by: { $0.maximum(.repetitions, for: exercise) < $1.maximum(.repetitions, for: exercise) })
        var maxRepetitions: Int64 = 0
        var weightOfMaxRepetitions: Int64 = 0
        if let standardSet = workoutSet as? StandardSet {
            maxRepetitions = standardSet.repetitions
            weightOfMaxRepetitions = standardSet.weight
        } else if let superSet = workoutSet as? SuperSet {
            if superSet.exercise == exercise {
                maxRepetitions = superSet.repetitionsFirstExercise
                weightOfMaxRepetitions = superSet.weightFirstExercise
            }
            if superSet.secondaryExercise == exercise, superSet.weightSecondExercise > maxRepetitions {
                maxRepetitions = superSet.repetitionsSecondExercise
                weightOfMaxRepetitions = superSet.weightSecondExercise
            }
        } else if let dropSet = workoutSet as? DropSet {
            for item in zip(dropSet.repetitions ?? [], dropSet.weights ?? []) {
                let shouldUpdate = item.0 > maxRepetitions
                maxRepetitions = shouldUpdate ? item.0 : maxRepetitions
                weightOfMaxRepetitions = shouldUpdate ? item.1 : weightOfMaxRepetitions
            }
        }
        return (Int(maxRepetitions), convertWeightForDisplaying(weightOfMaxRepetitions))
    }

    private var exerciseMuscleGroupColor: Color {
        exercise.muscleGroup?.color ?? Color.accentColor
    }
}

// MARK: - Preview

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database

    var body: some View {
        NavigationView {
            ExercisePersonalBestsTile(exercise: database.getExercises().first!, workoutSets: database.getExercises().flatMap { $0.sets })
                .padding()
        }
    }
}

struct PersonalBestsScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
    }
}
