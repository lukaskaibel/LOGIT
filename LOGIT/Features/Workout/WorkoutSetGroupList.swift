//
//  WorkoutSetGroupList.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 29.07.23.
//

import SwiftUI

enum InterSetGroupRestDisplayState: Equatable {
    case hidden
    case staticRest(Int)
    case active(Chronograph.Mode)

    static func betweenSetGroups(
        for workoutSet: WorkoutSet?,
        activeRestTimerSet: WorkoutSet?,
        isChronographActive: Bool,
        chronographMode: Chronograph.Mode
    ) -> Self {
        guard let workoutSet else { return .hidden }

        if isChronographActive, activeRestTimerSet?.objectID == workoutSet.objectID {
            return .active(chronographMode)
        }

        if workoutSet.restDurationSeconds > 0 {
            return .staticRest(workoutSet.restDurationSeconds)
        }

        return .hidden
    }
}

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
    var activeRestTimerSet: WorkoutSet? = nil
    var isChronographActive: Bool = false
    var chronograph: Chronograph? = nil
    var chronographMode: Chronograph.Mode = .timer

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
                        onTapRestDuration: onTapRestDuration
                    )
                    .shadow(color: .black.opacity(reduceShadow ? 0.5 : 1.0), radius: 5)
                    .zIndex(1)
                    interSetGroupConnector(
                        after: setGroup,
                        showsTrailingLine: workout.setGroups.last != setGroup
                    )
                    .zIndex(0)
                }
                .transition(.scale)
                .id(setGroup)
            }
        }
        .animation(.interactiveSpring(), value: workout.setGroups.count)
    }

    @ViewBuilder
    private func interSetGroupConnector(
        after setGroup: WorkoutSetGroup,
        showsTrailingLine: Bool
    ) -> some View {
        let displayState = InterSetGroupRestDisplayState.betweenSetGroups(
            for: setGroup.sets.last,
            activeRestTimerSet: activeRestTimerSet,
            isChronographActive: isChronographActive,
            chronographMode: chronographMode
        )

        switch displayState {
        case .hidden:
            if showsTrailingLine {
                Rectangle()
                    .foregroundStyle(.secondary)
                    .frame(width: 3, height: SECTION_SPACING)
            }

        case let .staticRest(seconds):
            interSetGroupRestIndicator(showsTrailingLine: showsTrailingLine) {
                interSetGroupRestCapsule {
                    let label = RestDurationLabel(
                        seconds: seconds,
                        foregroundColor: .secondary,
                        iconName: "timer",
                        textFont: .caption.weight(.semibold),
                        iconFont: .caption.weight(.semibold)
                    )

                    if let lastSet = setGroup.sets.last, let onTapRestDuration {
                        Button {
                            onTapRestDuration(lastSet)
                        } label: {
                            label
                        }
                        .buttonStyle(.plain)
                    } else {
                        label
                    }
                }
            }

        case let .active(mode):
            interSetGroupRestIndicator(showsTrailingLine: showsTrailingLine) {
                interSetGroupRestCapsule {
                    if let chronograph {
                        ChronographView(chronograph: chronograph) { seconds in
                            HStack(spacing: 4) {
                                Image(systemName: mode == .timer ? "timer" : "stopwatch")
                                    .font(.caption.weight(.semibold))
                                Text(restTimeString(seconds: max(0, Int(seconds.rounded(.down)))))
                                    .font(.caption.weight(.semibold).monospacedDigit())
                            }
                            .foregroundStyle(setGroup.exercise?.muscleGroup?.color ?? .accentColor)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: mode == .timer ? "timer" : "stopwatch")
                                .font(.caption.weight(.semibold))
                            Text(restTimeString(seconds: 0))
                                .font(.caption.weight(.semibold).monospacedDigit())
                        }
                        .foregroundStyle(setGroup.exercise?.muscleGroup?.color ?? .accentColor)
                    }
                }
            }
        }
    }

    private func interSetGroupRestIndicator<Content: View>(
        showsTrailingLine: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 4) {
            Rectangle()
                .foregroundStyle(.secondary)
                .frame(width: 3, height: 6)
            content()
            if showsTrailingLine {
                Rectangle()
                    .foregroundStyle(.secondary)
                    .frame(width: 3, height: 6)
            }
        }
        .frame(minHeight: SECTION_SPACING + 10)
    }

    private func interSetGroupRestCapsule<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondaryBackground)
            .clipShape(Capsule())
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
