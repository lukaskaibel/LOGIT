//
//  WorkoutSetGroupCell.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 28.07.23.
//

import Charts
import Combine
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
            if !isReordering, let workout = setGroup.workout {
                MetricBadgeView(
                    setGroup: setGroup,
                    workout: workout,
                    isEditing: focusedIntegerFieldIndex != nil
                )
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

/// The progress-metric badge shown on each set group. It's a small vertical wheel of three metrics
/// (e1RM / Weight / Reps): drag up or down to switch — slivers of the neighbouring metrics peek above
/// and below to signal it scrolls, a selection haptic fires as each becomes centred, and on release it
/// snaps to and persists the centred metric. A tap opens a panel with the metric's explanation and a
/// segmented switcher (the accessible path — the wheel also exposes an adjustable action). When a set
/// scores a personal best on a metric *other* than the centred one, the badge briefly "peeks" that
/// metric, with a trophy, before rolling back, so a win is never hidden.
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
    @StateObject private var peek = MetricPeekController()
    /// Set by the workout recorder. There the badge sits behind a persistent sheet, so presenting its
    /// own popover/sheet would tear that sheet down — instead the tap is routed up and the recorder
    /// presents the panel from the sheet's own context. Nil elsewhere, where the popover is fine.
    @Environment(\.metricInfoRequest) private var metricInfoRequest

    @State private var primaryMetric: ExercisePrimaryMetric = .estimatedOneRepMax
    @State private var isShowingInfo = false
    /// The badge's frame in global (window) coordinates, captured so the recorder can anchor its
    /// popover at the badge. Pure layout observation — nothing extra in the badge's render path.
    @State private var badgeFrame: CGRect = .zero

    // MARK: - Wheel geometry

    private let metrics = ExercisePrimaryMetric.allCases
    /// Drag distance (points) that advances one metric.
    private let itemHeight: CGFloat = 34

    @State private var isDragging = false
    /// Continuous scroll position in item units. An integer means that metric is centred; the integer
    /// is *virtual* (can exceed the metric count) so the wheel wraps endlessly while dragging. At rest
    /// it's normalised to 0..<count.
    @State private var scrollPos: Double = 0
    @State private var dragStartPos: Double = 0
    @State private var lastHapticIndex = 0

    private func index(of metric: ExercisePrimaryMetric) -> Int { metrics.firstIndex(of: metric) ?? 0 }

    /// Wraps a virtual index into 0..<count so the wheel can scroll endlessly in either direction.
    private func wrapped(_ i: Int) -> Int {
        let n = metrics.count
        return ((i % n) + n) % n
    }
    private func metric(atVirtual v: Int) -> ExercisePrimaryMetric { metrics[wrapped(v)] }

    /// The metric centred in the window — the rounded scroll position, wrapped.
    private var displayedMetric: ExercisePrimaryMetric { metric(atVirtual: Int(scrollPos.rounded())) }

    private var centeredIsRecord: Bool {
        recordMetric(for: resolvedDisplay(for: displayedMetric)).map(isPersonalRecord) ?? false
    }

    var body: some View {
        let accent = setGroup.exercise?.muscleGroup?.color ?? .accentColor
        return wheel(accent: accent)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { _, newValue in
                badgeFrame = newValue
            }
            .padding(.top, CELL_PADDING / 2)
            .padding(.trailing, CELL_PADDING / 2)
            .contentShape(Rectangle())
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                if let metricInfoRequest {
                    if badgeFrame != .zero {
                        metricInfoRequest(setGroup, badgeFrame)
                    }
                } else {
                    isShowingInfo = true
                }
            }
            .highPriorityGesture(dragGesture)
            .popover(isPresented: $isShowingInfo) {
                MetricInfoPanel(setGroup: setGroup)
                    .padding()
                    .frame(width: 320)
                    .presentationCompactAdaptation(.popover)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(NSLocalizedString("progressMetric", comment: "")), \(displayedMetric.title)"))
            .accessibilityHint(Text(NSLocalizedString("swipeForMetrics", comment: "")))
            .accessibilityAdjustableAction { direction in
                let center = Int(scrollPos.rounded())
                switch direction {
                case .increment: setMetric(metric(atVirtual: center + 1))
                case .decrement: setMetric(metric(atVirtual: center - 1))
                default: break
                }
            }
            .onAppear {
                primaryMetric = setGroup.exercise?.primaryMetric ?? .estimatedOneRepMax
                scrollPos = Double(index(of: primaryMetric))
                peek.seed(prSnapshot())
                peek.setEditing(isEditing)
            }
            .onChange(of: isEditing) { _, editing in
                peek.setEditing(editing)
            }
            .onChange(of: prSignature) { _, _ in
                peek.update(prs: prSnapshot(), primary: primaryMetric, order: ExercisePrimaryMetric.allCases)
            }
            .onChange(of: centeredIsRecord) { _, newValue in
                // Primary metric becoming a record at rest celebrates here; peeked records fire their
                // own haptic in the controller and drags fire selection haptics, so guard those out.
                if newValue, peek.activeMetric == nil, !isDragging {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
            .onChange(of: peek.activeMetric) { _, _ in
                // Scroll the wheel to a peeked record (and back when it ends). The drag owns scrollPos.
                guard !isDragging else { return }
                withAnimation(MetricPeekController.rollAnimation) {
                    scrollPos = Double(index(of: peek.activeMetric ?? primaryMetric))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                // The committed metric is persisted per-exercise in UserDefaults, so it can change out
                // from under us — from the info panel's picker (presented separately in the recorder)
                // or the exercise editor. Re-sync the wheel to it when idle.
                guard !isDragging, peek.activeMetric == nil else { return }
                let current = setGroup.exercise?.primaryMetric ?? .estimatedOneRepMax
                guard current != primaryMetric else { return }
                primaryMetric = current
                withAnimation(MetricPeekController.rollAnimation) {
                    scrollPos = Double(index(of: current))
                }
            }
    }

    // MARK: - Wheel rendering

    /// Fractional distance from the centred metric, in [-0.5, 0.5]. Zero whenever the wheel is at
    /// rest (`scrollPos` is an integer there); non-zero only mid-drag / mid-snap.
    private var scrollFraction: Double { scrollPos - scrollPos.rounded() }

    /// One metric at a time, but it *rides the finger*: the content slides and cross-fades by the
    /// fractional scroll position, so dragging feels like a continuous, wrapping wheel rather than a
    /// hard swap. Only `.offset`/`.opacity`/`.scaleEffect` transforms are used on a single,
    /// always-present item — never a mask, clip, transition, or a strip whose ids change. Those are
    /// exactly the constructs that blank this badge behind the recorder's interactive sheet; pure
    /// transforms render reliably. The outgoing metric fades to ~0 before it slides past the pill
    /// edge (there's no clip), so its overflow is invisible and the hand-off to the next metric — at
    /// the half-step, where the wrapping `displayedMetric` flips — is seamless.
    private func wheel(accent: Color) -> some View {
        let isRecord = centeredIsRecord
        let frac = scrollFraction
        let slideOffset = -frac * itemHeight                 // content tracks the drag, ±½ item
        let slideOpacity = max(0, 1 - abs(frac) * 2.2)       // faded out by the hand-off point
        return metricItem(displayedMetric, accent: accent)
            .offset(y: slideOffset)
            .opacity(slideOpacity)
            .frame(minHeight: itemHeight)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 30 - CELL_PADDING / 2)
                    .foregroundStyle(isRecord ? accent.opacity(0.18) : Color.tertiaryBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 30 - CELL_PADDING / 2)
                    .strokeBorder(accent.opacity(isRecord ? 0.6 : 0), lineWidth: 1)
            )
            .cornerRadius(30 - CELL_PADDING / 2)
            // Spring the pill's resize when the metric (hence content width/height) changes — at the
            // mid-drag hand-off and when the panel/peek switches metric — so the badge grows/shrinks
            // smoothly from its trailing anchor instead of snapping. The slide/opacity above stay
            // continuous: this animation's transient kick to the offset is overridden by the next drag
            // frame (and happens at ~0 opacity), so only the frame resize reads on screen.
            .animation(MetricPeekController.rollAnimation, value: displayedMetric)
            .scaleEffect(isRecord ? 1.05 : 1.0)
            .animation(.spring(response: 0.35, dampingFraction: 0.5), value: isRecord)
    }

    private func metricItem(_ metric: ExercisePrimaryMetric, accent: Color) -> some View {
        let display = resolvedDisplay(for: metric)
        let isRecord = recordMetric(for: display).map(isPersonalRecord) ?? false
        return VStack(alignment: .trailing, spacing: 1) {
            HStack(spacing: 3) {
                if isRecord {
                    Image(systemName: "trophy.fill")
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                }
                Text(label(for: metric, display: display))
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
            }
            .foregroundStyle(isRecord ? accent : Color.secondary)
            valueView(for: display, isRecord: isRecord, accent: accent)
        }
        .contentTransition(.numericText())
    }

    @ViewBuilder
    private func valueView(for display: MetricDisplay, isRecord: Bool, accent: Color) -> some View {
        let primaryColor = isRecord ? accent : Color.label
        switch display {
        case let .e1RM(grams):
            UnitView(
                value: formatEstimatedOneRepMax(grams),
                unit: WeightUnit.used.rawValue,
                configuration: .small
            )
            .foregroundStyle(primaryColor)
        case let .pair(reps, weightGrams, emphasize):
            pairView(reps: reps, weightGrams: weightGrams, emphasize: emphasize, primaryColor: primaryColor)
        case .empty:
            UnitView(value: "––", unit: WeightUnit.used.rawValue, configuration: .small)
                .foregroundStyle(Color.label)
        }
    }

    /// Renders "5 × 45 kg" with a fixed order (reps × weight); only the colour moves — the
    /// emphasised metric reads in the primary colour, the other in grey. Bodyweight sets (no weight)
    /// fall back to showing reps alone.
    @ViewBuilder
    private func pairView(
        reps: Int,
        weightGrams: Int64,
        emphasize: MetricDisplay.Emphasis,
        primaryColor: Color
    ) -> some View {
        let valueFont = Font.system(.subheadline, design: .rounded).weight(.bold)
        let unitFont = Font.system(.caption2, design: .rounded).weight(.semibold)
        let repsColor: Color = emphasize == .reps ? primaryColor : .secondary
        let weightColor: Color = emphasize == .weight ? primaryColor : .secondary
        if weightGrams > 0 {
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text("\(reps)")
                    .font(valueFont)
                    .foregroundStyle(repsColor)
                Text("×")
                    .font(unitFont)
                    .foregroundStyle(Color.secondary)
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(formatWeightForDisplay(weightGrams))
                        .font(valueFont)
                    Text(WeightUnit.used.rawValue)
                        .font(unitFont)
                }
                .foregroundStyle(weightColor)
            }
        } else {
            UnitView(value: "\(reps)", unit: NSLocalizedString("reps", comment: ""), configuration: .small)
                .foregroundStyle(primaryColor)
        }
    }

    // MARK: - Gestures & actions

    /// A vertical drag scrolls the wheel continuously — unclamped, so dragging far wraps through the
    /// metrics endlessly — with a selection haptic per metric crossed, and snaps to / persists the
    /// centred metric on release. `minimumDistance: 8` keeps it from stealing taps (a tap opens the
    /// panel) and from firing spuriously on launch; `highPriorityGesture` lets a real drag win over
    /// the recorder's page scroll.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragStartPos = Double(index(of: peek.activeMetric ?? primaryMetric))
                    lastHapticIndex = Int(dragStartPos.rounded())
                    peek.cancelForManualCycle()
                }
                // Follow the finger continuously, unclamped — dragging far wraps through the metrics
                // repeatedly. Dragging up advances to the next metric.
                scrollPos = dragStartPos - Double(value.translation.height) / Double(itemHeight)
                let idx = Int(scrollPos.rounded())
                if idx != lastHapticIndex {
                    lastHapticIndex = idx
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
            .onEnded { _ in
                guard isDragging else { return }
                let targetVirtual = Int(scrollPos.rounded())
                let target = metric(atVirtual: targetVirtual)
                setGroup.exercise?.primaryMetric = target
                UISelectionFeedbackGenerator().selectionChanged()
                // Snap to the nearest metric, then normalise the virtual position back into range
                // (invisible — same metric centred) once the snap settles.
                withAnimation(MetricPeekController.rollAnimation) {
                    scrollPos = Double(targetVirtual)
                } completion: {
                    primaryMetric = target
                    scrollPos = Double(index(of: target))
                    isDragging = false
                }
            }
    }

    private func setMetric(_ metric: ExercisePrimaryMetric) {
        guard metric != primaryMetric else { return }
        setGroup.exercise?.primaryMetric = metric
        UISelectionFeedbackGenerator().selectionChanged()
        peek.cancelForManualCycle()
        primaryMetric = metric
        withAnimation(MetricPeekController.rollAnimation) {
            scrollPos = Double(index(of: metric))
        }
    }

    // MARK: - Display resolution

    /// Resolves the requested metric to what's actually rendered, falling back gracefully when the
    /// chosen metric has no usable data (e.g. e1RM on a bodyweight or high-rep set → reps).
    private func resolvedDisplay(for metric: ExercisePrimaryMetric) -> MetricDisplay {
        switch metric {
        case .estimatedOneRepMax:
            if let grams = bestE1RMGrams() { return .e1RM(grams: grams) }
            if let r = bestRepsEntry() { return .pair(reps: Int(r.reps), weightGrams: r.weight, emphasize: .reps) }
            if let w = bestWeightEntry() { return .pair(reps: Int(w.reps), weightGrams: w.weight, emphasize: .weight) }
            return .empty
        case .weight:
            if let w = bestWeightEntry() { return .pair(reps: Int(w.reps), weightGrams: w.weight, emphasize: .weight) }
            if let r = bestRepsEntry() { return .pair(reps: Int(r.reps), weightGrams: r.weight, emphasize: .reps) }
            return .empty
        case .repetitions:
            if let r = bestRepsEntry() { return .pair(reps: Int(r.reps), weightGrams: r.weight, emphasize: .reps) }
            if let w = bestWeightEntry() { return .pair(reps: Int(w.reps), weightGrams: w.weight, emphasize: .weight) }
            return .empty
        }
    }

    /// The badge label is the plain metric name — it makes no timeframe claim (the value is the
    /// *current best*, not an all-time max, so "Max Weight" would over-claim), and it keeps the
    /// two pair-rendered metrics distinguishable. The popover explains the current-best window.
    private func label(for metric: ExercisePrimaryMetric, display: MetricDisplay) -> String {
        switch display {
        case .e1RM: return NSLocalizedString("e1RM", comment: "")
        case let .pair(_, _, emphasize):
            return emphasize == .weight
                ? NSLocalizedString("weight", comment: "")
                : NSLocalizedString("repetitions", comment: "")
        case .empty: return metric.title
        }
    }

    /// The metric whose personal-best status the on-screen value reflects (drives the trophy).
    private func recordMetric(for display: MetricDisplay) -> ExercisePrimaryMetric? {
        switch display {
        case .e1RM: return .estimatedOneRepMax
        case let .pair(_, _, emphasize): return emphasize == .weight ? .weight : .repetitions
        case .empty: return nil
        }
    }

    // MARK: - Displayed values: the exercise's *current best* (last month, incl. this workout)

    /// The badge is an overview of the lifter's current standing for the exercise — what to beat
    /// today — not a readout of this session (the set rows below already show that). Values come
    /// from `Exercise.currentBestSet`, so they match the exercise-detail tiles; at workout start
    /// the badge immediately shows the standing best instead of "––".

    private func bestE1RMGrams() -> Int? {
        guard let exercise = setGroup.exercise,
              let best = exercise.currentBestSet(for: .estimatedOneRepMax)
        else { return nil }
        let grams = best.estimatedOneRepMax(for: exercise)
        return grams > 0 ? grams : nil
    }

    private func bestWeightEntry() -> (weight: Int64, reps: Int64)? {
        guard let exercise = setGroup.exercise,
              let best = exercise.currentBestSet(for: .weight)
        else { return nil }
        let entry = best.maxWeightEntry(for: exercise)
        guard entry.weight > 0 else { return nil }
        return (entry.weight, entry.repetitions)
    }

    private func bestRepsEntry() -> (reps: Int64, weight: Int64)? {
        guard let exercise = setGroup.exercise,
              let best = exercise.currentBestSet(for: .repetitions)
        else { return nil }
        let entry = best.maxRepetitionsEntry(for: exercise)
        guard entry.repetitions > 0 else { return nil }
        return (entry.repetitions, entry.weight)
    }

    // MARK: - Record detection (session vs all-time — intentionally NOT the current-best window)

    /// This set group's best — what the *session* achieved, used only to detect records.
    private func setGroupBest(_ metric: ExercisePrimaryMetric) -> Int {
        guard let exercise = setGroup.exercise else { return 0 }
        switch metric {
        case .estimatedOneRepMax: return setGroup.sets.map { $0.estimatedOneRepMax(for: exercise) }.max() ?? 0
        case .weight: return setGroup.sets.map { $0.maximum(.weight, for: exercise) }.max() ?? 0
        case .repetitions: return setGroup.sets.map { $0.maximum(.repetitions, for: exercise) }.max() ?? 0
        }
    }

    /// Best value for `metric` across all *previous* sessions for this exercise — the bar a new
    /// record has to clear. Excludes the current workout.
    private func previousBest(_ metric: ExercisePrimaryMetric) -> Int {
        guard let exercise = setGroup.exercise else { return 0 }
        let priorSets = exercise.sets.filter { $0.workout != setGroup.workout }
        switch metric {
        case .estimatedOneRepMax: return priorSets.map { $0.estimatedOneRepMax(for: exercise) }.max() ?? 0
        case .weight: return priorSets.map { $0.maximum(.weight, for: exercise) }.max() ?? 0
        case .repetitions: return priorSets.map { $0.maximum(.repetitions, for: exercise) }.max() ?? 0
        }
    }

    /// True only while recording, when this set group beats every previous session on `metric`.
    /// Ties don't count — you have to exceed it.
    private func isPersonalRecord(_ metric: ExercisePrimaryMetric) -> Bool {
        guard setGroup.workout?.isCurrentWorkout == true else { return false }
        let current = setGroupBest(metric)
        return current > 0 && current > previousBest(metric)
    }

    /// Base values of every metric currently at a personal record, for the peek controller.
    private func prSnapshot() -> [ExercisePrimaryMetric: Int] {
        var snapshot: [ExercisePrimaryMetric: Int] = [:]
        for metric in ExercisePrimaryMetric.allCases where isPersonalRecord(metric) {
            snapshot[metric] = setGroupBest(metric)
        }
        return snapshot
    }

    /// Stable string that changes whenever any metric's record value changes — drives `onChange`.
    private var prSignature: String {
        ExercisePrimaryMetric.allCases
            .map { "\($0.rawValue):\(isPersonalRecord($0) ? setGroupBest($0) : 0)" }
            .joined(separator: "|")
    }

    /// One rendered form of the badge value.
    enum MetricDisplay {
        case e1RM(grams: Int)
        case pair(reps: Int, weightGrams: Int64, emphasize: Emphasis)
        case empty

        enum Emphasis { case reps, weight }
    }
}

