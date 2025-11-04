//
//  DropSetCell.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 13.05.22.
//

import SwiftUI

struct DropSetCell: View {
    // MARK: - Environment

    @EnvironmentObject var database: Database
    @EnvironmentObject var workoutRecorder: WorkoutRecorder

    // MARK: - Parameters

    @ObservedObject var dropSet: DropSet
    @Binding var focusedIntegerFieldIndex: IntegerField.Index?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if let indexInWorkout = indexInWorkout {
                ForEach(0 ..< (dropSet.repetitions?.count ?? 0), id: \.self) { index in
                    HStack {
                        IntegerField(
                            placeholder: repetitionsPlaceholder(for: dropSet).value(at: index) ?? 0,
                            value: repetitionsBinding(forIndex: index),
                            maxDigits: 4,
                            index: IntegerField.Index(
                                primary: indexInWorkout,
                                secondary: index,
                                tertiary: 0
                            ),
                            focusedIntegerFieldIndex: $focusedIntegerFieldIndex,
                            unit: NSLocalizedString("reps", comment: "")
                        )
                        DecimalField(
                            placeholder: weightsPlaceholderDecimal(for: dropSet).value(at: index) ?? 0,
                            value: weightsBindingDecimal(forIndex: index),
                            maxDigits: 4,
                            decimalPlaces: 3,
                            index: IntegerField.Index(
                                primary: indexInWorkout,
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

    private var indexInWorkout: Int? {
        dropSet.workout?.sets.firstIndex(of: dropSet)
    }

    private func repetitionsBinding(forIndex index: Int) -> Binding<Int64> {
        Binding(
            get: {
                Int64(dropSet.repetitions?.value(at: index) ?? 0)
            },
            set: { newValue in
                dropSet.repetitions?[index] = newValue
            }
        )
    }

    private func weightsBinding(forIndex index: Int) -> Binding<Int64> {
        Binding(
            get: {
                Int64(convertWeightForDisplaying(dropSet.weights?.value(at: index) ?? 0))
            },
            set: { newValue in
                dropSet.weights?[index] = convertWeightForStoring(newValue)
            }
        )
    }
    
    private func weightsBindingDecimal(forIndex index: Int) -> Binding<Double> {
        Binding(
            get: {
                convertWeightForDisplayingDecimal(dropSet.weights?.value(at: index) ?? 0)
            },
            set: { newValue in
                dropSet.weights?[index] = convertWeightForStoring(newValue)
            }
        )
    }

    private func repetitionsPlaceholder(for dropSet: DropSet) -> [Int64] {
        guard let templateDropSet = workoutRecorder.templateSet(for: dropSet) as? TemplateDropSet
        else {
            return [0]
        }
        return templateDropSet.repetitions?.map { $0 } ?? .emptyList
    }

    private func weightsPlaceholder(for dropSet: DropSet) -> [Int64] {
        guard let templateDropSet = workoutRecorder.templateSet(for: dropSet) as? TemplateDropSet
        else {
            return [0]
        }
        return templateDropSet.weights?.map { Int64(convertWeightForDisplaying($0)) } ?? .emptyList
    }
    
    private func weightsPlaceholderDecimal(for dropSet: DropSet) -> [Double] {
        guard let templateDropSet = workoutRecorder.templateSet(for: dropSet) as? TemplateDropSet
        else {
            return [0]
        }
        return templateDropSet.weights?.map { convertWeightForDisplayingDecimal($0) } ?? .emptyList
    }
}
