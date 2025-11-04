//
//  StandardSetCell.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 13.05.22.
//

import SwiftUI

struct StandardSetCell: View {
    // MARK: - Environment

    @EnvironmentObject var database: Database
    @EnvironmentObject var workoutRecorder: WorkoutRecorder

    // MARK: - Parameters

    @ObservedObject var standardSet: StandardSet
    @Binding var focusedIntegerFieldIndex: IntegerField.Index?

    // MARK: - Body

    var body: some View {
        HStack {
            if let indexInWorkout = indexInWorkout {
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
                    unit: NSLocalizedString("reps", comment: "")
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
                    unit: WeightUnit.used.rawValue
                )
            }
        }
    }

    // MARK: - Supporting Methods

    private var indexInWorkout: Int? {
        standardSet.workout?.sets.firstIndex(of: standardSet)
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
