//
//  StandardSetCell.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 13.05.22.
//

import SwiftUI

struct StandardSetCell: View {
    // MARK: - Environment

    @Environment(\.canEdit) private var canEdit
    @EnvironmentObject var database: Database
    @EnvironmentObject var workoutRecorder: WorkoutRecorder

    // MARK: - Parameters

    @ObservedObject var standardSet: StandardSet
    @Binding var focusedIntegerFieldIndex: IntegerField.Index?
    let referenceSet: WorkoutSet?
    var onTapPreviousSet: ((Exercise) -> Void)? = nil

    // MARK: - Body

    var body: some View {
        HStack {
            if let indexInWorkout = indexInWorkout {
                PreviousSetReferenceLabel(reference: referenceValue) {
                    if let exercise = standardSet.setGroup?.exercise {
                        onTapPreviousSet?(exercise)
                    }
                }
                .opacity(canEdit && standardSet.hasEntry ? 0 : 1)
                .animation(.easeInOut(duration: 0.2), value: standardSet.hasEntry)
                IntegerField(
                    placeholder: repetitionsPlaceholder(for: standardSet),
                    value: $standardSet.repetitions,
                    maxDigits: 4,
                    index: IntegerField.Index(
                        primary: indexInWorkout,
                        secondary: 0,
                        tertiary: 0
                    ),
                    focusedIntegerFieldIndex: $focusedIntegerFieldIndex,
                    unit: NSLocalizedString("reps", comment: ""),
                    trend: repetitionsDelta.comparison,
                    trendText: repetitionsDelta.text,
                    trendColor: muscleColor
                )
                DecimalField(
                    placeholder: weightPlaceholderDecimal(for: standardSet),
                    value: Binding(
                        get: { convertWeightForDisplayingDecimal(standardSet.weight) },
                        set: { standardSet.weight = convertWeightForStoring($0) }
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
                    trend: weightDeltaResult.comparison,
                    trendText: weightDeltaResult.text,
                    trendColor: muscleColor
                )
            }
        }
    }

    // MARK: - Supporting Methods

    private var indexInWorkout: Int? {
        standardSet.workout?.sets.firstIndex(of: standardSet)
    }

    private var referenceStandardSet: StandardSet? {
        referenceSet as? StandardSet
    }

    private var referenceValue: WorkoutSetReferenceValue? {
        guard let referenceStandardSet else { return nil }
        return WorkoutSetReferenceValue(
            repetitions: referenceStandardSet.repetitions,
            weight: referenceStandardSet.weight
        )
    }

    private var repetitionsDelta: (comparison: SetValueComparison?, text: String) {
        repsDelta(current: standardSet.repetitions, previous: referenceStandardSet?.repetitions)
    }

    private var weightDeltaResult: (comparison: SetValueComparison?, text: String) {
        weightDelta(currentGrams: standardSet.weight, previousGrams: referenceStandardSet?.weight)
    }

    private var muscleColor: Color {
        standardSet.setGroup?.exercise?.muscleGroup?.color ?? .accentColor
    }

    private func copyReferenceValues() {
        guard let referenceStandardSet = referenceSet as? StandardSet else { return }
        standardSet.repetitions = referenceStandardSet.repetitions
        standardSet.weight = referenceStandardSet.weight
    }

    private func repetitionsPlaceholder(for standardSet: StandardSet) -> Int64 {
        guard
            let templateStandardSet = workoutRecorder.templateSet(for: standardSet)
            as? TemplateStandardSet
        else { return 0 }
        return templateStandardSet.repetitions
    }

    private func weightPlaceholder(for standardSet: StandardSet) -> Int64 {
        guard
            let templateStandardSet = workoutRecorder.templateSet(for: standardSet)
            as? TemplateStandardSet
        else { return 0 }
        return Int64(convertWeightForDisplaying(templateStandardSet.weight))
    }
    
    private func weightPlaceholderDecimal(for standardSet: StandardSet) -> Double {
        guard
            let templateStandardSet = workoutRecorder.templateSet(for: standardSet)
            as? TemplateStandardSet
        else { return 0 }
        return convertWeightForDisplayingDecimal(templateStandardSet.weight)
    }
}
