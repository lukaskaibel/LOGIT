//
//  RestTimerBetweenSetsView.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 12.03.26.
//

import Combine
import SwiftUI

/// The workout recorder's rest clock, for the views in its set list that read it.
///
/// Handed down through the environment as plain references rather than observed objects: the
/// recorder and the chronograph publish on every rest start, stop, pause and adjustment, and each
/// set row observing them re-rendered the whole list on each of those — for a timer that concerns
/// one row. The views here subscribe to exactly the change they show instead.
struct RecorderRestContext: Equatable {
    let workoutRecorder: WorkoutRecorder
    let chronograph: Chronograph

    static func == (lhs: RecorderRestContext, rhs: RecorderRestContext) -> Bool {
        lhs.workoutRecorder === rhs.workoutRecorder && lhs.chronograph === rhs.chronograph
    }

    /// Whether `workoutSet`'s rest is the one on the clock, re-announced as the rest moves on.
    func restIsActive(for workoutSet: WorkoutSet) -> AnyPublisher<Bool, Never> {
        workoutRecorder.$activeRestTimerSet
            .combineLatest(chronograph.$status)
            .map { activeSet, status in
                activeSet?.objectID == workoutSet.objectID && (status == .running || status == .paused)
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
}

private struct RecorderRestContextKey: EnvironmentKey {
    static let defaultValue: RecorderRestContext? = nil
}

extension EnvironmentValues {
    /// Set by the recorder; nil everywhere a workout isn't being recorded.
    var recorderRestContext: RecorderRestContext? {
        get { self[RecorderRestContextKey.self] }
        set { self[RecorderRestContextKey.self] = newValue }
    }
}

/// Shows a live countdown or a static rest label between sets during workout recording.
struct RestTimerBetweenSetsView: View {
    @Environment(\.recorderRestContext) private var restContext

    @ObservedObject var workoutSet: WorkoutSet
    var showPendingRestInTertiary: Bool = false
    var onTapActiveTimer: (() -> Void)? = nil
    var onTapRestDuration: (() -> Void)? = nil

    @State private var isTimerActiveForThisSet = false

    var body: some View {
        Group {
            if isTimerActiveForThisSet, let restContext {
                activeTimerLabel(chronograph: restContext.chronograph)
            } else if workoutSet.restDurationSeconds > 0 {
                staticRestLabel
            }
        }
        .onReceive(restContext?.restIsActive(for: workoutSet) ?? Just(false).eraseToAnyPublisher()) { isActive in
            if isTimerActiveForThisSet != isActive { isTimerActiveForThisSet = isActive }
        }
    }

    @ViewBuilder
    private var staticRestLabel: some View {
        let label = RestDurationLabel(
            seconds: workoutSet.restDurationSeconds,
            foregroundColor: pendingRestColor,
            iconName: "timer",
            textFont: .caption.weight(.semibold),
            iconFont: .caption.weight(.semibold)
        )

        if let onTapRestDuration {
            Button(action: onTapRestDuration) {
                label
            }
            .buttonStyle(.plain)
        } else {
            label
        }
    }

    private var activeTimerTint: Color {
        workoutSet.exercise?.muscleGroup?.color ?? .accentColor
    }

    private var pendingRestColor: Color {
        showPendingRestInTertiary && !workoutSet.hasEntry ? .tertiaryLabel : .secondary
    }

    @ViewBuilder
    private func activeTimerLabel(chronograph: Chronograph) -> some View {
        let label = ChronographView(chronograph: chronograph) { seconds in
            HStack(spacing: 4) {
                let displayedSeconds = max(0, Int(seconds.rounded(.down)))
                Image(systemName: chronograph.mode == .timer ? "timer" : "stopwatch")
                    .font(.caption.weight(.semibold))
                Text(restTimeString(seconds: displayedSeconds))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.18), value: displayedSeconds)
            }
            .foregroundStyle(activeTimerTint)
        }

        if let onTapActiveTimer {
            Button(action: onTapActiveTimer) {
                label
            }
            .buttonStyle(.plain)
        } else {
            label
        }
    }
}
