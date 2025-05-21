//
//  SuperSetCell.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 28.05.22.
//

import SwiftUI

struct SuperSetCell: View {

    // MARK: - Environment

    @EnvironmentObject var database: Database
    @EnvironmentObject var workoutRecorder: WorkoutRecorder

    // MARK: - Parameters

    @ObservedObject var superSet: SuperSet
    @Binding var focusedIntegerFieldIndex: IntegerField.Index?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if let indexInWorkout = indexInWorkout {
                HStack {
                    Text("1")
                        .foregroundColor(.secondaryLabel)
                        .font(.footnote)
                    IntegerField(
                        placeholder: repetitionsPlaceholder(for: superSet).first!,
                        value: $superSet.repetitionsFirstExercise,
                        maxDigits: 4,
                        index: IntegerField.Index(
                            primary: indexInWorkout,
                            secondary: 0,
                            tertiary: 0
                        ),
                        focusedIntegerFieldIndex: $focusedIntegerFieldIndex,
                        unit: NSLocalizedString("reps", comment: "")
                    )
                    IntegerField(
                        placeholder: weightsPlaceholder(for: superSet).first!,
                        value: Binding(
                            get: { Int64(convertWeightForDisplaying(superSet.weightFirstExercise)) },
                            set: { superSet.weightFirstExercise = convertWeightForStoring($0) }
                        ),
                        maxDigits: 4,
                        index: IntegerField.Index(
                            primary: indexInWorkout,
                            secondary: 0,
                            tertiary: 1
                        ),
                        focusedIntegerFieldIndex: $focusedIntegerFieldIndex,
                        unit: WeightUnit.used.rawValue
                    )
                }
                HStack {
                    Text("2")
                        .foregroundColor(.secondaryLabel)
                        .font(.footnote)
                    IntegerField(
                        placeholder: repetitionsPlaceholder(for: superSet).second!,
                        value: $superSet.repetitionsSecondExercise,
                        maxDigits: 4,
                        index: IntegerField.Index(
                            primary: indexInWorkout,
                            secondary: 1,
                            tertiary: 0
                        ),
                        focusedIntegerFieldIndex: $focusedIntegerFieldIndex,
                        unit: NSLocalizedString("reps", comment: "")
                    )
                    IntegerField(
                        placeholder: weightsPlaceholder(for: superSet).second!,
                        value: Binding(
                            get: { Int64(convertWeightForDisplaying(superSet.weightSecondExercise)) },
                            set: { superSet.weightSecondExercise = convertWeightForStoring($0) }
                        ),
                        maxDigits: 4,
                        index: IntegerField.Index(
                            primary: indexInWorkout,
                            secondary: 1,
                            tertiary: 1
                        ),
                        focusedIntegerFieldIndex: $focusedIntegerFieldIndex,
                        unit: WeightUnit.used.rawValue
                    )
                }
                .accentColor(superSet.secondaryExercise?.muscleGroup?.color)
            }
        }
    }

    // MARK: - Supporting Methods

    private var indexInWorkout: Int? {
        superSet.workout?.sets.firstIndex(of: superSet)
    }

    private func repetitionsPlaceholder(for superSet: SuperSet) -> [Int64] {
        guard let templateSuperSet = workoutRecorder.templateSet(for: superSet) as? TemplateSuperSet
        else { return [0, 0] }
        return [
            templateSuperSet.repetitionsFirstExercise, templateSuperSet.repetitionsSecondExercise,
        ]
        .map { $0 }
    }

    private func weightsPlaceholder(for superSet: SuperSet) -> [Int64] {
        guard let templateSuperSet = workoutRecorder.templateSet(for: superSet) as? TemplateSuperSet
        else { return [0, 0] }
        return [templateSuperSet.weightFirstExercise, templateSuperSet.weightSecondExercise]
            .map { Int64(convertWeightForDisplaying($0)) }
    }

}
