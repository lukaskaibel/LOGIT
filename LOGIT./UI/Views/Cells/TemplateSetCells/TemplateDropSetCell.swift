//
//  TemplateDropSetCell.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 13.05.22.
//

import SwiftUI

struct TemplateDropSetCell: View {

    // MARK: - Environment

    @EnvironmentObject var database: Database

    // MARK: - Parameters

    @ObservedObject var dropSet: TemplateDropSet
    @Binding var focusedIntegerFieldIndex: IntegerField.Index?

    // MARK: - Body

    var body: some View {
        VStack {
            if let indexInTemplate = indexInTemplate {
                ForEach(0..<(dropSet.repetitions?.count ?? 0), id: \.self) { index in
                    HStack {
                        IntegerField(
                            placeholder: 0,
                            value: repetitionsBinding(forIndex: index),
                            maxDigits: 4,
                            index: IntegerField.Index(
                                primary: indexInTemplate,
                                secondary: index,
                                tertiary: 0
                            ),
                            focusedIntegerFieldIndex: $focusedIntegerFieldIndex,
                            unit: NSLocalizedString("reps", comment: "")
                        )
                        IntegerField(
                            placeholder: 0,
                            value: weightsBinding(forIndex: index),
                            maxDigits: 4,
                            index: IntegerField.Index(
                                primary: indexInTemplate,
                                secondary: index,
                                tertiary: 1
                            ),
                            focusedIntegerFieldIndex: $focusedIntegerFieldIndex,
                            unit: WeightUnit.used.rawValue
                        )
                    }
                }
            }
        }
    }

    // MARK: - Supporting Methods

    private var indexInTemplate: Int? {
        dropSet.setGroup?.workout?.sets.firstIndex(of: dropSet)
    }
    
    private func repetitionsBinding(forIndex index: Int) -> Binding<Int64> {
        Binding(
            get: {
                return Int64(dropSet.repetitions?.value(at: index) ?? 0)
            },
            set: { newValue in
                dropSet.repetitions?[index] = newValue
            }
        )
    }
    
    private func weightsBinding(forIndex index: Int) -> Binding<Int64> {
        Binding(
            get: {
                return Int64(convertWeightForDisplaying(dropSet.weights?.value(at: index) ?? 0))
            },
            set: { newValue in
                dropSet.weights?[index] = convertWeightForStoring(newValue)
            }
        )
    }

}
