//
//  SuperSetCell.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 28.05.22.
//

import SwiftUI

struct SuperSetCell: View {
    // MARK: - Environment

    @Environment(\.canEdit) private var canEdit
    @EnvironmentObject var database: Database
    @EnvironmentObject var workoutRecorder: WorkoutRecorder

    // MARK: - Parameters

    @ObservedObject var superSet: SuperSet
    @Binding var focusedIntegerFieldIndex: IntegerField.Index?
    let referenceSet: WorkoutSet?
    var onTapPreviousSet: ((Exercise) -> Void)? = nil

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if let indexInWorkout = indexInWorkout {
                HStack {
                    PreviousSetReferenceLabel(reference: referenceValue(for: superSet.exercise)) {
                        if let exercise = superSet.exercise {
                            onTapPreviousSet?(exercise)
                        }
                    }
                    .opacity(canEdit && firstExerciseHasEntry ? 0 : 1)
                    .animation(.easeInOut(duration: 0.2), value: firstExerciseHasEntry)
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
                        unit: NSLocalizedString("reps", comment: ""),
                        trend: repetitionsDelta(current: superSet.repetitionsFirstExercise, for: superSet.exercise).comparison,
                        trendText: repetitionsDelta(current: superSet.repetitionsFirstExercise, for: superSet.exercise).text,
                        trendColor: muscleColor(for: superSet.exercise)
                    )
                    DecimalField(
                        placeholder: weightsPlaceholderDecimal(for: superSet).first!,
                        value: Binding(
                            get: { convertWeightForDisplayingDecimal(superSet.weightFirstExercise) },
                            set: { superSet.weightFirstExercise = convertWeightForStoring($0) }
                        ),
                        maxDigits: 4,
                        decimalPlaces: 3,
                        index: IntegerField.Index(
                            primary: indexInWorkout,
                            secondary: 0,
                            tertiary: 1
                        ),
                        focusedIntegerFieldIndex: $focusedIntegerFieldIndex,
                        unit: WeightUnit.used.rawValue,
                        trend: weightDeltaResult(currentGrams: superSet.weightFirstExercise, for: superSet.exercise).comparison,
                        trendText: weightDeltaResult(currentGrams: superSet.weightFirstExercise, for: superSet.exercise).text,
                        trendColor: muscleColor(for: superSet.exercise)
                    )
                }
                HStack {
                    PreviousSetReferenceLabel(reference: referenceValue(for: superSet.secondaryExercise)) {
                        if let exercise = superSet.secondaryExercise {
                            onTapPreviousSet?(exercise)
                        }
                    }
                    .opacity(canEdit && secondExerciseHasEntry ? 0 : 1)
                    .animation(.easeInOut(duration: 0.2), value: secondExerciseHasEntry)
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
                        unit: NSLocalizedString("reps", comment: ""),
                        trend: repetitionsDelta(current: superSet.repetitionsSecondExercise, for: superSet.secondaryExercise).comparison,
                        trendText: repetitionsDelta(current: superSet.repetitionsSecondExercise, for: superSet.secondaryExercise).text,
                        trendColor: muscleColor(for: superSet.secondaryExercise)
                    )
                    DecimalField(
                        placeholder: weightsPlaceholderDecimal(for: superSet).second!,
                        value: Binding(
                            get: { convertWeightForDisplayingDecimal(superSet.weightSecondExercise) },
                            set: { superSet.weightSecondExercise = convertWeightForStoring($0) }
                        ),
                        maxDigits: 4,
                        decimalPlaces: 3,
                        index: IntegerField.Index(
                            primary: indexInWorkout,
                            secondary: 1,
                            tertiary: 1
                        ),
                        focusedIntegerFieldIndex: $focusedIntegerFieldIndex,
                        unit: WeightUnit.used.rawValue,
                        trend: weightDeltaResult(currentGrams: superSet.weightSecondExercise, for: superSet.secondaryExercise).comparison,
                        trendText: weightDeltaResult(currentGrams: superSet.weightSecondExercise, for: superSet.secondaryExercise).text,
                        trendColor: muscleColor(for: superSet.secondaryExercise)
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

    private func referenceValue(for exercise: Exercise?) -> WorkoutSetReferenceValue? {
        guard let referenceValues = referenceValues(for: exercise) else { return nil }
        return WorkoutSetReferenceValue(
            repetitions: referenceValues.repetitions,
            weight: referenceValues.weight
        )
    }

    private var firstExerciseHasEntry: Bool {
        superSet.repetitionsFirstExercise > 0 || superSet.weightFirstExercise > 0
    }

    private var secondExerciseHasEntry: Bool {
        superSet.repetitionsSecondExercise > 0 || superSet.weightSecondExercise > 0
    }

    private func repetitionsDelta(
        current: Int64,
        for exercise: Exercise?
    ) -> (comparison: SetValueComparison?, text: String) {
        repsDelta(current: current, previous: referenceValues(for: exercise)?.repetitions)
    }

    private func weightDeltaResult(
        currentGrams: Int64,
        for exercise: Exercise?
    ) -> (comparison: SetValueComparison?, text: String) {
        weightDelta(currentGrams: currentGrams, previousGrams: referenceValues(for: exercise)?.weight)
    }

    private func muscleColor(for exercise: Exercise?) -> Color {
        exercise?.muscleGroup?.color ?? .accentColor
    }

    private func referenceValues(for exercise: Exercise?) -> (repetitions: Int64, weight: Int64)? {
        guard let exercise, let referenceSuperSet = referenceSet as? SuperSet else { return nil }

        if referenceSuperSet.exercise == exercise {
            return (
                referenceSuperSet.repetitionsFirstExercise,
                referenceSuperSet.weightFirstExercise
            )
        }

        if referenceSuperSet.secondaryExercise == exercise {
            return (
                referenceSuperSet.repetitionsSecondExercise,
                referenceSuperSet.weightSecondExercise
            )
        }

        return nil
    }

    private func copyReferenceValues(for exercise: Exercise?, toPrimaryExercise: Bool) {
        guard let referenceValues = referenceValues(for: exercise) else { return }

        if toPrimaryExercise {
            superSet.repetitionsFirstExercise = referenceValues.repetitions
            superSet.weightFirstExercise = referenceValues.weight
        } else {
            superSet.repetitionsSecondExercise = referenceValues.repetitions
            superSet.weightSecondExercise = referenceValues.weight
        }
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
    
    private func weightsPlaceholderDecimal(for superSet: SuperSet) -> [Double] {
        guard let templateSuperSet = workoutRecorder.templateSet(for: superSet) as? TemplateSuperSet
        else { return [0, 0] }
        return [templateSuperSet.weightFirstExercise, templateSuperSet.weightSecondExercise]
            .map { convertWeightForDisplayingDecimal($0) }
    }
}
