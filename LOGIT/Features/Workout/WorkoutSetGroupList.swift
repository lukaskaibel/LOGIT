//
//  WorkoutSetGroupList.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 29.07.23.
//

import SwiftUI

struct WorkoutSetGroupList: View {
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

    // MARK: - State

    @State var isReordering = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            ForEach(workout.setGroups) { setGroup in
                VStack(spacing: 0) {
                    WorkoutSetGroupCell(
                        setGroup: setGroup,
                        focusedIntegerFieldIndex: $focusedIntegerFieldIndex,
                        isReordering: $isReordering,
                        supplementaryText: nil,
                        showDetailAsSheet: showDetailAsSheet,
                        onTapRestDuration: onTapRestDuration,
                        onReorderSetGroups: onReorderSetGroups,
                        onTapPreviousSet: onTapPreviousSet,
                        onTapExerciseName: onTapExerciseName
                    )
                    .shadow(color: .black.opacity(reduceShadow ? 0.5 : 1.0), radius: 5)
                    .zIndex(1)
                    setGroupConnector(for: setGroup)
                }
                .transition(.scale)
                .id(setGroup)
            }
        }
        .animation(.interactiveSpring(), value: workout.setGroups.count)
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
