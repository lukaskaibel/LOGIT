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
    let onEditRestDuration: (() -> Void)?

    // MARK: - State

    @State private var isEditingRestDuration = false

    init(
        workoutSet: WorkoutSet,
        focusedIntegerFieldIndex: Binding<IntegerField.Index?>,
        onEditRestDuration: (() -> Void)? = nil
    ) {
        self.workoutSet = workoutSet
        _focusedIntegerFieldIndex = focusedIntegerFieldIndex
        self.onEditRestDuration = onEditRestDuration
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
                    Spacer()
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
                focusedIntegerFieldIndex: $focusedIntegerFieldIndex
            )
            .padding(.top, workoutSetIsFirst(workoutSet: workoutSet) ? 0 : CELL_SPACING / 2)
            .padding(.bottom, workoutSetIsLast(workoutSet: workoutSet) ? 0 : CELL_SPACING / 2)
        } else if let dropSet = workoutSet as? DropSet {
            DropSetCell(
                dropSet: dropSet,
                focusedIntegerFieldIndex: $focusedIntegerFieldIndex
            )
            .padding(.top, workoutSetIsFirst(workoutSet: workoutSet) ? 0 : CELL_SPACING / 2)
            .padding(.bottom, workoutSetIsLast(workoutSet: workoutSet) ? 0 : CELL_SPACING / 2)
        } else if let superSet = workoutSet as? SuperSet {
            SuperSetCell(
                superSet: superSet,
                focusedIntegerFieldIndex: $focusedIntegerFieldIndex
            )
            .padding(.top, workoutSetIsFirst(workoutSet: workoutSet) ? 0 : CELL_SPACING / 2)
            .padding(.bottom, workoutSetIsLast(workoutSet: workoutSet) ? 0 : CELL_SPACING / 2)
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

    private func workoutSetIsFirst(workoutSet: WorkoutSet) -> Bool {
        guard let setGroup = workoutSet.setGroup else { return false }
        return setGroup.sets.firstIndex(of: workoutSet) == 0
    }

    private func workoutSetIsLast(workoutSet: WorkoutSet) -> Bool {
        guard let setGroup = workoutSet.setGroup else { return false }
        return setGroup.sets.firstIndex(of: workoutSet) == setGroup.numberOfSets - 1
    }
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
