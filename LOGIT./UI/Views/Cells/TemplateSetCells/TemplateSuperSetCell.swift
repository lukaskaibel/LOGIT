//
//  TemplateSuperSetCell.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 28.05.22.
//

import SwiftUI

struct TemplateSuperSetCell: View {

    // MARK: - Environment

    @EnvironmentObject var database: Database

    // MARK: - Parameters

    @ObservedObject var superSet: TemplateSuperSet
    @Binding var focusedIntegerFieldIndex: IntegerField.Index?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if let indexInTemplate = indexInTemplate {
                HStack {
                    Text("1")
                        .foregroundColor(.secondaryLabel)
                        .font(.footnote)
                    IntegerField(
                        placeholder: 0,
                        value: $superSet.repetitionsFirstExercise,
                        maxDigits: 4,
                        index: IntegerField.Index(
                            primary: indexInTemplate,
                            secondary: 0,
                            tertiary: 0
                        ),
                        focusedIntegerFieldIndex: $focusedIntegerFieldIndex,
                        unit: NSLocalizedString("reps", comment: "")
                    )
                    IntegerField(
                        placeholder: 0,
                        value: Binding(
                            get: { Int64(convertWeightForDisplaying(superSet.weightFirstExercise)) },
                            set: { superSet.weightFirstExercise = convertWeightForStoring($0) }
                        ),
                        maxDigits: 4,
                        index: IntegerField.Index(
                            primary: indexInTemplate,
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
                        placeholder: 0,
                        value: $superSet.repetitionsSecondExercise,
                        maxDigits: 4,
                        index: IntegerField.Index(
                            primary: indexInTemplate,
                            secondary: 1,
                            tertiary: 0
                        ),
                        focusedIntegerFieldIndex: $focusedIntegerFieldIndex,
                        unit: NSLocalizedString("reps", comment: "")
                    )
                    IntegerField(
                        placeholder: 0,
                        value: Binding(
                            get: { Int64(convertWeightForDisplaying(superSet.weightSecondExercise)) },
                            set: { superSet.weightSecondExercise = convertWeightForStoring($0) }
                        ),
                        maxDigits: 4,
                        index: IntegerField.Index(
                            primary: indexInTemplate,
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

    private var indexInTemplate: Int? {
        superSet.setGroup?.workout?.sets.firstIndex(of: superSet)
    }

}
