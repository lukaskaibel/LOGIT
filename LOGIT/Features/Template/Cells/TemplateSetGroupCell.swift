//
//  TemplateSetGroupCell.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 30.07.23.
//

import CoreData
import SwiftUI

/// A template's set group, mirroring `WorkoutSetGroupCell`: a superset renders containerless as
/// one full-size card per exercise paged horizontally, every card wears the thread's index
/// bulge, and the rails fork/merge across the pages. Workout-only concepts (metric badges,
/// previous-set references, the session note) have no template counterpart and are absent.
struct TemplateSetGroupCell: View {
    // MARK: - Environment

    @Environment(\.canEdit) var canEdit: Bool
    @EnvironmentObject var database: Database

    // MARK: - Parameters

    @ObservedObject var setGroup: TemplateSetGroup

    @Binding var focusedIntegerFieldIndex: IntegerField.Index?
    @Binding var sheetType: TemplateEditorScreen.SheetType?
    @Binding var isReordering: Bool

    let supplementaryText: String?
    var showDetailAsSheet: Bool = false
    /// Position of this group in the template, passed by the list so a structural change
    /// elsewhere refreshes this cell's bulge label. Nil derives it from the template.
    var indexInTemplate: Int? = nil
    /// Total number of set groups, for the "2 of 5" bulge label. Nil derives it.
    var groupCount: Int? = nil
    var onTapRestDuration: ((TemplateSet) -> Void)? = nil

    // MARK: - State

    @State private var isSelectingPrimaryExercise = false
    @State private var primaryExerciseSelectionSheetDetend: PresentationDetent? = .large
    @State private var isSelectingSecondaryExercise = false
    /// Which exercise's page the superset pager is snapped to (objectID; nil = first page).
    /// Also driven programmatically when keyboard focus lands on the partner's fields.
    @State private var pagedExerciseID: NSManagedObjectID?

    // MARK: - Body

