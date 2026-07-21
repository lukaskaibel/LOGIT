//
//  WorkoutSetGroupCell.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 28.07.23.
//

import Charts
import Combine
import CoreData
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
    /// Whether any set field is currently focused, passed as a plain value (instead of reading
    /// `focusedIntegerFieldIndex` here) so this cell's body doesn't re-run for every focus move
    /// between fields — only for the keyboard appearing or disappearing.
    var isFieldFocused: Bool = false
    /// Position of this group in the workout, passed by `WorkoutSetGroupList` so it is part of
    /// this cell's `Equatable` inputs: with body skipping, deleting or reordering *another*
    /// group must still refresh this cell's header number. Nil when the cell is used standalone
    /// (previews), where the position is derived from the workout instead.
    var indexInWorkout: Int? = nil
    /// Flat index of this group's first set within the whole workout. Not rendered, but part of
    /// `==`: the set cells derive their keyboard-focus indices from flat set positions, so a
    /// structural change in an earlier group has to re-render this cell's children too.
    var firstSetIndexInWorkout: Int = 0
    var onTapRestDuration: ((WorkoutSet) -> Void)? = nil
    var onReorderSetGroups: (() -> Void)? = nil
    var onTapPreviousSet: ((Exercise) -> Void)? = nil
    var onTapExerciseName: ((Exercise) -> Void)? = nil
    var onTapMetricBadge: ((WorkoutSetGroup, CGRect) -> Void)? = nil

    // MARK: - State

    @State private var isHeaderExpanded = false
    @State private var isSelectingPrimaryExercise = false
    @State private var primaryExerciseSelectionSheetDetend: PresentationDetent? = .large
    @State private var isSelectingSecondaryExercise = false
    @State private var isEditingNote = false
    /// Live width of the metric badge (an overlay with no layout footprint), measured so the exercise
    /// name can reserve room and dissolve before it instead of sliding underneath the capsule.
    @State private var metricBadgeWidth: CGFloat = 0
    /// Width of the exercise-name column (the name + muscle-group VStack). Measured so the name's
    /// width budget can be derived as (column − badge reservation) and handed to `ExerciseHeader`.
    @State private var nameSlotWidth: CGFloat = 0
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
                    .animation(.interactiveSpring(), value: setGroup.sets)
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
            if !isReordering, let workout = setGroup.workout {
                MetricBadgeView(
                    setGroup: setGroup,
                    workout: workout,
                    isEditing: isFieldFocused,
                    onTapBadge: onTapMetricBadge
                )
                // The badge floats here without claiming layout space; feed its width back so the
                // exercise name can reserve room and fade out before it (see `exerciseNameTrailingInset`).
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { _, newWidth in
                    metricBadgeWidth = newWidth
                }
            }
        }
    }

    // MARK: - Supporting Views

    /// Trailing space the metric badge occupies, reserved on the exercise name's side so a long name
    /// fades out *before* the badge instead of sliding under it. The badge is an overlay measuring to
    /// the cell's true trailing edge while the header is inset by `CELL_PADDING`, so subtract that;
    /// `+ 8` leaves a small gap between the name's fade and the badge. Zero whenever no badge is shown
    /// (while reordering, or before there's anything to compare) so the name reclaims the full width.
    private var exerciseNameTrailingInset: CGFloat {
        guard !isReordering, setGroup.workout != nil else { return 0 }
        return max(0, metricBadgeWidth - CELL_PADDING + 8)
    }

    /// Width budget for the exercise-name label (name + chevron) when a badge is present: the measured
    /// column width minus the badge reservation. Passed to `ExerciseHeader.nameMaxWidth`, which fades
    /// the name within it while leaving the chevron opaque. `nil` (no badge yet, or the column not
    /// measured) leaves the name at its natural width with no fade — there's nothing to dissolve before.
    private var exerciseNameWidth: CGFloat? {
        let inset = exerciseNameTrailingInset
        guard inset > 0, nameSlotWidth > 0 else { return nil }
        return max(40, nameSlotWidth - inset)
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                if let indexInWorkout = indexInWorkout ?? setGroup.workout?.setGroups.firstIndex(of: setGroup) {
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
                        onTapExerciseName: onTapExerciseName,
                        nameMaxWidth: exerciseNameWidth
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
                // Width of the name column, fed to `exerciseNameWidth` so the name fills exactly to
                // its fade. The muscle row's trailing `Spacer` holds this at the full available width
                // regardless of the name's own (narrower) frame, so reading it back can't feed back.
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { _, newWidth in
                    nameSlotWidth = newWidth
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
            // Per-group measurement override on top of the exercise default. Hidden for super
            // sets: their two exercises each bring their own measurement type.
            if setGroup.setType != .superSet {
                Section {
                    ForEach(SetMeasurementType.allCases) { type in
                        Button {
                            setGroup.overrideMeasurementType(type)
                        } label: {
                            HStack {
                                Text(type.title)
                                if setGroup.measurementType == type {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } header: {
                    Text(NSLocalizedString("measurementType", comment: ""))
                }
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

/// Lets SwiftUI skip this cell's body when a parent re-render didn't change what it draws. The
/// recorder screen re-renders for reasons that don't concern individual cells (focus moves
/// between fields, timer state, progress), and without this every such pass re-ran every cell.
/// The comparison deliberately ignores the callback closures (their behavior is stable across
/// renders) and the bindings (views reading a binding's value re-render on its changes on their
/// own). Set-level edits still re-render instantly through the cell's `@ObservedObject setGroup`
/// and the set cells' own observed sets, which bypass this check entirely.
extension WorkoutSetGroupCell: Equatable {
    static func == (lhs: WorkoutSetGroupCell, rhs: WorkoutSetGroupCell) -> Bool {
        lhs.setGroup === rhs.setGroup
            && lhs.supplementaryText == rhs.supplementaryText
            && lhs.showDetailAsSheet == rhs.showDetailAsSheet
            && lhs.showPendingRestInTertiary == rhs.showPendingRestInTertiary
            && lhs.isFieldFocused == rhs.isFieldFocused
            && lhs.indexInWorkout == rhs.indexInWorkout
            && lhs.firstSetIndexInWorkout == rhs.firstSetIndexInWorkout
    }
}

// MARK: - Session vs current best

/// Cache for the history-derived side of `SetGroupMetricComparison` (`previousAllTimeBest` and
/// `currentBest`). Both scan the exercise's entire set history — hundreds of sets for a trained
/// exercise — and the badge consults them several times per render, which made every full
/// recorder re-render pay dozens of history scans (the dominant main-thread cost while typing,
/// focusing fields, or running the rest timer). During a session that history is static: both
/// values exclude the workout being recorded. So the scans are cached here and recomputed only
/// when something *outside* the current workout changes — a CloudKit import, deleting or editing
/// an old workout, or an exercise change.
private final class ExerciseHistoryBestsCache: @unchecked Sendable {
    static let shared = ExerciseHistoryBestsCache()

    enum Kind: Hashable {
        case allTimeBest
        case currentBest
    }

    private struct Key: Hashable {
        let kind: Kind
        let exercise: NSManagedObjectID
        let metric: ExercisePrimaryMetric
        let excludedWorkout: NSManagedObjectID?
        let anchor: Date?
    }

    private let lock = NSLock()
    private var values: [Key: Int?] = [:]

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contextObjectsDidChange),
            name: .NSManagedObjectContextObjectsDidChange,
            object: nil
        )
    }

    func value(
        _ kind: Kind,
        exercise: Exercise,
        metric: ExercisePrimaryMetric,
        excludedWorkout: Workout?,
        anchor: Date?,
        compute: () -> Int?
    ) -> Int? {
        let key = Key(
            kind: kind,
            exercise: exercise.objectID,
            metric: metric,
            excludedWorkout: excludedWorkout?.objectID,
            anchor: anchor
        )
        lock.lock()
        if let cached = values[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let computed = compute()
        lock.lock()
        values[key] = computed
        lock.unlock()
        return computed
    }

    private func invalidateAll() {
        lock.lock()
        values.removeAll()
        lock.unlock()
    }

    /// The context-change notification arrives on the posting context's queue. Background
    /// contexts (CloudKit imports) always concern history, so they invalidate wholesale.
    /// Main-context changes are inspected on their own (main) queue: edits confined to the
    /// workout currently being recorded (typing a set value, adding a set) don't touch prior
    /// history and keep the cache.
    @objc private func contextObjectsDidChange(_ notification: Notification) {
        guard Thread.isMainThread else {
            invalidateAll()
            return
        }
        lock.lock()
        let isEmpty = values.isEmpty
        lock.unlock()
        guard !isEmpty else { return }

        let changeKeys = [
            NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey, NSRefreshedObjectsKey,
        ]
        for changeKey in changeKeys {
            guard let objects = notification.userInfo?[changeKey] as? Set<NSManagedObject> else {
                continue
            }
            for object in objects {
                let workout: Workout?
                switch object {
                case let workoutSet as WorkoutSet:
                    workout = workoutSet.setGroup?.workout
                case let setGroup as WorkoutSetGroup:
                    workout = setGroup.workout
                case let changedWorkout as Workout:
                    workout = changedWorkout
                case is Exercise:
                    invalidateAll()
                    return
                default:
                    continue
                }
                // Anything not clearly confined to the in-progress workout — including
                // deletions, whose relationships are already severed — invalidates.
                guard let workout, !workout.isDeleted, workout.isCurrentWorkout else {
                    invalidateAll()
                    return
                }
            }
        }
    }
}

/// The numbers behind the metric badge and its info panel: what this set group achieved per metric,
/// the exercise's current best it's measured against, and the percent between them. One shared home
/// so the badge's pill and the panel's spelled-out values can never tell different stories.
private struct SetGroupMetricComparison {
    let setGroup: WorkoutSetGroup

    /// This set group's best for `metric` — what the *session* achieved.
    func sessionBest(_ metric: ExercisePrimaryMetric) -> Int {
        guard let exercise = setGroup.exercise else { return 0 }
        switch metric {
        case .estimatedOneRepMax: return setGroup.sets.map { $0.estimatedOneRepMax(for: exercise) }.max() ?? 0
        case .weight: return setGroup.sets.map { $0.maximum(.weight, for: exercise) }.max() ?? 0
        case .repetitions: return setGroup.sets.map { $0.maximum(.repetitions, for: exercise) }.max() ?? 0
        case .duration: return setGroup.sets.map { $0.maximum(.duration, for: exercise) }.max() ?? 0
        case .distance: return setGroup.sets.map { $0.maximum(.distance, for: exercise) }.max() ?? 0
        }
    }

    /// The comparison bar: the exercise's current best (see `Exercise.currentBestWindowStart`) —
    /// the same recent peak the exercise tiles show — but *excluding* the current workout. The
    /// exclusion matters: `currentBestSet` includes the workout being recorded, so today's new best
    /// would clamp the comparison to 0% the moment it's set. A stable monthly bar, deliberately not
    /// the previous session (a deload last time would fake a huge gain).
    ///
    /// On a *finished* workout the window and fallback are anchored at the workout's date, so the
    /// comparison keeps telling that day's story even after later sessions surpass it. While
    /// recording, the window stays anchored at now — the two coincide there anyway.
    func currentBest(_ metric: ExercisePrimaryMetric) -> Int? {
        guard let exercise = setGroup.exercise else { return nil }
        let anchor = setGroup.workout?.isCurrentWorkout == true ? nil : setGroup.workout?.date
        return ExerciseHistoryBestsCache.shared.value(
            .currentBest,
            exercise: exercise,
            metric: metric,
            excludedWorkout: setGroup.workout,
            anchor: anchor
        ) {
            currentBestImpl(metric)
        }
    }

    private func currentBestImpl(_ metric: ExercisePrimaryMetric) -> Int? {
        guard let exercise = setGroup.exercise else { return nil }
        let anchor = setGroup.workout?.isCurrentWorkout == true ? nil : setGroup.workout?.date
        var priorSets = exercise.sets.filter { $0.workout != setGroup.workout }
        if let anchor {
            priorSets = priorSets.filter { ($0.workout?.date ?? .distantFuture) < anchor }
        }
        if let best = exercise.currentBestSet(for: metric, in: priorSets, endingAt: anchor) {
            switch metric {
            case .estimatedOneRepMax: return best.estimatedOneRepMax(for: exercise)
            case .weight: return best.maximum(.weight, for: exercise)
            case .repetitions: return best.maximum(.repetitions, for: exercise)
            case .duration: return best.maximum(.duration, for: exercise)
            case .distance: return best.maximum(.distance, for: exercise)
            }
        }
        // Untrained for over a month → the window is empty. Fall back to the all-time best so there
        // is still a bar to compare against, instead of a flat 0% whatever the entered value is
        // (the trophy fires against all-time anyway, so the two stay consistent).
        func value(_ workoutSet: WorkoutSet) -> Int {
            switch metric {
            case .estimatedOneRepMax: return workoutSet.estimatedOneRepMax(for: exercise)
            case .weight: return workoutSet.maximum(.weight, for: exercise)
            case .repetitions: return workoutSet.maximum(.repetitions, for: exercise)
            case .duration: return workoutSet.maximum(.duration, for: exercise)
            case .distance: return workoutSet.maximum(.distance, for: exercise)
            }
        }
        let allTimeBest = priorSets.map(value).max() ?? 0
        return allTimeBest > 0 ? allTimeBest : nil
    }

    /// Percent change of this set group's best over the exercise's current best for `metric`, or
    /// nil when either side has nothing to compare — before the session's first entry, or with no
    /// prior history at all.
    func percentChange(_ metric: ExercisePrimaryMetric) -> Double? {
        let current = sessionBest(metric)
        guard current > 0, let baseline = currentBest(metric), baseline > 0 else { return nil }
        return (Double(current) - Double(baseline)) / Double(baseline) * 100
    }

    /// Best value for `metric` across all *previous* sessions for this exercise — the bar a new
    /// record has to clear (all-time, intentionally NOT the current-best window). Excludes the
    /// current workout.
    func previousAllTimeBest(_ metric: ExercisePrimaryMetric) -> Int {
        guard let exercise = setGroup.exercise else { return 0 }
        return ExerciseHistoryBestsCache.shared.value(
            .allTimeBest,
            exercise: exercise,
            metric: metric,
            excludedWorkout: setGroup.workout,
            anchor: nil
        ) {
            previousAllTimeBestImpl(metric)
        } ?? 0
    }

    private func previousAllTimeBestImpl(_ metric: ExercisePrimaryMetric) -> Int {
        guard let exercise = setGroup.exercise else { return 0 }
        let priorSets = exercise.sets.filter { $0.workout != setGroup.workout }
        switch metric {
        case .estimatedOneRepMax: return priorSets.map { $0.estimatedOneRepMax(for: exercise) }.max() ?? 0
        case .weight: return priorSets.map { $0.maximum(.weight, for: exercise) }.max() ?? 0
        case .repetitions: return priorSets.map { $0.maximum(.repetitions, for: exercise) }.max() ?? 0
        case .duration: return priorSets.map { $0.maximum(.duration, for: exercise) }.max() ?? 0
        case .distance: return priorSets.map { $0.maximum(.distance, for: exercise) }.max() ?? 0
        }
    }

    /// True only while recording, when this set group beats every previous session on `metric`.
    /// Ties don't count — you have to exceed it. Neither do first-ever entries — with no earlier
    /// value there is no record to beat (and everything would be a PR on day one).
    func isPersonalRecord(_ metric: ExercisePrimaryMetric) -> Bool {
        guard setGroup.workout?.isCurrentWorkout == true else { return false }
        let current = sessionBest(metric)
        let priorBest = previousAllTimeBest(metric)
        return current > 0 && priorBest > 0 && current > priorBest
    }
}

/// The progress-metric badge shown on each set group, styled like the trend pill on the exercise
/// chart screens: how this session's best compares to the exercise's current best (last month,
/// excluding this workout) — the percent change with an up/down arrow, or a dash at 0% — with the
/// chosen metric's name in fine print
/// beneath it. The metric is switched from the info panel a tap opens (also where it's explained); the badge
/// itself has no switching gesture. While the displayed metric stands at a personal record, the
/// percentage gives way to a trophy and the record value; a record on a metric *other* than the
/// displayed one is "peeked" — rolled in for a few seconds, trophy and all — before rolling back,
/// so a win is never hidden.
///
/// It owns its own info popover so the popover is presented from this view's context, not the
/// cell's — otherwise it shares a presentation host with the cell's exercise-selection sheets and
/// they dismiss each other (UIKit only presents one thing per view controller at a time).
private struct MetricBadgeView: View {
    @ObservedObject var setGroup: WorkoutSetGroup
    /// Observed so the badge re-renders on every recorder change. Editing a set mutates the set —
    /// and, via the recorder's autosave, the workout — but NOT this set group, so without observing
    /// the workout the badge would never re-evaluate while the user types, and live values plus PR
    /// peeks would stall. This mirrors how `WorkoutSetGroupList` already observes the workout.
    @ObservedObject var workout: Workout
    /// True while any set field is being edited (keyboard up). Focusing a field scrolls it above the
    /// keyboard, which often pushes this badge out of view — so peeks found mid-edit are deferred
    /// until editing ends and the badge is back on screen.
    let isEditing: Bool
    /// Set by the workout recorder. There the badge sits behind a persistent sheet, so presenting its
    /// own popover/sheet would tear that sheet down — instead the tap is routed up and the recorder
    /// presents the panel from the sheet's own context. Nil elsewhere, where the popover is fine.
    /// A plain parameter (not an environment value) so the recorder's per-render closure can't
    /// register every badge as environment-dependent on it.
    let onTapBadge: ((WorkoutSetGroup, CGRect) -> Void)?
    @StateObject private var peek = MetricPeekController()

    @State private var primaryMetric: ExercisePrimaryMetric = .estimatedOneRepMax
    @State private var isShowingInfo = false
    /// Exercise-detail sheet presented when the popover's value/chart row is tapped (non-recorder
    /// contexts — the recorder routes this through its own sheet instead).
    @State private var detailExercise: Exercise?
    @State private var detailMetric: ExercisePrimaryMetric = .estimatedOneRepMax
    /// The badge's frame in global (window) coordinates, captured so the recorder can anchor its
    /// popover at the badge. Pure layout observation — nothing extra in the badge's render path.
    @State private var badgeFrame: CGRect = .zero

    /// The metric on screen — a peeked record while one plays, otherwise the chosen metric.
    private var displayedMetric: ExercisePrimaryMetric { peek.activeMetric ?? primaryMetric }

    /// Session-vs-current-best math, shared with `MetricInfoPanel` so badge and panel always agree.
    private var comparison: SetGroupMetricComparison { SetGroupMetricComparison(setGroup: setGroup) }

    private var displayedIsRecord: Bool { comparison.isPersonalRecord(displayedMetric) }

    init(
        setGroup: WorkoutSetGroup,
        workout: Workout,
        isEditing: Bool,
        onTapBadge: ((WorkoutSetGroup, CGRect) -> Void)? = nil
    ) {
        _setGroup = ObservedObject(wrappedValue: setGroup)
        _workout = ObservedObject(wrappedValue: workout)
        self.isEditing = isEditing
        self.onTapBadge = onTapBadge
        // Resolve the committed metric up front so the very first render already evaluates the right
        // metric: the idle/empty decision below shouldn't wait on `onAppear`, and it spares a
        // first-frame roll up from the `.estimatedOneRepMax` default.
        _primaryMetric = State(initialValue: setGroup.exercise?.primaryMetric ?? .defaultMetric)
    }

    var body: some View {
        let accent = setGroup.exercise?.muscleGroup?.color ?? .accentColor
        let displayed = displayedMetric
        let sessionBest = comparison.sessionBest(displayed)
        // Before this session's first entry there's nothing to trend, so rather than a dead "0 %"
        // the badge previews the bar this metric is scored against: the exercise's current best
        // (`idleBest`). With no prior best either — a brand-new exercise — there's nothing to show,
        // so the badge renders nothing (the info panel owns the "no data yet" state). The instant a
        // value is entered `sessionBest` turns positive and the trend pill takes over, unchanged.
        let idleBest = sessionBest == 0 ? comparison.currentBest(displayed) : nil
        return Group {
            if sessionBest > 0 || idleBest != nil {
                pill(accent: accent, idleBest: idleBest)
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .global)
                    } action: { _, newValue in
                        badgeFrame = newValue
                    }
                    // Slightly more than the set cells' edge inset (CELL_PADDING / 2) — the capsule sits in
                    // the cell's rounded corner, which visually eats some of the gap.
                    .padding(.top, CELL_PADDING / 2 + 3)
                    .padding(.trailing, CELL_PADDING / 2 + 3)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        if let onTapBadge {
                            if badgeFrame != .zero {
                                onTapBadge(setGroup, badgeFrame)
                            }
                        } else {
                            isShowingInfo = true
                        }
                    }
                    .popover(isPresented: $isShowingInfo) {
                        MetricInfoPanel(setGroup: setGroup, onOpenDetail: { metric in
                            detailMetric = metric
                            isShowingInfo = false
                            // Present after the popover's dismissal settles — competing presentations
                            // from the same host cancel each other.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                                detailExercise = setGroup.exercise
                            }
                        })
                        .padding()
                        .frame(width: 320)
                        .presentationCompactAdaptation(.popover)
                    }
                    .sheet(item: $detailExercise) { exercise in
                        NavigationStack {
                            ExerciseDetailScreen(exercise: exercise, isShowingAsSheet: true, autoOpenMetric: detailMetric)
                        }
                        .presentationDragIndicator(.visible)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(accessibilityDescription))
                    .accessibilityHint(Text(NSLocalizedString("tapForMetricInfo", comment: "")))
                    .onAppear {
                        primaryMetric = setGroup.exercise?.primaryMetric ?? .defaultMetric
                        peek.seed(prSnapshot())
                        peek.setEditing(isEditing)
                    }
            }
        }
        .onChange(of: isEditing) { _, editing in
            peek.setEditing(editing)
        }
        .onChange(of: prSignature) { _, _ in
            peek.update(
                prs: prSnapshot(),
                primary: primaryMetric,
                order: ExercisePrimaryMetric.allowed(
                    for: setGroup.exercise?.measurementType ?? .repsAndWeight
                )
            )
        }
        .onChange(of: displayedIsRecord) { _, newValue in
            // The chosen metric becoming a record celebrates here; peeked records fire their own
            // haptic in the controller, so guard those out.
            if newValue, peek.activeMetric == nil {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            // The committed metric is persisted per-exercise in UserDefaults, and the badge never
            // changes it itself — the info panel's picker (presented separately in the recorder)
            // and the exercise editor write it. Re-sync to it, cancelling any running peek so the
            // user's explicit choice is what lands on screen.
            let current = setGroup.exercise?.primaryMetric ?? .defaultMetric
            guard current != primaryMetric else { return }
            peek.cancelForManualCycle()
            withAnimation(MetricPeekController.rollAnimation) {
                primaryMetric = current
            }
        }
    }

    // MARK: - Pill rendering

    /// Idle vs trend dispatch: before this session's first entry the badge shows the current best
    /// to beat (`idleBest`); once a value is in, the trend pill takes over. The empty-empty case
    /// (no entry, no prior best) is filtered out in `body`, so a non-nil `idleBest` here always has
    /// a value to show.
    @ViewBuilder
    private func pill(accent: Color, idleBest: Int?) -> some View {
        if let idleBest {
            idlePill(best: idleBest)
        } else {
            trendPill(accent: accent)
        }
    }

    /// The empty/idle state: the exercise's current best for the displayed metric — the bar the
    /// trend pill scores against — in muted gray behind a `target`, deliberately not the record
    /// `trophy.fill` (a target is the goal to clear, not a win already won). A tap still opens the
    /// info panel and switching metric still rolls, exactly like the trend pill; the value reuses
    /// the record state's `valueView` so the idle and record states read alike.
    private func idlePill(best: Int) -> some View {
        let metric = displayedMetric
        return ProgressIndicatorPill(symbol: "target", color: .secondary, size: .prominent) {
            VStack(alignment: .trailing, spacing: 1) {
                valueView(for: metric, value: best)
                    .foregroundStyle(.secondary)
                Text(metric.shortTitle)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .contentTransition(.numericText())
        .animation(MetricPeekController.rollAnimation, value: metric)
    }

    /// Mirrors `TrendIndicatorView` (the trend pill on the chart screens) — arrow weight, percent
    /// formatting, tint, capsule fill (translucent accent as soon as the trend is positive, never a
    /// border) — with the metric's name in fine print beneath the value. It can't embed that view
    /// directly because the record state swaps the trend row for a trophy and the record value
    /// inside the same capsule.
    private func trendPill(accent: Color) -> some View {
        let metric = displayedMetric
        let isRecord = displayedIsRecord
        let change = comparison.percentChange(metric) ?? 0
        let direction = trendDirection(for: change)
        let trendColor = direction == .up ? accent : Color.secondary
        let isColorful = isRecord || direction == .up
        // The icon sits beside the whole value+label stack so it centres on the badge, not the value.
        // A flat trend has no icon (nil) — the muted percent says "no change" without a minus that
        // would read like a decline; a record still shows the trophy.
        let symbol = isRecord ? "trophy.fill" : symbolName(for: direction)
        // The whole capsule (icon + capsule fill + two-line value/name) is the shared
        // `ProgressIndicatorPill`; only the per-line color overrides and the metric name in fine
        // print are local. The pill's tint (icon + fill) is the record/up accent, else muted gray.
        return ProgressIndicatorPill(symbol: symbol, color: isRecord ? accent : trendColor, size: .prominent) {
            VStack(alignment: .trailing, spacing: 1) {
                if isRecord {
                    recordValueView(for: metric)
                        .foregroundStyle(accent)
                } else {
                    Text(displayedFraction(for: change), format: .percent.precision(.fractionLength(0)))
                        .font(.system(.footnote, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(trendColor)
                }
                Text(metric.shortTitle)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(isColorful ? AnyShapeStyle(accent.secondary) : AnyShapeStyle(.secondary))
            }
        }
        .contentTransition(.numericText())
        // Roll between metrics (a peek, or a new choice from the panel) with the shared spring so
        // the capsule resizes smoothly from its trailing anchor; value edits animate the number in
        // place via the content transition.
        .animation(MetricPeekController.rollAnimation, value: metric)
        .animation(.snappy, value: change)
        .scaleEffect(isRecord ? 1.05 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.5), value: isRecord)
    }

    /// The session's record value, beside the trophy, while the displayed metric stands at a
    /// personal record — the record itself is the news; the percentage returns once it no longer is.
    private func recordValueView(for metric: ExercisePrimaryMetric) -> some View {
        valueView(for: metric, value: comparison.sessionBest(metric))
    }

    /// A metric's value with its unit, sized for the pill — shared by the record state (this
    /// session's best, beside the trophy) and the idle state (the current best to beat, in gray).
    private func valueView(for metric: ExercisePrimaryMetric, value: Int) -> some View {
        switch metric {
        case .estimatedOneRepMax:
            return UnitView(value: formatEstimatedOneRepMax(value), unit: WeightUnit.used.rawValue, configuration: .extraSmall)
        case .weight:
            return UnitView(value: formatWeightForDisplay(value), unit: WeightUnit.used.rawValue, configuration: .extraSmall)
        case .repetitions:
            return UnitView(value: "\(value)", unit: NSLocalizedString("reps", comment: ""), configuration: .extraSmall)
        case .duration:
            return UnitView(value: "\(value)", unit: NSLocalizedString("sec", comment: ""), configuration: .extraSmall)
        case .distance:
            return UnitView(
                value: formatDistanceForDisplay(Int64(value), style: distanceStyle),
                unit: distanceUnitTitle(for: distanceStyle),
                configuration: .extraSmall
            )
        }
    }

    /// The distance scale for this exercise's displayed values — from its measurement type,
    /// defaulting to the cardio (km) scale.
    private var distanceStyle: SetMeasurementType.DistanceStyle {
        setGroup.exercise?.measurementType.distanceStyle ?? .long
    }

    // MARK: - Trend rendering (math lives in SetGroupMetricComparison)

    private enum TrendDirection { case up, down, flat }

    /// Whole displayed percent, capped like the chart pill so an outlier can't blow up the badge.
    private func trendMagnitude(for change: Double) -> Int { Int(min(abs(change), 999).rounded()) }

    private func trendDirection(for change: Double) -> TrendDirection {
        guard trendMagnitude(for: change) > 0 else { return .flat }
        return change > 0 ? .up : .down
    }

    /// Nil for a flat trend — see `pill(accent:)`; the muted percent carries "no change" on its own.
    private func symbolName(for direction: TrendDirection) -> String? {
        switch direction {
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .flat: return nil
        }
    }

    private func displayedFraction(for change: Double) -> Double {
        Double(trendMagnitude(for: change)) / 100
    }

    /// Spoken summary mirroring what's drawn: the metric, then the current best (idle), the record,
    /// or the trend.
    private var accessibilityDescription: String {
        let base = "\(NSLocalizedString("progressMetric", comment: "")), \(displayedMetric.title)"
        // Idle (nothing logged yet): spoken as the current best to beat, matching the pill.
        if comparison.sessionBest(displayedMetric) == 0, let best = comparison.currentBest(displayedMetric) {
            return "\(base), \(NSLocalizedString("currentBest", comment: "")), \(accessibleValue(best, for: displayedMetric))"
        }
        if displayedIsRecord {
            return "\(base), \(NSLocalizedString("personalRecord", comment: ""))"
        }
        let change = comparison.percentChange(displayedMetric) ?? 0
        let percentString = displayedFraction(for: change).formatted(.percent.precision(.fractionLength(0)))
        switch trendDirection(for: change) {
        case .up: return "\(base), " + String(format: NSLocalizedString("trendUp", comment: ""), percentString)
        case .down: return "\(base), " + String(format: NSLocalizedString("trendDown", comment: ""), percentString)
        case .flat: return "\(base), " + NSLocalizedString("trendFlat", comment: "")
        }
    }

    /// A metric value with its unit as plain text, for VoiceOver — the drawn `UnitView` uppercases
    /// the unit, but spoken text keeps it natural.
    private func accessibleValue(_ value: Int, for metric: ExercisePrimaryMetric) -> String {
        switch metric {
        case .estimatedOneRepMax:
            return "\(formatEstimatedOneRepMax(value)) \(WeightUnit.used.rawValue)"
        case .weight:
            return "\(formatWeightForDisplay(value)) \(WeightUnit.used.rawValue)"
        case .repetitions:
            return "\(value) \(NSLocalizedString("reps", comment: ""))"
        case .duration:
            return "\(value) \(NSLocalizedString("sec", comment: ""))"
        case .distance:
            return "\(formatDistanceForDisplay(Int64(value), style: distanceStyle)) \(distanceUnitTitle(for: distanceStyle))"
        }
    }

    // MARK: - Record peeks

    /// Base values of every metric currently at a personal record, for the peek controller.
    private func prSnapshot() -> [ExercisePrimaryMetric: Int] {
        var snapshot: [ExercisePrimaryMetric: Int] = [:]
        for metric in ExercisePrimaryMetric.allCases where comparison.isPersonalRecord(metric) {
            snapshot[metric] = comparison.sessionBest(metric)
        }
        return snapshot
    }

    /// Stable string that changes whenever any metric's record value changes — drives `onChange`.
    private var prSignature: String {
        ExercisePrimaryMetric.allCases
            .map { "\($0.rawValue):\(comparison.isPersonalRecord($0) ? comparison.sessionBest($0) : 0)" }
            .joined(separator: "|")
    }
}

/// Drives the personal-best "peek": when a non-primary metric sets a record, show it briefly (with a
/// success haptic) then roll back to the primary. Multiple fresh records are shown in turn. A manual
/// cycle cancels any peek and suppresses further peeks until the *next* record arrives.
@MainActor
private final class MetricPeekController: ObservableObject {
    static let rollAnimation: Animation = .spring(response: 0.4, dampingFraction: 0.85)

    /// How long each record is shown before rolling on.
    private let peekDuration: Double = 3.0

    /// The record metric currently on screen, or nil while the primary metric is shown.
    @Published private(set) var activeMetric: ExercisePrimaryMetric?

    private var queue: [ExercisePrimaryMetric] = []
    private var suppressed = false
    /// While a set field is being edited the badge is often scrolled out of view, so records found
    /// mid-edit are queued and only played once editing ends.
    private var editing = false
    /// Highest record value already surfaced per metric this session — a peek only fires on a new high.
    private var lastSurfaced: [ExercisePrimaryMetric: Int] = [:]
    private var seeded = false
    private var task: Task<Void, Never>?

    /// Records the current record values on first appearance so pre-existing PRs don't peek when the
    /// cell merely scrolls into view — only records set *after* this fire.
    func seed(_ prs: [ExercisePrimaryMetric: Int]) {
        guard !seeded else { return }
        seeded = true
        lastSurfaced = prs
    }

    func update(
        prs: [ExercisePrimaryMetric: Int],
        primary: ExercisePrimaryMetric,
        order: [ExercisePrimaryMetric]
    ) {
        guard seeded else { seed(prs); return }
        var fresh: [ExercisePrimaryMetric] = []
        for metric in order {
            guard let value = prs[metric] else { continue }
            if value > (lastSurfaced[metric] ?? 0) {
                lastSurfaced[metric] = value
                if metric != primary { fresh.append(metric) }
            }
        }
        guard !fresh.isEmpty else { return }
        suppressed = false // a new record lifts manual suppression
        for metric in fresh where !queue.contains(metric) { queue.append(metric) }
        startIfIdle()
    }

    func cancelForManualCycle() {
        task?.cancel()
        task = nil
        queue.removeAll()
        suppressed = true
        activeMetric = nil
    }

    /// Tracks whether a set field is being edited. Records detected while editing wait; when editing
    /// ends the badge is back on screen, so any queued peek plays then.
    func setEditing(_ value: Bool) {
        guard value != editing else { return }
        editing = value
        if !value { startIfIdle() }
    }

    private func startIfIdle() {
        guard task == nil, !suppressed, !editing, activeMetric == nil, !queue.isEmpty else { return }
        runNext()
    }

    private func runNext() {
        guard !suppressed, !queue.isEmpty else {
            withAnimation(Self.rollAnimation) { activeMetric = nil }
            task = nil
            return
        }
        let next = queue.removeFirst()
        withAnimation(Self.rollAnimation) { activeMetric = next }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        task = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.peekDuration * 1_000_000_000))
            if Task.isCancelled { return }
            self.runNext()
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

// MARK: - Metric info panel

/// Shown when the metric badge is tapped: a switcher (the only way to change the badge's metric),
/// then the badge's comparison as one scoreboard row — current best on the left, this workout on
/// the right, the badge's percent pill as the step between them — over a full-width progression
/// chart flowing the same old-to-new direction (same design as the exercise-detail tiles), with
/// the metric explanation as fine print (the current-best definition lives in the chart detail
/// screens' header popover instead). Values and percent all
/// come from `SetGroupMetricComparison`, the badge's own math, so the panel can never contradict
/// the badge (`Exercise.currentBestSet` would: it includes this workout).
/// Shared by the badge's own popover (most screens) and the recorder, which presents it as a sheet
/// from its persistent exercise sheet so that sheet survives.
struct MetricInfoPanel: View {
    @ObservedObject var setGroup: WorkoutSetGroup
    /// Called when the value/chart row is tapped — the host opens the exercise detail at this
    /// metric's chart screen. The row isn't tappable when nil.
    var onOpenDetail: ((ExercisePrimaryMetric) -> Void)?
    @State private var selectedMetric: ExercisePrimaryMetric

    /// Only the metrics that fit how the exercise is measured — five total metrics exist now,
    /// and a segmented control full of inapplicable ones (an e1RM segment on a plank) helps no
    /// one. Matches the badge's cycling order and the exercise editor's picker.
    private var metrics: [ExercisePrimaryMetric] {
        ExercisePrimaryMetric.allowed(for: setGroup.exercise?.measurementType ?? .repsAndWeight)
    }

    /// Same math as the badge — see the type's doc.
    private var comparison: SetGroupMetricComparison { SetGroupMetricComparison(setGroup: setGroup) }

    init(setGroup: WorkoutSetGroup, onOpenDetail: ((ExercisePrimaryMetric) -> Void)? = nil) {
        _setGroup = ObservedObject(wrappedValue: setGroup)
        self.onOpenDetail = onOpenDetail
        _selectedMetric = State(initialValue: setGroup.exercise?.primaryMetric ?? .defaultMetric)
    }

    var body: some View {
        let color = setGroup.exercise?.muscleGroup?.color ?? .accentColor
        // Nothing has ever been logged for this metric — a brand-new exercise, or e1RM on one only
        // ever trained above 12 reps. The scoreboard would read "––" vs "––" over a blank chart, so
        // show the shared empty state instead (see `emptyState`). `metricPoints` spans the whole
        // history up to the anchor including this session, so empty here == no value anywhere.
        let hasData = !metricPoints(for: selectedMetric).isEmpty
        return VStack(alignment: .leading, spacing: 14) {
            Picker("", selection: Binding(get: { selectedMetric }, set: { setMetric($0) })) {
                ForEach(metrics, id: \.self) { metric in
                    Text(metric.title).tag(metric)
                }
            }
            .pickerStyle(.segmented)

            if hasData {
                // Weight and e1RM comparisons are Pro content; repetitions stays free so every user
                // gets the full panel on one metric (and the default metric for free users IS reps —
                // see `ExercisePrimaryMetric.defaultMetric`). Only the data is gated: the picker stays
                // usable so a free user can always switch to reps (or set the badge to any metric),
                // and the blurred block shows exactly what Pro would reveal.
                Group {
                    if let onOpenDetail {
                        Button {
                            onOpenDetail(selectedMetric)
                        } label: {
                            comparisonAndChart(color: color)
                        }
                        .buttonStyle(.plain)
                    } else {
                        comparisonAndChart(color: color)
                    }
                }
                .isBlockedWithoutPro(selectedMetric != .repetitions)
            } else {
                emptyState(color: color)
            }

            Text(explanation(for: selectedMetric))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Replaces the scoreboard and chart when the selected metric has nothing to show — same ghost
    /// sparkline and "no data yet" copy as the exercise-detail empty tile (`ExerciseMetricsEmptyTile`),
    /// so an empty popover reads as a designed state rather than a pair of dashes over a void. The
    /// explanation below still renders, so the panel keeps teaching what the metric is. Deliberately
    /// *not* Pro-gated: with no data there is nothing to unlock, and a paywall here would promise
    /// something upgrading wouldn't reveal.
    private func emptyState(color: Color) -> some View {
        VStack(spacing: 12) {
            GhostSparkline(color: color)
                .frame(width: 160, height: 46)
            VStack(spacing: 3) {
                Text(NSLocalizedString("noExerciseDataTitle", comment: ""))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.label)
                Text(NSLocalizedString("noExerciseDataMessage", comment: ""))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    /// The heart of the panel, one scoreboard row: current best → this workout, old to new like the
    /// chart beneath, with the badge's pill as the step between them (hidden when there's nothing to
    /// compare). Color carries the meaning — only the session value wears the muscle-group tint
    /// (it's the live side of the comparison, and what the badge tints when you're up); the
    /// reference stays neutral so a single glance finds "you, now".
    private func comparisonRow(color: Color) -> some View {
        MetricComparisonView(
            leading: .init(
                label: NSLocalizedString("currentBest", comment: ""),
                value: currentBestValue(for: selectedMetric),
                unit: panelUnit(for: selectedMetric)
            ),
            trailing: .init(
                label: NSLocalizedString("thisWorkout", comment: ""),
                value: formattedValue(comparison.sessionBest(selectedMetric), for: selectedMetric),
                unit: panelUnit(for: selectedMetric)
            ),
            trailingValueStyle: AnyShapeStyle(color.gradient),
            percentChange: comparison.percentChange(selectedMetric),
            positiveColor: color,
            isRecord: comparison.isPersonalRecord(selectedMetric)
        )
    }

    /// The comparison row over its full-width chart, sitting tighter together than the panel's
    /// other rows — one perceptual unit (the two numbers, then the history they come from) and,
    /// where the host can open it, one whole-area tap target for the exercise-detail chart screen
    /// (no chevron — the numbers and chart themselves are the invitation).
    private func comparisonAndChart(color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            comparisonRow(color: color)
            metricChart(for: selectedMetric, color: color)
        }
        .contentShape(Rectangle())
    }

    /// Persists the chosen metric (per exercise). The badge observes `UserDefaults.didChangeNotification`
    /// and re-syncs, so this is reflected on the badge even when the panel is a separate sheet.
    private func setMetric(_ metric: ExercisePrimaryMetric) {
        guard metric != selectedMetric else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        selectedMetric = metric
        setGroup.exercise?.primaryMetric = metric
    }

    private func explanation(for metric: ExercisePrimaryMetric) -> String {
        switch metric {
        case .estimatedOneRepMax: return NSLocalizedString("e1RMInfo", comment: "")
        case .weight: return NSLocalizedString("metricInfoWeight", comment: "")
        case .repetitions: return NSLocalizedString("metricInfoReps", comment: "")
        case .duration: return NSLocalizedString("metricInfoDuration", comment: "")
        case .distance: return NSLocalizedString("metricInfoDistance", comment: "")
        }
    }

    // MARK: - Values

    /// The exercise's current best for `metric` — the badge's own baseline (excluding this
    /// workout), so the percent pill and the two displayed values always agree.
    private func currentBestValue(for metric: ExercisePrimaryMetric) -> String {
        guard let best = comparison.currentBest(metric) else { return "––" }
        return formattedValue(best, for: metric)
    }

    private func formattedValue(_ value: Int, for metric: ExercisePrimaryMetric) -> String {
        guard value > 0 else { return "––" }
        switch metric {
        case .estimatedOneRepMax: return formatEstimatedOneRepMax(value)
        case .weight: return formatWeightForDisplay(value)
        case .repetitions, .duration: return String(value)
        case .distance: return formatDistanceForDisplay(Int64(value), style: distanceStyle)
        }
    }

    private func panelUnit(for metric: ExercisePrimaryMetric) -> String {
        switch metric {
        case .estimatedOneRepMax, .weight: return WeightUnit.used.rawValue
        case .repetitions: return NSLocalizedString("reps", comment: "")
        case .duration: return NSLocalizedString("sec", comment: "")
        case .distance: return distanceUnitTitle(for: distanceStyle)
        }
    }

    /// The distance scale for displayed values — same rule as the badge's.
    private var distanceStyle: SetMeasurementType.DistanceStyle {
        setGroup.exercise?.measurementType.distanceStyle ?? .long
    }

    // MARK: - Progression chart

    private func metricBase(_ set: WorkoutSet, _ metric: ExercisePrimaryMetric, _ exercise: Exercise) -> Int {
        switch metric {
        case .estimatedOneRepMax: return set.estimatedOneRepMax(for: exercise)
        case .weight: return set.maximum(.weight, for: exercise)
        case .repetitions: return set.maximum(.repetitions, for: exercise)
        case .duration: return set.maximum(.duration, for: exercise)
        case .distance: return set.maximum(.distance, for: exercise)
        }
    }

    private func metricDisplayValue(_ base: Int, _ metric: ExercisePrimaryMetric) -> Double {
        switch metric {
        case .estimatedOneRepMax, .weight: return convertWeightForDisplayingDecimal(base)
        case .repetitions, .duration: return Double(base)
        case .distance:
            switch distanceStyle {
            case .long: return convertDistanceForDisplayingDecimal(Int64(base))
            case .short: return Double(convertShortDistanceForDisplaying(Int64(base)))
            }
        }
    }

    /// Daily-max points for `metric` across this exercise's sessions up to the window anchor,
    /// oldest → newest. Sessions after a finished workout's date are cut so the chart's story ends
    /// where the comparison's does (the domain would clip them anyway, but a Catmull-Rom segment
    /// into a clipped point still bends the visible line).
    private func metricPoints(for metric: ExercisePrimaryMetric) -> [TileSparklinePoint] {
        guard let exercise = setGroup.exercise else { return [] }
        let grouped = Dictionary(grouping: exercise.sets) {
            Calendar.current.startOfDay(for: $0.workout?.date ?? .now)
        }
        return grouped.compactMap { _, sets -> TileSparklinePoint? in
            guard let best = sets.max(by: { metricBase($0, metric, exercise) < metricBase($1, metric, exercise) })
            else { return nil }
            let base = metricBase(best, metric, exercise)
            guard base > 0, let date = best.workout?.date else { return nil }
            return TileSparklinePoint(date: date, value: metricDisplayValue(base, metric))
        }
        .filter { $0.date <= windowAnchor }
        .sorted { $0.date < $1.date }
    }

    /// Anchor of the chart window — the same anchor `SetGroupMetricComparison` uses for the current
    /// best: now while recording, the workout's own date once it's finished. Without this, opening
    /// the panel on an old workout would chart *today's* last month next to that day's numbers.
    private var windowAnchor: Date {
        setGroup.workout?.isCurrentWorkout == true ? .now : (setGroup.workout?.date ?? .now)
    }

    /// Chart window == current-best window, so everything the chart shows is exactly the history
    /// the comparison above it is computed from (plus this workout's own point).
    private var chartStartDate: Date {
        Exercise.currentBestWindowStart(endingAt: windowAnchor)
    }

    /// Trailing edge of the x-domain, pushed ~2 days past the anchor so the latest point's symbol
    /// clears the right edge — the chart is `.clipped()` with no trailing fade, and the recorder's
    /// last point is always today, so without this margin it gets sliced in half. (The volume tile
    /// does the same by extending to `endOfWeek`.)
    private var chartEndDate: Date {
        Calendar.current.date(byAdding: .day, value: 2, to: windowAnchor) ?? windowAnchor
    }

    /// Compact progression chart matching the exercise-detail tiles (line + area, muscle-group
    /// colour, faded leading edge, hidden axes). Empty when the metric has no history.
    @ViewBuilder
    private func metricChart(for metric: ExercisePrimaryMetric, color: Color) -> some View {
        let points = metricPoints(for: metric)
        let maxValue = points.map(\.value).max() ?? 1
        Chart {
            tileSparklineMarks(points: points, color: color, carryForwardEnd: windowAnchor)
        }
        .chartXScale(domain: chartStartDate ... chartEndDate)
        .chartYScale(domain: 0 ... max(maxValue * 1.15, 1))
        .chartXAxis {}
        .chartYAxis {}
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .clipped()
        .tileSparklineFadeMask()
    }
}

