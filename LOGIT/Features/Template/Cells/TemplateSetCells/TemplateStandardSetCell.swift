//
//  TemplateStandardSetCell.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 13.05.22.
//

import SwiftUI

struct TemplateStandardSetCell: View {
    // MARK: - Environment

    @EnvironmentObject var database: Database

    // MARK: - Parameters

    @ObservedObject var standardSet: TemplateStandardSet
    @Binding var focusedIntegerFieldIndex: IntegerField.Index?

    // MARK: - Body

    var body: some View {
        HStack {
            if let indexInTemplate = indexInTemplate {
                IntegerField(
                    placeholder: 0,
                    value: $standardSet.repetitions,
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
                        get: { Int64(convertWeightForDisplaying(standardSet.weight)) },
                        set: { standardSet.weight = convertWeightForStoring($0) }
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
        }
    }

    // MARK: - Supporting Methods

    private var indexInTemplate: Int? {
        standardSet.setGroup?.workout?.sets.firstIndex(of: standardSet)
    }
}