/// Drives the personal-best "peek": when a non-primary metric sets a record, show it briefly (with a
/// success haptic) then roll back to the primary. Multiple fresh records are shown in turn. A manual
/// cycle cancels any peek and suppresses further peeks until the *next* record arrives.
@MainActor
private final class MetricPeekController: ObservableObject {
    static let rollAnimation: Animation = .spring(response: 0.4, dampingFraction: 0.85)

    /// How long each record is shown before rolling on.
    private let peekDuration: Double = 3.5

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

/// Shown when the metric badge is tapped: a switcher, this set group's current value for the selected
/// metric, a compact progression chart (same design as the exercise-detail tiles), an explanation, and
/// the "scroll for other metrics" hint. Shared by the badge's own popover (most screens) and the
/// recorder, which presents it as a sheet from its persistent exercise sheet so that sheet survives.
struct MetricInfoPanel: View {
    @ObservedObject var setGroup: WorkoutSetGroup
    @State private var selectedMetric: ExercisePrimaryMetric

    private let metrics = ExercisePrimaryMetric.allCases

    init(setGroup: WorkoutSetGroup) {
        _setGroup = ObservedObject(wrappedValue: setGroup)
        _selectedMetric = State(initialValue: setGroup.exercise?.primaryMetric ?? .estimatedOneRepMax)
    }

