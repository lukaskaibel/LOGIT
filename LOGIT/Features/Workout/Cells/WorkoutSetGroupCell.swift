//
//  WorkoutSetGroupCell.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 28.07.23.
//

import SwiftUI

struct WorkoutSetGroupCell: View {
    // MARK: - Environment

    @Environment(\.canEdit) var canEdit: Bool
    @EnvironmentObject var database: Database

    // MARK: - Parameters

    @ObservedObject var setGroup: WorkoutSetGroup

    @Binding var focusedIntegerFieldIndex: IntegerField.Index?
    @Binding var isReordering: Bool

    let supplementaryText: String?
    var shouldShowExerciseDetailInSheet: Bool = false

    // MARK: - State

    @State private var isReorderingSets = false
    @State private var isHeaderExpanded = false
    @State private var isSelectingPrimaryExercise = false
    @State private var primaryExerciseSelectionSheetDetend: PresentationDetent? = .large
    @State private var isSelectingSecondaryExercise = false
    @State private var isEditingNote = false
    @FocusState private var isNoteFieldFocused: Bool

    // MARK: - Body

    var body: some View {
        VStack(spacing: CELL_PADDING) {
            header
                .padding([.top, .horizontal], CELL_PADDING)

            if !isReordering {
                VStack(spacing: CELL_PADDING) {
                    VStack(spacing: CELL_SPACING) {
                        ReorderableForEach(
                            $setGroup.sets,
                            canReorder: canEdit,
                            isReordering: $isReorderingSets
                        ) { workoutSet in
                            WorkoutSetCell(
                                workoutSet: workoutSet,
                                focusedIntegerFieldIndex: $focusedIntegerFieldIndex
                            )
                            .contentShape(Rectangle())
                            .onDelete(disabled: !canEdit) {
                                withAnimation(.interactiveSpring()) {
                                    database.delete(workoutSet)
                                }
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 15)
                                    .fill(.shadow(.inner(color: .black.opacity(0.4), radius: 5)))
                                    .foregroundStyle(Color.secondaryBackground)
                            )
                            .cornerRadius(15)
                        }
                    }
                    .padding(.horizontal, CELL_PADDING / 2)
                    .animation(.interactiveSpring())
                    if canEdit {
                        HStack(spacing: 8) {
                            Button {
                                withAnimation(.interactiveSpring()) {
                                    database.addSet(to: setGroup)
                                }
                            } label: {
                                Label(
                                    NSLocalizedString("addSet", comment: ""),
                                    systemImage: "plus.circle.fill"
                                )
                                .foregroundStyle((setGroup.exercise?.muscleGroup?.color ?? .accentColor).gradient)
                                .font(.system(.body, design: .rounded, weight: .bold))
                                .padding(.vertical, 15)
                                .frame(maxWidth: .infinity)
                                .background(Color.accentColor.secondaryTranslucentBackground)
                                .clipShape(Capsule())
                            }
                            Button {
                                withAnimation(.interactiveSpring()) {
                                    database.duplicateLastSet(from: setGroup)
                                }
                            } label: {
                                Image(systemName: "plus.square.on.square")
                                    .foregroundStyle((setGroup.exercise?.muscleGroup?.color ?? .accentColor).gradient)
                                    .font(.system(.body, design: .rounded, weight: .bold))
                                    .padding(15)
                                    .background(Color.accentColor.secondaryTranslucentBackground)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, CELL_PADDING)
                    }
                }
            }
        }
        .sheet(isPresented: $isSelectingPrimaryExercise) {
            NavigationStack {
                ExerciseSelectionScreen(
                    selectedExercise: setGroup.exercise,
                    setExercise: {
                        setGroup.exercise = $0
                        isSelectingPrimaryExercise = false
                    },
                    forSecondary: false,
                    presentationDetentSelection: .constant(.large)
                )
                .presentationDetents([.large], selection: .constant(.large))
                .navigationTitle(NSLocalizedString("replaceExercise", comment: ""))
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(NSLocalizedString("cancel", comment: "")) {
                            isSelectingPrimaryExercise = false
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isSelectingSecondaryExercise) {
            NavigationStack {
                ExerciseSelectionScreen(
                    selectedExercise: setGroup.secondaryExercise,
                    setExercise: {
                        setGroup.secondaryExercise = $0
                        isSelectingSecondaryExercise = false
                    },
                    forSecondary: true,
                    presentationDetentSelection: .constant(.large)
                )
                .presentationDetents([.large], selection: .constant(.large))
                .navigationTitle(NSLocalizedString("selectSecondaryExercise", comment: ""))
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(NSLocalizedString("cancel", comment: "")) {
                            if setGroup.secondaryExercise == nil {
                                database.convertSetGroupToStandardSets(setGroup)
                            }
                            isSelectingSecondaryExercise = false
                        }
                    }
                }
            }
        }
        .accentColor(setGroup.exercise?.muscleGroup?.color ?? .accentColor)
        .padding(.bottom, canEdit || isReordering ? CELL_PADDING : CELL_PADDING / 2)
        .tileStyle()
    }