    var body: some View {
        content
            .sheet(isPresented: $isSelectingPrimaryExercise) {
                NavigationStack {
                    ExerciseSelectionScreen(
                        selectedExercise: setGroup.exercise,
                        setExercise: {
                            setGroup.exercise = $0
                            isSelectingPrimaryExercise = false
                        },
                        forSecondary: false,
                        currentWorkoutExercises: [],
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
                        currentWorkoutExercises: [],
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
    }

    /// A superset with both exercises chosen renders as containerless side-by-side pages; while
    /// reordering (compact header row) or before the second exercise is picked it falls back to
    /// the classic single card, whose header still offers the "select exercise" entry point.
    @ViewBuilder
    private var content: some View {
        if isPagedSuperset {
            supersetPager
        } else {
            standardCard
        }
    }

    private var isPagedSuperset: Bool {
        setGroup.setType == .superSet
            && setGroup.exercise != nil
            && setGroup.secondaryExercise != nil
            && !isReordering
    }

    // MARK: - Index bulge

    private var resolvedIndexInTemplate: Int? {
        indexInTemplate ?? setGroup.workout?.setGroups.firstIndex(of: setGroup)
    }

    private var resolvedGroupCount: Int {
        groupCount ?? setGroup.workout?.setGroups.count ?? 0
    }

    private var bulgeLabel: String? {
        SetGroupThread.indexLabel(index: resolvedIndexInTemplate, count: resolvedGroupCount)
    }

    /// The merge rail is drawn under the pages only when another group follows, so the
    /// converged line has somewhere to continue to (the list draws the trunk between cells).
    private var showsMergeRail: Bool {
        guard let index = resolvedIndexInTemplate else { return false }
        return index < resolvedGroupCount - 1
    }

    /// The fork rail only when a group precedes — a floating rail above the first group with
    /// nothing feeding it just looks broken.
    private var showsForkRail: Bool {
        (resolvedIndexInTemplate ?? 0) > 0
    }

    // MARK: - Standard card

    private var standardCard: some View {
        standardCardBody
            .padding(.bottom, canEdit || isReordering ? CELL_PADDING : CELL_PADDING / 2)
            .background(
                RoundedRectangle(cornerRadius: 30)
                    .fill(.shadow(.inner(color: .white.opacity(0.04), radius: 3)))
                    .foregroundStyle(Color.secondaryBackground)
            )
            .cornerRadius(30)
            .bulgeSocket(label: bulgeLabel)
    }

    private var standardCardBody: some View {
        VStack(spacing: CELL_PADDING) {
            header
            if !isReordering {
                VStack(spacing: CELL_PADDING) {
                    VStack(spacing: CELL_SPACING) {
                        ReorderableForEach(
                            $setGroup.sets,
                            canReorder: false,
                            isReordering: .constant(false)
                        ) { templateSet in
                            VStack(spacing: CELL_SPACING) {
                                setCell(for: templateSet, visibleExercise: nil)
                                if !isLastSet(templateSet), templateSet.restDurationSeconds > 0 {
                                    restLabel(for: templateSet)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, CELL_PADDING / 2)
                    .animation(.interactiveSpring(), value: setGroup.sets)
                    if canEdit {
                        controls(for: setGroup.exercise)
                            .padding(.horizontal, CELL_PADDING)
                    }
                }
            }
        }
    }

    // MARK: - Superset pager

    /// The containerless superset: one full-size card per exercise, paged horizontally, each
    /// with its own bulge socket and add-set controls. The thread's rails ride in the bands
    /// above and below the pages and scroll WITH them, so the fixed trunk the list draws
    /// between cells always meets a rail at a right angle, whatever the scroll position.
    private var supersetPager: some View {
        let exercises = [setGroup.exercise, setGroup.secondaryExercise].compactMap { $0 }
        return ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: SetGroupThread.pageSpacing) {
                ForEach(exercises, id: \.objectID) { exercise in
                    TemplateSupersetExercisePage(
                        setGroup: setGroup,
                        exercise: exercise,
                        isPrimaryPage: exercise == setGroup.exercise,
                        bulgeLabel: bulgeLabel,
                        focusedIntegerFieldIndex: $focusedIntegerFieldIndex,
                        supplementaryText: supplementaryText,
                        showDetailAsSheet: showDetailAsSheet,
                        onTapRestDuration: onTapRestDuration,
                        groupMenu: AnyView(menu)
                    )
                    .containerRelativeFrame(.horizontal) { length, _ in
                        max(length - SetGroupThread.pageInset * 2, 100)
                    }
                }
            }
            .scrollTargetLayout()
            .supersetThreadRails(
                pageCount: exercises.count,
                showsFork: showsForkRail,
                showsMerge: showsMergeRail
            )
        }
        // No content margins: the snapped first page sits flush with the leading edge (and the
        // last page, clamped at the scroll bound, flush with the trailing edge) exactly like
        // every non-superset cell — see `WorkoutSetGroupCell.supersetPager`.
        .scrollTargetBehavior(.viewAligned)
        .scrollClipDisabled()
        .scrollIndicators(.hidden)
        .scrollPosition(id: $pagedExerciseID)
        .onChange(of: focusedIntegerFieldIndex) { _, newValue in
            autopageIfNeeded(for: newValue, exercises: exercises)
        }
    }

    /// Keyboard next/previous walks a set's entries, which alternate exercises in a superset —
    /// when focus lands on a field whose entry belongs to the other exercise, the pager follows
    /// so the focused field is never on an off-screen page.
    private func autopageIfNeeded(for index: IntegerField.Index?, exercises: [Exercise]) {
        guard let index,
              let templateSet = setGroup.sets.first(where: { $0.id == index.setID }),
              templateSet.entries.indices.contains(index.secondary),
              let owner = templateSet.owningExercise(of: templateSet.entries[index.secondary])
        else { return }
        let currentID = pagedExerciseID ?? exercises.first?.objectID
        guard owner.objectID != currentID else { return }
        withAnimation(.snappy) { pagedExerciseID = owner.objectID }
    }

    // MARK: - Supporting Views

    /// One set row, optionally restricted to a single exercise's entries (superset pages).
    fileprivate func setCell(for templateSet: TemplateSet, visibleExercise: Exercise?) -> some View {
        TemplateSetCell(
            templateSet: templateSet,
            focusedIntegerFieldIndex: $focusedIntegerFieldIndex,
            visibleExercise: visibleExercise,
            onEditRestDuration: onTapRestDuration.map { callback in
                { callback(templateSet) }
            }
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
                database.delete(templateSet)
            }
        }
    }

    /// A static, tappable rest indicator shown between two sets (mirrors the recorder's
    /// `RestTimerBetweenSetsView`, but without the live chronograph since templates don't run a timer).
    fileprivate func restLabel(for templateSet: TemplateSet) -> some View {
        let label = RestDurationLabel(
            seconds: templateSet.restDurationSeconds,
            foregroundColor: .secondary,
            iconName: "timer",
            textFont: .caption.weight(.semibold),
            iconFont: .caption.weight(.semibold)
        )
        return Group {
            if let onTapRestDuration {
                Button {
                    onTapRestDuration(templateSet)
                } label: {
                    label
                }
                .buttonStyle(.plain)
            } else {
                label
            }
        }
    }

    private func isLastSet(_ templateSet: TemplateSet) -> Bool {
        setGroup.sets.last == templateSet
    }

    /// Duplicate-last-set, add-set and the group menu, tinted by the page's own exercise.
    fileprivate func controls(for exercise: Exercise?) -> some View {
        HStack(spacing: 8) {
            Button {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                withAnimation(.interactiveSpring()) {
                    database.duplicateLastSet(from: setGroup)
                }
            } label: {
                Image(systemName: "plus.square.on.square")
                    .foregroundStyle((exercise?.muscleGroup?.color ?? .accentColor).gradient)
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .padding(15)
                    .background(Color.accentColor.secondaryTranslucentBackground)
                    .clipShape(Capsule())
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
                .foregroundStyle((exercise?.muscleGroup?.color ?? .accentColor).gradient)
                .font(.system(.body, design: .rounded, weight: .bold))
                .padding(.vertical, 15)
                .frame(maxWidth: .infinity)
                .background(Color.accentColor.secondaryTranslucentBackground)
                .clipShape(Capsule())
            }
            menu
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    ExerciseHeader(
                        exercise: setGroup.exercise,
                        secondaryExercise: setGroup.secondaryExercise,
                        noExerciseAction: { isSelectingPrimaryExercise = true },
                        noSecondaryExerciseAction: { isSelectingSecondaryExercise = true },
                        isSuperSet: setGroup.setType == .superSet,
                        navigationToDetailEnabled: true,
                        showDetailAsSheet: showDetailAsSheet
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
        }
        .padding([.top, .horizontal], CELL_PADDING)
    }

    // MARK: - Supporting Views

    fileprivate var menu: some View {
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
                    database.convertSetGroupToStandardSets(setGroup)
                } label: {
                    Label(
                        NSLocalizedString("standard", comment: ""),
                        systemImage: setGroup.setType == .standard ? "checkmark" : ""
                    )
                }
                Button {
                    database.convertSetGroupToSuperSet(setGroup)
                    isSelectingSecondaryExercise = true
                } label: {
                    Label(
                        NSLocalizedString("superSet", comment: ""),
                        systemImage: setGroup.setType == .superSet ? "checkmark" : ""
                    )
                }
                Button {
                    database.convertSetGroupToDropSets(setGroup)
                } label: {
                    Label(
                        NSLocalizedString("dropSet", comment: ""),
                        systemImage: setGroup.setType == .dropSet ? "checkmark" : ""
                    )
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
                            Label(
                                type.title,
                                systemImage: setGroup.measurementType == type ? "checkmark" : ""
                            )
                        }
                    }
                } header: {
                    Text(NSLocalizedString("measurementType", comment: ""))
                }
                // The distance scale is the user's choice per exercise (km vs m, mi vs yd) —
                // distances are stored in meters regardless, so switching only changes how
                // they're shown and entered, everywhere this exercise appears.
                if setGroup.measurementType.usesDistance, let exercise = setGroup.exercise {
                    Section {
                        ForEach(SetMeasurementType.DistanceStyle.allCases, id: \.self) { style in
                            Button {
                                exercise.distanceStyle = style
                            } label: {
                                Label(
                                    distanceStyleTitle(for: style),
                                    systemImage: setGroup.measurementType.distanceStyle(for: exercise) == style
                                        ? "checkmark" : ""
                                )
                            }
                        }
                    } header: {
                        Text(NSLocalizedString("distanceUnit", comment: ""))
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
}

// MARK: - Superset exercise page

/// One exercise's card inside the template superset pager: its own bulge socket, header, set
/// column (only this exercise's entry per set) and add-set controls. The group-level menu is
/// built by the cell (it owns the exercise-selection state) and passed in.
private struct TemplateSupersetExercisePage: View {
    @Environment(\.canEdit) var canEdit: Bool
    @EnvironmentObject var database: Database

    @ObservedObject var setGroup: TemplateSetGroup
    let exercise: Exercise
    let isPrimaryPage: Bool
    let bulgeLabel: String?
    @Binding var focusedIntegerFieldIndex: IntegerField.Index?
    let supplementaryText: String?
    let showDetailAsSheet: Bool
    let onTapRestDuration: ((TemplateSet) -> Void)?
    let groupMenu: AnyView

    var body: some View {
        card
            .bulgeSocket(label: bulgeLabel)
            .accentColor(exercise.muscleGroup?.color ?? .accentColor)
    }

    private var card: some View {
        VStack(spacing: CELL_PADDING) {
            header
                .padding([.top, .horizontal], CELL_PADDING)
            VStack(spacing: CELL_SPACING) {
                ForEach(setGroup.sets, id: \.objectID) { templateSet in
                    VStack(spacing: CELL_SPACING) {
                        TemplateSetCell(
                            templateSet: templateSet,
                            focusedIntegerFieldIndex: $focusedIntegerFieldIndex,
                            visibleExercise: exercise,
                            onEditRestDuration: onTapRestDuration.map { callback in
                                { callback(templateSet) }
                            }
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
                                database.delete(templateSet)
                            }
                        }
                        if setGroup.sets.last != templateSet, templateSet.restDurationSeconds > 0 {
                            restLabel(for: templateSet)
                        }
                    }
                }
            }
            .padding(.horizontal, CELL_PADDING / 2)
            .animation(.interactiveSpring(), value: setGroup.sets)
            if canEdit {
                controls
                    .padding(.horizontal, CELL_PADDING)
            }
        }
        .padding(.bottom, canEdit ? CELL_PADDING : CELL_PADDING / 2)
        .background(
            RoundedRectangle(cornerRadius: 30)
                .fill(.shadow(.inner(color: .white.opacity(0.04), radius: 3)))
                .foregroundStyle(Color.secondaryBackground)
        )
        .cornerRadius(30)
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                ExerciseHeader(
                    exercise: exercise,
                    secondaryExercise: nil,
                    noExerciseAction: {},
                    noSecondaryExerciseAction: nil,
                    isSuperSet: false,
                    navigationToDetailEnabled: true,
                    showDetailAsSheet: showDetailAsSheet
                )
                HStack {
                    Text(exercise.muscleGroup?.description ?? "")
                        .foregroundColor(exercise.muscleGroup?.color ?? .accentColor)
                    Spacer()
                    if isPrimaryPage, let supplementaryText {
                        Text(supplementaryText)
                            .foregroundStyle(.secondary)
                            .fontWeight(.medium)
                    }
                }
                .font(.system(.footnote, design: .rounded, weight: .bold))
            }
            Spacer()
        }
    }

    private func restLabel(for templateSet: TemplateSet) -> some View {
        let label = RestDurationLabel(
            seconds: templateSet.restDurationSeconds,
            foregroundColor: .secondary,
            iconName: "timer",
            textFont: .caption.weight(.semibold),
            iconFont: .caption.weight(.semibold)
        )
        return Group {
            if let onTapRestDuration {
                Button {
                    onTapRestDuration(templateSet)
                } label: {
                    label
                }
                .buttonStyle(.plain)
            } else {
                label
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                withAnimation(.interactiveSpring()) {
                    database.duplicateLastSet(from: setGroup)
                }
            } label: {
                Image(systemName: "plus.square.on.square")
                    .foregroundStyle((exercise.muscleGroup?.color ?? .accentColor).gradient)
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .padding(15)
                    .background(Color.accentColor.secondaryTranslucentBackground)
                    .clipShape(Capsule())
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
                .foregroundStyle((exercise.muscleGroup?.color ?? .accentColor).gradient)
                .font(.system(.body, design: .rounded, weight: .bold))
                .padding(.vertical, 15)
                .frame(maxWidth: .infinity)
                .background(Color.accentColor.secondaryTranslucentBackground)
                .clipShape(Capsule())
            }
            groupMenu
        }
    }
}

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(
                        Array(database.testTemplate.setGroups.enumerated()),
                        id: \.element.objectID
                    ) { index, setGroup in
                        VStack(spacing: 0) {
                            TemplateSetGroupCell(
                                setGroup: setGroup,
                                focusedIntegerFieldIndex: .constant(nil),
                                sheetType: .constant(nil),
                                isReordering: .constant(false),
                                supplementaryText: nil,
                                indexInTemplate: index,
                                groupCount: database.testTemplate.setGroups.count
                            )
                            if index < database.testTemplate.setGroups.count - 1 {
                                SetGroupTrunk()
                            }
                        }
                        .setGroupRowStyle(
                            index: index,
                            count: database.testTemplate.setGroups.count
                        )
                    }
                }
                .padding()
            }
        }
    }
}

struct TemplateSetGroupCell_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
    }
}