    var body: some View {
        let color = setGroup.exercise?.muscleGroup?.color ?? .accentColor
        return VStack(alignment: .leading, spacing: 14) {
            Picker("", selection: Binding(get: { selectedMetric }, set: { setMetric($0) })) {
                ForEach(metrics, id: \.self) { metric in
                    Text(metric.title).tag(metric)
                }
            }
            .pickerStyle(.segmented)

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(NSLocalizedString("currentBest", comment: ""))
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    UnitView(
                        value: panelValue(for: selectedMetric),
                        unit: panelUnit(for: selectedMetric),
                        configuration: .large
                    )
                    .foregroundStyle(color.gradient)
                }
                Spacer(minLength: 0)
                metricChart(for: selectedMetric, color: color)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(explanation(for: selectedMetric))
                Text(NSLocalizedString("currentBestInfo", comment: ""))
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Label(NSLocalizedString("swipeForMetrics", comment: ""), systemImage: "hand.draw")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    /// Persists the chosen metric (per exercise). The badge observes `UserDefaults.didChangeNotification`
    /// and re-syncs its wheel, so this is reflected on the badge even when the panel is a separate sheet.
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
        }
    }

    // MARK: - Value

    /// The exercise's current best for `metric` (same window as the badge), formatted for display.
    private func panelValue(for metric: ExercisePrimaryMetric) -> String {
        guard let exercise = setGroup.exercise,
              let best = exercise.currentBestSet(for: metric)
        else { return "––" }
        switch metric {
        case .estimatedOneRepMax: return formatEstimatedOneRepMax(best.estimatedOneRepMax(for: exercise))
        case .weight: return formatWeightForDisplay(Int64(best.maximum(.weight, for: exercise)))
        case .repetitions: return String(best.maximum(.repetitions, for: exercise))
        }
    }

