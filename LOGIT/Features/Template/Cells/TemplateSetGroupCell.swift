//
//  TemplateSetGroupCell.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 30.07.23.
//

import SwiftUI

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
    var onTapRestDuration: ((TemplateSet) -> Void)? = nil

    // MARK: - State

    @State private var isSelectingPrimaryExercise = false
    @State private var primaryExerciseSelectionSheetDetend: PresentationDetent? = .large
    @State private var isSelectingSecondaryExercise = false

    // MARK: - Body

    var body: some View {
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
                                TemplateSetCell(
                                    templateSet: templateSet,
                                    focusedIntegerFieldIndex: $focusedIntegerFieldIndex,
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
                                if !isLastSet(templateSet), templateSet.restDurationSeconds > 0 {
                                    restLabel(for: templateSet)
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
                    supersetPrimaryExercise: nil,
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

    // MARK: - Supporting Views

    /// A static, tappable rest indicator shown between two sets (mirrors the recorder's
    /// `RestTimerBetweenSetsView`, but without the live chronograph since templates don't run a timer).
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

    private func isLastSet(_ templateSet: TemplateSet) -> Bool {
        setGroup.sets.last == templateSet
    }

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

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack {
                    TemplateSetGroupCell(
                        setGroup: database.testTemplate.setGroups.first!,
                        focusedIntegerFieldIndex: .constant(nil),
                        sheetType: .constant(nil),
                        isReordering: .constant(false),
                        supplementaryText: nil
                    )
                    .padding(CELL_PADDING)
                    .tileStyle()
                    .padding()
                    TemplateSetGroupCell(
                        setGroup: database.testTemplate.setGroups.first!,
                        focusedIntegerFieldIndex: .constant(nil),
                        sheetType: .constant(nil),
                        isReordering: .constant(true),
                        supplementaryText: "1 / 3"
                    )
                    .padding(CELL_PADDING)
                    .tileStyle()
                    .padding()
                    TemplateSetGroupCell(
                        setGroup: database.testTemplate.setGroups.first!,
                        focusedIntegerFieldIndex: .constant(nil),
                        sheetType: .constant(nil),
                        isReordering: .constant(false),
                        supplementaryText: "1 / 3"
                    )
                    .padding(CELL_PADDING)
                    .tileStyle()
                    .padding()
                    .canEdit(false)
                }
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