    // MARK: - Supporting Views

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                if let indexInWorkout = setGroup.workout?.setGroups.firstIndex(of: setGroup) {
                    Text("\(indexInWorkout + 1)")
                        .font(.title)
                        .fontWeight(.medium)
                        .fontDesign(.rounded)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 0) {
                    ExerciseHeader(
                        exercise: setGroup.exercise,
                        secondaryExercise: setGroup.secondaryExercise,
                        noExerciseAction: {
                            isSelectingPrimaryExercise = true
                        },
                        noSecondaryExerciseAction: {
                            isSelectingSecondaryExercise = true
                        },
                        isSuperSet: setGroup.setType == .superSet,
                        navigationToDetailEnabled: true,
                        shouldShowExerciseDetailInSheet: shouldShowExerciseDetailInSheet
                    )
                    HStack {
                        Text(setGroup.exercise?.muscleGroup?.description ?? "")
                            .foregroundColor(setGroup.exercise?.muscleGroup?.color ?? .accentColor)
                        if setGroup.setType == .superSet {
                            Text(setGroup.secondaryExercise?.muscleGroup?.description ?? "")
                                .foregroundColor(setGroup.secondaryExercise?.muscleGroup?.color ?? .accentColor)
                        }
                        Spacer()
                        if !isReordering, let supplementaryText = supplementaryText {
                            Text(supplementaryText)
                                .foregroundStyle(.secondary)
                                .fontWeight(.medium)
                        }
                    }
                    .font(.system(.footnote, design: .rounded, weight: .bold))
                }
                Spacer()
                if canEdit && !isReordering {
                    menu
                }
                if isReordering {
                    Image(systemName: "line.3.horizontal")
                        .fontWeight(.regular)
                        .foregroundStyle(.secondary)
                }
            }
            if isEditingNote || !(setGroup.note?.isEmpty ?? true) {
                TextField("Note", text: Binding(get: { setGroup.note ?? "" }, set: { setGroup.note = $0 }), prompt: Text(NSLocalizedString("addNote...", comment: "")), axis: .vertical)
                    .focused($isNoteFieldFocused)
                    .onSubmit(of: .text) {
                        setGroup.note = (setGroup.note ?? "") + "\n"
                        isNoteFieldFocused = true
                    }
                    .lineLimit(1...5)
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .onChange(of: isNoteFieldFocused) {
            if !isNoteFieldFocused {
                isEditingNote = false
            }
        }
    }

    // MARK: - Supporting Views

    private var menu: some View {
        Menu {
            Section {
                Button(
                    role: .destructive,
                    action: {
                        withAnimation {
                            database.delete(setGroup)
                        }
                    }
                ) {
                    Label(NSLocalizedString("remove", comment: ""), systemImage: "xmark.circle")
                }
                Button {
                    isSelectingPrimaryExercise = true
                } label: {
                    Label(
                        NSLocalizedString("replaceExercise", comment: ""),
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                }
                if setGroup.setType == .superSet {
                    Button {
                        isSelectingSecondaryExercise = true
                    } label: {
                        Label(
                            NSLocalizedString("replaceSecondaryExercise", comment: ""),
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                }
                Button {
                    isReordering.toggle()
                } label: {
                    Label(
                        NSLocalizedString(
                            isReordering ? "reorderingDone" : "reorderExercises",
                            comment: ""
                        ),
                        systemImage: "arrow.up.arrow.down"
                    )
                }
            }
            Section {
                Button {
                    isEditingNote = true
                    isNoteFieldFocused = true
                } label: {
                    Label((setGroup.note?.isEmpty ?? true) ? NSLocalizedString("addNote", comment: "") : NSLocalizedString("editNote", comment: ""), systemImage: "square.and.pencil")
                }
            }
            Section {
                Button {
                    database.convertSetGroupToStandardSets(setGroup)
                } label: {
                    HStack {
                        Text(NSLocalizedString("standard", comment: ""))
                        if setGroup.setType == .standard {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                Button {
                    database.convertSetGroupToSuperSets(setGroup)
                    isSelectingSecondaryExercise = true
                } label: {
                    HStack {
                        Text(NSLocalizedString("superSet", comment: ""))
                        if setGroup.setType == .superSet {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                Button {
                    database.convertSetGroupToDropSets(setGroup)
                } label: {
                    HStack {
                        Text(NSLocalizedString("dropSet", comment: ""))
                        if setGroup.setType == .dropSet {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            } header: {
                Text(NSLocalizedString("setType", comment: ""))
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle((setGroup.exercise?.muscleGroup?.color ?? .accentColor).gradient)
                .padding(.horizontal, 3)
                .padding(.vertical, 10)
                .background(
                    Circle()
                        .fill((setGroup.exercise?.muscleGroup?.color ?? .accentColor).secondaryTranslucentBackground)
                )
        }
    }
}

private struct PreviewWrapperView: View {
    var body: some View {
        FetchRequestWrapper(
            Workout.self,
            sortDescriptors: [SortDescriptor(\.date, order: .reverse)]
        ) { workouts in
            NavigationStack {
                ScrollView {
                    VStack {
                        WorkoutSetGroupCell(
                            setGroup: workouts.first!.setGroups.first!,
                            focusedIntegerFieldIndex: .constant(nil),
                            isReordering: .constant(false),
                            supplementaryText: ""
                        )
                        .padding()
                        WorkoutSetGroupCell(
                            setGroup: workouts.first!.setGroups.first!,
                            focusedIntegerFieldIndex: .constant(nil),
                            isReordering: .constant(true),
                            supplementaryText: nil
                        )
                        .padding()
                        WorkoutSetGroupCell(
                            setGroup: workouts.first!.setGroups.first!,
                            focusedIntegerFieldIndex: .constant(nil),
                            isReordering: .constant(false),
                            supplementaryText: "Saturday Night Workout"
                        )
                        .padding()
                        .canEdit(false)
                    }
                }
            }
        }
    }
}

struct WorkoutSetGroupCell_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
    }
}
