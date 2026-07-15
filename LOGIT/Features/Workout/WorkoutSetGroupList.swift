//
//  WorkoutSetGroupList.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 29.07.23.
//

import SwiftUI

struct WorkoutSetGroupList: View, Equatable {
    // MARK: - Environment

    @EnvironmentObject var database: Database

    // MARK: - Parameters

    @ObservedObject var workout: Workout
    @Binding var focusedIntegerFieldIndex: IntegerField.Index?
    let canReorder: Bool
    var reduceShadow: Bool = false
    var showDetailAsSheet: Bool = false
    var onTapRestDuration: ((WorkoutSet) -> Void)? = nil
    var onReorderSetGroups: (() -> Void)? = nil
    var onTapPreviousSet: ((Exercise) -> Void)? = nil
    var onTapExerciseName: ((Exercise) -> Void)? = nil
    /// Recorder only: routes a metric-badge tap up so the popover is presented from the
    /// recorder's persistent sheet (see `MetricBadgeView.onTapBadge`).
    var onTapMetricBadge: ((WorkoutSetGroup, CGRect) -> Void)? = nil

    // MARK: - State

    @State var isReordering = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            ForEach(indexedSetGroups, id: \.setGroup.id) { entry in
                VStack(spacing: 0) {
                    WorkoutSetGroupCell(
                        setGroup: entry.setGroup,
                        focusedIntegerFieldIndex: $focusedIntegerFieldIndex,
                        isReordering: $isReordering,
                        supplementaryText: nil,
                        showDetailAsSheet: showDetailAsSheet,
                        isFieldFocused: focusedIntegerFieldIndex != nil,
                        indexInWorkout: entry.index,
                        firstSetIndexInWorkout: entry.firstSetIndex,
                        onTapRestDuration: onTapRestDuration,
                        onReorderSetGroups: onReorderSetGroups,
                        onTapPreviousSet: onTapPreviousSet,
                        onTapExerciseName: onTapExerciseName,
                        onTapMetricBadge: onTapMetricBadge
                    )
                    .shadow(color: .black.opacity(reduceShadow ? 0.5 : 1.0), radius: 5)
                    .zIndex(1)
                    setGroupConnector(for: entry.setGroup)
                }
                .transition(.scale)
                .id(entry.setGroup)
            }
        }
        .animation(.interactiveSpring(), value: workout.setGroups.count)
    }

    /// Each set group with its position and the flat index of its first set. Computed here and
    /// passed into the cells because the cells' `Equatable` skipping needs structural changes to
    /// be visible in their inputs: the header number and the set cells' focus indices depend on
    /// what comes *before* a group, so deleting/reordering/resizing an earlier group must
    /// re-render the ones after it even though their own set group didn't change.
    private var indexedSetGroups: [(index: Int, firstSetIndex: Int, setGroup: WorkoutSetGroup)] {
        var firstSetIndex = 0
        return workout.setGroups.enumerated().map { index, setGroup in
            defer { firstSetIndex += setGroup.sets.count }
            return (index: index, firstSetIndex: firstSetIndex, setGroup: setGroup)
        }
    }

    @ViewBuilder
    private func setGroupConnector(for setGroup: WorkoutSetGroup) -> some View {
        let lastSet = setGroup.sets.last
        let hasRest = lastSet?.restDurationSeconds ?? 0 > 0
        let isLast = workout.setGroups.last == setGroup

        if isLast {
            if hasRest, let lastSet {
                restCapsule(for: lastSet)
            }
        } else {
            if hasRest, let lastSet {
                restCapsule(for: lastSet)
                    .padding(.vertical, SECTION_SPACING / 2)
                    .background(
                        Rectangle()
                            .foregroundStyle(.secondary)
                            .frame(width: 3)
                    )
            } else {
                Rectangle()
                    .foregroundStyle(.secondary)
                    .frame(width: 3, height: SECTION_SPACING)
            }
        }
    }

    /// Lets SwiftUI skip re-running the list body when a parent re-render didn't change its
    /// inputs (the recorder screen re-renders for progress, timer, and sheet reasons that don't
    /// concern the list). Ignores the callback closures (stable behavior across renders) and the
    /// focus binding — the list reads the binding's value in `body`, so focus changes re-render
    /// it through that dependency regardless of this comparison. Structural changes re-render
    /// through the `@ObservedObject workout`.
    static func == (lhs: WorkoutSetGroupList, rhs: WorkoutSetGroupList) -> Bool {
        lhs.workout === rhs.workout
            && lhs.canReorder == rhs.canReorder
            && lhs.reduceShadow == rhs.reduceShadow
            && lhs.showDetailAsSheet == rhs.showDetailAsSheet
    }

    private func restCapsule(for workoutSet: WorkoutSet) -> some View {
        RestDurationLabel(
            seconds: workoutSet.restDurationSeconds,
            iconName: "timer",
            textFont: .caption.weight(.semibold),
            iconFont: .caption.weight(.semibold)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.secondaryBackground)
        .clipShape(Capsule())
        .transition(.scale.animation(.interactiveSpring()))
        .onTapGesture {
            onTapRestDuration?(workoutSet)
        }
    }
}

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database

    var body: some View {
        WorkoutSetGroupList(
            workout: database.testWorkout,
            focusedIntegerFieldIndex: .constant(nil),
            canReorder: true
        )
    }
}

struct WorkoutSetGroupList_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            PreviewWrapperView()
                .padding()
        }
        .previewEnvironmentObjects()
    }
}
