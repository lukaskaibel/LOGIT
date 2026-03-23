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
    @EnvironmentObject private var chronograph: Chronograph
    @EnvironmentObject private var workoutRecorder: WorkoutRecorder

    // MARK: - Parameters

    @ObservedObject var workout: Workout
    @Binding var focusedIntegerFieldIndex: IntegerField.Index?
    let canReorder: Bool
    var reduceShadow: Bool = false
    var showDetailAsSheet: Bool = false
    var onTapActiveRest: ((WorkoutSet) -> Void)? = nil
    var onTapStaticRest: ((WorkoutSet) -> Void)? = nil

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
                        onTapActiveRest: onTapActiveRest,
                        onTapStaticRest: onTapStaticRest
                    )
                    .shadow(color: .black.opacity(reduceShadow ? 0.5 : 1.0), radius: 5)
                    .zIndex(1)
                    if workout.setGroups.last != setGroup {
                        separator(for: setGroup.sets.last)
                            .zIndex(0)
                    }
                }
                .transition(.scale)
                .id(setGroup)
            }
        }
        .animation(.interactiveSpring(), value: workout.setGroups.count)
    }

    @ViewBuilder
    private func separator(for workoutSet: WorkoutSet?) -> some View {
        let showsRestCapsule = workoutSet.map(shouldShowRestSeparator(for:)) ?? false
        Rectangle()
            .foregroundStyle(.secondary)
            .frame(width: 3, height: showsRestCapsule ? SECTION_SPACING + 14 : SECTION_SPACING)
            .overlay {
                if let workoutSet, showsRestCapsule {
                    RestTimerBetweenSetsView(
                        workoutSet: workoutSet,
                        onTapActiveTimer: {
                            onTapActiveRest?(workoutSet)
                        },
                        onTapRestDuration: {
                            onTapStaticRest?(workoutSet)
                        }
                    )
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.secondaryBackground)
                    .clipShape(Capsule())
                }
            }
    }

    private func shouldShowRestSeparator(for workoutSet: WorkoutSet) -> Bool {
        workoutSet.restDurationSeconds > 0
            || (
                workoutRecorder.activeRestTimerSet?.objectID == workoutSet.objectID
                    && (chronograph.status == .running || chronograph.status == .paused)
            )
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