    private func panelUnit(for metric: ExercisePrimaryMetric) -> String {
        switch metric {
        case .estimatedOneRepMax, .weight: return WeightUnit.used.rawValue.uppercased()
        case .repetitions: return NSLocalizedString("reps", comment: "").uppercased()
        }
    }

    // MARK: - Progression chart

    private struct MetricPoint: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    private func metricBase(_ set: WorkoutSet, _ metric: ExercisePrimaryMetric, _ exercise: Exercise) -> Int {
        switch metric {
        case .estimatedOneRepMax: return set.estimatedOneRepMax(for: exercise)
        case .weight: return set.maximum(.weight, for: exercise)
        case .repetitions: return set.maximum(.repetitions, for: exercise)
        }
    }

    private func metricDisplayValue(_ base: Int, _ metric: ExercisePrimaryMetric) -> Double {
        switch metric {
        case .estimatedOneRepMax, .weight: return convertWeightForDisplayingDecimal(base)
        case .repetitions: return Double(base)
        }
    }

    /// Daily-max points for `metric` across all of this exercise's sessions, oldest → newest.
    private func metricPoints(for metric: ExercisePrimaryMetric) -> [MetricPoint] {
        guard let exercise = setGroup.exercise else { return [] }
        let grouped = Dictionary(grouping: exercise.sets) {
            Calendar.current.startOfDay(for: $0.workout?.date ?? .now)
        }
        return grouped.compactMap { _, sets -> MetricPoint? in
            guard let best = sets.max(by: { metricBase($0, metric, exercise) < metricBase($1, metric, exercise) })
            else { return nil }
            let base = metricBase(best, metric, exercise)
            guard base > 0, let date = best.workout?.date else { return nil }
            return MetricPoint(date: date, value: metricDisplayValue(base, metric))
        }
        .sorted { $0.date < $1.date }
    }

