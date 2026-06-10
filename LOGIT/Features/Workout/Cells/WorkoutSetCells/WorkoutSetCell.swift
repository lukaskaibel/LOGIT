//
//  WorkoutSetCell.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 23.05.22.
//

import SwiftUI

struct WorkoutSetCell: View {
    // MARK: - Environment

    @Environment(\.canEdit) var canEdit: Bool
    @EnvironmentObject var database: Database

    // MARK: - Parameters

    @ObservedObject var workoutSet: WorkoutSet
    @Binding var focusedIntegerFieldIndex: IntegerField.Index?
    let referenceSet: WorkoutSet?
    let onEditRestDuration: (() -> Void)?
    let onTapPreviousSet: ((Exercise) -> Void)?

    // MARK: - State

    @State private var isEditingRestDuration = false

    init(
        workoutSet: WorkoutSet,
        focusedIntegerFieldIndex: Binding<IntegerField.Index?>,
        referenceSet: WorkoutSet? = nil,
        onEditRestDuration: (() -> Void)? = nil,
        onTapPreviousSet: ((Exercise) -> Void)? = nil
    ) {
        self.workoutSet = workoutSet
        _focusedIntegerFieldIndex = focusedIntegerFieldIndex
        self.referenceSet = referenceSet
        self.onEditRestDuration = onEditRestDuration
        self.onTapPreviousSet = onTapPreviousSet
    }

    // MARK: - Body

    var body: some View {
        Group {
            if canEdit {
                content
                    .contextMenu {
                        contextMenuContent
                    }
            } else {
                content
            }
        }
        .padding(.leading, CELL_PADDING)
        .padding([.top, .trailing], 8)
        .padding(.bottom, workoutSet as? DropSet != nil ? CELL_PADDING : 8)
        .sheet(isPresented: $isEditingRestDuration) {
            RestDurationEditorSheet(workoutSet: workoutSet)
                .presentationDetents([.fraction(0.65)])
                .padding()
                .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: - Supporting Views

    private var content: some View {
        VStack(spacing: 0) {
            if let indexInSetGroup = indexInSetGroup {
                HStack {
                    Text("\(indexInSetGroup + 1)")
                        .fontWeight(.bold)
                        .fontDesign(.rounded)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                    setContent
                }
                if let dropSet = workoutSet as? DropSet, canEdit {
                    Divider()
                        .padding(.top, 8)
                        .padding(.bottom, CELL_PADDING)
                    HStack {
                        Text(NSLocalizedString("dropCount", comment: ""))
                        Spacer()
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            dropSet.removeLastDrop()
                        } label: {
                            Image(systemName: "minus")
                                .fontWeight(.semibold)
                                .padding(.vertical, 5)
                                .padding(.horizontal, 10)
                        }
                        .disabled(dropSet.numberOfDrops < 2)
                        Text(String(dropSet.numberOfDrops))
                            .font(.body.weight(.medium).monospacedDigit())
                            .foregroundStyle(.primary)
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            dropSet.addDrop()
                        } label: {
                            Image(systemName: "plus")
                                .fontWeight(.semibold)
                                .padding(.vertical, 5)
                                .padding(.horizontal, 10)
                        }
                    }
                    .accentColor(dropSet.exercise?.muscleGroup?.color)
                }
            }
        }
    }

    @ViewBuilder
    private var setContent: some View {
        if let standardSet = workoutSet as? StandardSet {
            StandardSetCell(
                standardSet: standardSet,
                focusedIntegerFieldIndex: $focusedIntegerFieldIndex,
                referenceSet: referenceSet,
                onTapPreviousSet: onTapPreviousSet
            )
            .padding(.vertical, CELL_SPACING / 2)
        } else if let dropSet = workoutSet as? DropSet {
            DropSetCell(
                dropSet: dropSet,
                focusedIntegerFieldIndex: $focusedIntegerFieldIndex,
                referenceSet: referenceSet,
                onTapPreviousSet: onTapPreviousSet
            )
            .padding(.vertical, CELL_SPACING / 2)
        } else if let superSet = workoutSet as? SuperSet {
            SuperSetCell(
                superSet: superSet,
                focusedIntegerFieldIndex: $focusedIntegerFieldIndex,
                referenceSet: referenceSet,
                onTapPreviousSet: onTapPreviousSet
            )
            .padding(.vertical, CELL_SPACING / 2)
        }
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        Section {
            Button {
                if let onEditRestDuration {
                    onEditRestDuration()
                } else {
                    isEditingRestDuration = true
                }
            } label: {
                Label(
                    NSLocalizedString(
                        workoutSet.restDurationSeconds > 0 ? "editRest" : "addRest",
                        comment: ""
                    ),
                    systemImage: "clock"
                )
            }
        }

        Section {
            Button {
                withAnimation(.interactiveSpring()) {
                    database.addSet(before: workoutSet)
                }
            } label: {
                Label(
                    NSLocalizedString("addSetBefore", comment: ""),
                    systemImage: "arrow.up.to.line.circle"
                )
            }

            Button {
                withAnimation(.interactiveSpring()) {
                    database.addSet(after: workoutSet)
                }
            } label: {
                Label(
                    NSLocalizedString("addSetAfter", comment: ""),
                    systemImage: "arrow.down.to.line.circle"
                )
            }
        }

        Section {
            Button {
                withAnimation(.interactiveSpring()) {
                    database.duplicateSet(workoutSet)
                }
            } label: {
                Label(NSLocalizedString("copySet", comment: ""), systemImage: "plus.square.on.square")
            }

            Button(role: .destructive) {
                withAnimation(.interactiveSpring()) {
                    database.delete(workoutSet)
                }
            } label: {
                Label(NSLocalizedString("remove", comment: ""), systemImage: "xmark.circle")
            }
        }
    }

