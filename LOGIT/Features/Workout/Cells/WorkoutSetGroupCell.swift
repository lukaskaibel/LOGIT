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
    var showDetailAsSheet: Bool = false
    var showPendingRestInTertiary: Bool = false
    var onTapRestDuration: ((WorkoutSet) -> Void)? = nil
    var onReorderSetGroups: (() -> Void)? = nil
    var onTapPreviousSet: ((Exercise) -> Void)? = nil
    var onTapExerciseName: ((Exercise) -> Void)? = nil

    // MARK: - State

    private enum BadgeDisplayMode {
        case volume, currentBest, allTime
    }

    @State private var badgeDisplayMode: BadgeDisplayMode = .volume
    @State private var isHeaderExpanded = false
    @State private var isSelectingPrimaryExercise = false
    @State private var primaryExerciseSelectionSheetDetend: PresentationDetent? = .large
    @State private var isSelectingSecondaryExercise = false
    @State private var isEditingNote = false
    @FocusState private var isNoteFieldFocused: Bool

    // MARK: - Body

    var body: some View {
        Group {
            if shouldShowPreviousSetReferences {
                FetchRequestWrapper(
                    WorkoutSetGroup.self,
                    sortDescriptors: [SortDescriptor(\.workout?.date, order: .reverse)],
                    predicate: WorkoutSetGroupPredicateFactory.getWorkoutSetGroups(
                        withExercise: setGroup.exercise
                    )
                ) { previousSetGroups in
                    content(previousSetGroup: previousSetGroup(from: previousSetGroups))
                }
            } else {
                content(previousSetGroup: nil)
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
                    currentWorkoutExercises: setGroup.workout?.exercises ?? [],
                    supersetPrimaryExercise: nil,
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
                    currentWorkoutExercises: setGroup.workout?.exercises ?? [],
                    supersetPrimaryExercise: setGroup.exercise,
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
        .background(
            RoundedRectangle(cornerRadius: 30)
                .fill(.shadow(.inner(color: .white.opacity(0.04), radius: 3)))
                .foregroundStyle(Color.secondaryBackground)
        )
        .cornerRadius(30)
    }

    private func content(previousSetGroup: WorkoutSetGroup?) -> some View {
        VStack(spacing: CELL_PADDING) {
            header
                .padding([.top, .horizontal], CELL_PADDING)

            if !isReordering {
                VStack(spacing: CELL_PADDING) {
                    VStack(spacing: CELL_SPACING) {
                        ReorderableForEach(
                            $setGroup.sets,
                            canReorder: false,
                            isReordering: .constant(false)
                        ) { workoutSet in
                            VStack(spacing: CELL_SPACING) {
                                WorkoutSetCell(
                                    workoutSet: workoutSet,
                                    focusedIntegerFieldIndex: $focusedIntegerFieldIndex,
                                    referenceSet: referenceSet(
                                        for: workoutSet,
                                        in: previousSetGroup
                                    ),
                                    onEditRestDuration: onTapRestDuration.map { callback in
                                        { callback(workoutSet) }
                                    },
                                    onTapPreviousSet: onTapPreviousSet
                                )
                                .contentShape(Rectangle())
                                .background(
                                    RoundedRectangle(cornerRadius: 15)
                                        .fill(.shadow(.inner(color: .black.opacity(0.4), radius: 5)))
                                        .foregroundStyle(Color.tertiaryBackground)
                                )
                                .cornerRadius(15)
                                .onDeleteView(disabled: !canEdit) {
                                    withAnimation(.interactiveSpring()) {
                                        database.delete(workoutSet)
                                    }
                                }
                                if !isLastSet(workoutSet) {
                                    if canEdit {
                                        RestTimerBetweenSetsView(
                                            workoutSet: workoutSet,
                                            showPendingRestInTertiary: showPendingRestInTertiary,
                                            onTapRestDuration: onTapRestDuration.map { callback in
                                                { callback(workoutSet) }
                                            }
                                        )
                                    } else if workoutSet.restDurationSeconds > 0 {
                                        RestDurationLabel(seconds: workoutSet.restDurationSeconds)
                                            .padding(.vertical, 2)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, CELL_PADDING / 2)
                    .animation(.interactiveSpring())
                    if canEdit {
                        HStack(spacing: 8) {
                            Button {
                                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
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
                            .contextMenu {
                                Button {
                                    withAnimation(.interactiveSpring()) {
                                        database.duplicateLastWeight(from: setGroup)
                                    }
                                } label: {
                                    Label(NSLocalizedString("copyWeight", comment: ""), systemImage: "scalemass")
                                }
                                Button {
                                    withAnimation(.interactiveSpring()) {
                                        database.duplicateLastRepetitions(from: setGroup)
                                    }
                                } label: {
                                    Label(NSLocalizedString("copyRepetitions", comment: ""), systemImage: "repeat.circle")
                                }
                                Button {
                                    withAnimation(.interactiveSpring()) {
                                        database.duplicateLastSet(from: setGroup)
                                    }
                                } label: {
                                    Label(NSLocalizedString("copySet", comment: ""), systemImage: "plus.square.on.square")
                                }
                            }
                            Button {
                                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
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
                            menu
                        }
                        .padding(.horizontal, CELL_PADDING)
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if !isReordering {
                VStack(spacing: 2) {
                    Text(badgeLabel)
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                    UnitView(
                        value: badgeValue,
                        unit: badgeUnit,
                        configuration: .small
                    )
                }
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.2), value: badgeDisplayMode)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 30 - CELL_PADDING / 2)
                        .fill(.shadow(.inner(color: .black.opacity(0.4), radius: 5)))
                        .foregroundStyle(Color.tertiaryBackground)
                )
                .cornerRadius(30 - CELL_PADDING / 2)
                .padding(.top, CELL_PADDING / 2)
                .padding(.trailing, CELL_PADDING / 2)
                .onTapGesture {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        cycleBadgeMode()
                    }
                }
            }
        }
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
                        showDetailAsSheet: showDetailAsSheet,
                        onTapExerciseName: onTapExerciseName
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
                        withAnimation(.interactiveSpring()) {
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
            if let onReorderSetGroups {
                Section {
                    Button {
                        onReorderSetGroups()
                    } label: {
                        Label(
                            NSLocalizedString("reorderExercises", comment: ""),
                            systemImage: "arrow.up.arrow.down"
                        )
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle((setGroup.exercise?.muscleGroup?.color ?? .accentColor).gradient)
                .font(.system(.body, design: .rounded, weight: .bold))
                .frame(width: 20, height: 20)
                .padding(15)
                .background(Color.accentColor.secondaryTranslucentBackground)
                .clipShape(Circle())
        }
    }

    // MARK: - Badge Display

    private var badgeLabel: String {
        switch badgeDisplayMode {
        case .volume: return NSLocalizedString("volume", comment: "")
        case .currentBest: return NSLocalizedString("currentBest", comment: "")
        case .allTime: return NSLocalizedString("allTime", comment: "")
        }
    }

    private var badgeValue: String {
        switch badgeDisplayMode {
        case .volume:
            return formatWeightForDisplay(getVolume(of: setGroup.sets))
        case .currentBest:
            if let weight = lastMonthBestWeight {
                return formatWeightForDisplay(weight)
            } else if let reps = lastMonthBestReps {
                return String(reps)
            }
            return "0"
        case .allTime:
            if let weight = allTimeBestWeight {
                return formatWeightForDisplay(weight)
            } else if let reps = allTimeBestReps {
                return String(reps)
            }
            return "0"
        }
    }

    private var badgeUnit: String {
        switch badgeDisplayMode {
        case .volume:
            return WeightUnit.used.rawValue
        case .currentBest:
            return lastMonthBestWeight != nil ? WeightUnit.used.rawValue : NSLocalizedString("reps", comment: "")
        case .allTime:
            return allTimeBestWeight != nil ? WeightUnit.used.rawValue : NSLocalizedString("reps", comment: "")
        }
    }

    private var lastMonthBestWeight: Int? {
        guard let exercise = setGroup.exercise else { return nil }
        let oneMonthAgo = Calendar.current.date(byAdding: .month, value: -1, to: .now)!
        let sets = exercise.sets.filter { ($0.workout?.date ?? .distantPast) >= oneMonthAgo }
        let best = sets.map { $0.maximum(.weight, for: exercise) }.max()
        return best != nil && best! > 0 ? best : nil
    }

    private var lastMonthBestReps: Int? {
        guard let exercise = setGroup.exercise else { return nil }
        let oneMonthAgo = Calendar.current.date(byAdding: .month, value: -1, to: .now)!
        let sets = exercise.sets.filter { ($0.workout?.date ?? .distantPast) >= oneMonthAgo }
        let best = sets.map { $0.maximum(.repetitions, for: exercise) }.max()
        return best != nil && best! > 0 ? best : nil
    }

    private var allTimeBestWeight: Int? {
        guard let exercise = setGroup.exercise else { return nil }
        let best = exercise.sets.map { $0.maximum(.weight, for: exercise) }.max()
        return best != nil && best! > 0 ? best : nil
    }

    private var allTimeBestReps: Int? {
        guard let exercise = setGroup.exercise else { return nil }
        let best = exercise.sets.map { $0.maximum(.repetitions, for: exercise) }.max()
        return best != nil && best! > 0 ? best : nil
    }

    private func cycleBadgeMode() {
        let modes: [BadgeDisplayMode] = [.volume, .currentBest, .allTime]
        guard let currentIndex = modes.firstIndex(of: badgeDisplayMode) else {
            badgeDisplayMode = .volume
            return
        }
        for i in 1..<modes.count {
            let nextMode = modes[(currentIndex + i) % modes.count]
            switch nextMode {
            case .volume:
                badgeDisplayMode = .volume
                return
            case .currentBest:
                if lastMonthBestWeight != nil || lastMonthBestReps != nil {
                    badgeDisplayMode = .currentBest
                    return
                }
            case .allTime:
                if allTimeBestWeight != nil || allTimeBestReps != nil {
                    badgeDisplayMode = .allTime
                    return
                }
            }
        }
        badgeDisplayMode = .volume
    }

    // MARK: - Supporting Methods

    private func isLastSet(_ workoutSet: WorkoutSet) -> Bool {
        setGroup.sets.last == workoutSet
    }

    private var shouldShowPreviousSetReferences: Bool {
        setGroup.workout?.isCurrentWorkout == true && setGroup.exercise != nil
    }

    private func previousSetGroup(from previousSetGroups: [WorkoutSetGroup]) -> WorkoutSetGroup? {
        // The reference must match the current set group's type *and* its exercise
        // composition. Otherwise the per-cell `as? SuperSet` / `as? DropSet` cast (or
        // the superset's per-exercise match) silently fails when the same exercise was
        // most recently logged as a different set type or in a different pairing.
        let targetExerciseIDs = exerciseIDs(in: setGroup)
        return previousSetGroups.first { previousSetGroup in
            previousSetGroup != setGroup
                && previousSetGroup.setType == setGroup.setType
                && exerciseIDs(in: previousSetGroup) == targetExerciseIDs
                && previousSetGroup.sets.contains { $0.hasEntry }
        }
    }

    private func exerciseIDs(in setGroup: WorkoutSetGroup) -> Set<UUID> {
        var ids = Set<UUID>()
        if let id = setGroup.exercise?.id { ids.insert(id) }
        if let id = setGroup.secondaryExercise?.id { ids.insert(id) }
        return ids
    }

    private func referenceSet(
        for workoutSet: WorkoutSet,
        in previousSetGroup: WorkoutSetGroup?
    ) -> WorkoutSet? {
        guard
            let index = setGroup.sets.firstIndex(of: workoutSet),
            let previousSetGroup
        else { return nil }

        return previousSetGroup.sets.value(at: index)
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