    /// Chart window == current-best window, so the chart's visible peak IS the headline value.
    private var chartStartDate: Date {
        Exercise.currentBestWindowStart
    }

    /// Trailing edge of the x-domain, pushed ~2 days past today so the latest point's symbol clears
    /// the right edge — the chart is `.clipped()` with no trailing fade, and the recorder's last point
    /// is always today, so without this margin it gets sliced in half. (The volume tile does the same
    /// by extending to `endOfWeek`.)
    private var chartEndDate: Date {
        Calendar.current.date(byAdding: .day, value: 2, to: .now) ?? .now
    }

    /// Compact progression chart matching the exercise-detail tiles (line + area, muscle-group
    /// colour, faded leading edge, hidden axes). Empty when the metric has no history.
    @ViewBuilder
    private func metricChart(for metric: ExercisePrimaryMetric, color: Color) -> some View {
        let points = metricPoints(for: metric)
        let maxValue = points.map(\.value).max() ?? 1
        Chart {
            if let first = points.first {
                LineMark(x: .value("Date", Date.distantPast, unit: .day), y: .value("Value", first.value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(color.gradient)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            ForEach(points) { point in
                LineMark(x: .value("Date", point.date, unit: .day), y: .value("Value", point.value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(color.gradient)
                    .lineStyle(StrokeStyle(lineWidth: 3))
                    .symbol {
                        Circle()
                            .frame(width: 6, height: 6)
                            .foregroundStyle(color.gradient)
                            .overlay { Circle().frame(width: 2, height: 2).foregroundStyle(Color.black) }
                    }
                AreaMark(x: .value("Date", point.date, unit: .day), y: .value("Value", point.value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Gradient(colors: [color.opacity(0.3), color.opacity(0.1), color.opacity(0)]))
            }
            if let last = points.last, !Calendar.current.isDateInToday(last.date) {
                RuleMark(xStart: .value("Start", last.date), xEnd: .value("End", Date()), y: .value("Value", last.value))
                    .foregroundStyle(color.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, dash: [3, 6]))
            }
        }
        .chartXScale(domain: chartStartDate ... chartEndDate)
        .chartYScale(domain: 0 ... max(maxValue * 1.15, 1))
        .chartXAxis {}
        .chartYAxis {}
        .frame(width: 124, height: 60)
        .clipped()
        .mask(
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .black, location: 0.12),
                    .init(color: .black, location: 1.0),
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }
}

// MARK: - Metric info request (environment)

private struct MetricInfoRequestKey: EnvironmentKey {
    static let defaultValue: ((WorkoutSetGroup, CGRect) -> Void)? = nil
}

extension EnvironmentValues {
    /// Set by the workout recorder so a metric-badge tap presents the info popover from the
    /// recorder's persistent sheet context, anchored at the badge's global frame — a popover
    /// presented from the badge itself (which lives behind that sheet) tears the sheet down. Absent
    /// elsewhere, where the badge presents its own popover.
    var metricInfoRequest: ((WorkoutSetGroup, CGRect) -> Void)? {
        get { self[MetricInfoRequestKey.self] }
        set { self[MetricInfoRequestKey.self] = newValue }
    }
}