    // MARK: - Supporting Methods

    private var indexInSetGroup: Int? {
        workoutSet.setGroup?.sets.firstIndex(of: workoutSet)
    }

}

struct WorkoutSetReferenceValue: Equatable {
    let repetitions: Int64
    let weight: Int64

    var hasEntry: Bool {
        repetitions > 0 || weight > 0
    }

    var displayText: String {
        if repetitions > 0, weight > 0 {
            return "\(repetitions) x \(formatWeightForDisplay(weight)) \(WeightUnit.used.rawValue)"
        }

        if repetitions > 0 {
            return "\(repetitions) \(NSLocalizedString("reps", comment: ""))"
        }

        return "\(formatWeightForDisplay(weight)) \(WeightUnit.used.rawValue)"
    }

}

struct PreviousSetReferenceLabel: View {
    let reference: WorkoutSetReferenceValue?
    let onTap: () -> Void

    var body: some View {
        Group {
            if let reference, reference.hasEntry {
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    onTap()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.caption2)
                        Text(reference.displayText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(NSLocalizedString("lastSetReferencePrefix", comment: "") + " " + reference.displayText))
            } else {
                Color.clear
            }
        }
        .font(.system(.caption, design: .rounded, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

// MARK: - Set Value Delta Helpers

/// Compares an entered repetition count against the previous workout's value.
/// Returns `(nil, "")` when there is nothing meaningful to show (no reference,
/// empty entry, or unchanged).
func repsDelta(current: Int64, previous: Int64?) -> (comparison: SetValueComparison?, text: String) {
    guard let previous, previous > 0, current > 0, current != previous else { return (nil, "") }
    return (current > previous ? .improved : .declined, String(abs(current - previous)))
}

/// Compares an entered weight (in grams) against the previous workout's value.
/// Direction and text are computed in display units (kg/lbs) so they match what the
/// user sees and avoid rounding artefacts from differencing raw gram values.
func weightDelta(currentGrams: Int64, previousGrams: Int64?) -> (comparison: SetValueComparison?, text: String) {
    guard let previousGrams, previousGrams > 0, currentGrams > 0 else { return (nil, "") }
    let current = convertWeightForDisplayingDecimal(currentGrams)
    let previous = convertWeightForDisplayingDecimal(previousGrams)
    guard current != previous else { return (nil, "") }
    return (current > previous ? .improved : .declined, formatDisplayWeightDelta(abs(current - previous)))
}

private func formatDisplayWeightDelta(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 3
    formatter.decimalSeparator = "."
    formatter.groupingSeparator = ""
    return formatter.string(from: NSNumber(value: value)) ?? "0"
}

// MARK: - Preview

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database

    private var standardSet: WorkoutSet? {
        let workouts = database.fetch(Workout.self) as! [Workout]
        let sets = workouts.flatMap(\.sets)
        return sets.first(where: { $0 is StandardSet })
    }

    private var dropSet: WorkoutSet? {
        let workouts = database.fetch(Workout.self) as! [Workout]
        let sets = workouts.flatMap(\.sets)
        return sets.first(where: { $0 is DropSet })
    }

    private var superSet: WorkoutSet? {
        let workouts = database.fetch(Workout.self) as! [Workout]
        let sets = workouts.flatMap(\.sets)
        return sets.first(where: { $0 is SuperSet })
    }

    var body: some View {
        ScrollView {
            VStack(spacing: CELL_PADDING) {
                if let standardSet {
                    previewSection(title: "Standard Set", workoutSet: standardSet)
                }
                if let dropSet {
                    previewSection(title: "Drop Set", workoutSet: dropSet)
                    previewSection(title: "Read-Only Drop Set", workoutSet: dropSet, canEdit: false)
                }
                if let superSet {
                    previewSection(title: "Superset", workoutSet: superSet)
                }
            }
            .padding()
        }
    }

    private func previewSection(
        title: String,
        workoutSet: WorkoutSet,
        canEdit: Bool = true
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            WorkoutSetCell(
                workoutSet: workoutSet,
                focusedIntegerFieldIndex: .constant(nil)
            )
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(.shadow(.inner(color: .black.opacity(0.4), radius: 5)))
                    .foregroundStyle(Color.tertiaryBackground)
            )
            .cornerRadius(15)
            .canEdit(canEdit)
        }
    }
}

struct WorkoutSetCell_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
    }
}
