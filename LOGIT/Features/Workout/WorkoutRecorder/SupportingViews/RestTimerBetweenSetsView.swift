//
//  RestTimerBetweenSetsView.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 12.03.26.
//

import SwiftUI

/// Shows a live countdown or a static rest label between sets during workout recording.
struct RestTimerBetweenSetsView: View {
    @EnvironmentObject var chronograph: Chronograph
    @EnvironmentObject var workoutRecorder: WorkoutRecorder

    @ObservedObject var workoutSet: WorkoutSet
    var onTapActiveTimer: (() -> Void)? = nil
    var onTapRestDuration: (() -> Void)? = nil

    @ViewBuilder
    var body: some View {
        if isTimerActiveForThisSet {
            activeTimerLabel
        } else if workoutSet.restDurationSeconds > 0 {
            staticRestLabel
        }
    }

    @ViewBuilder
    private var staticRestLabel: some View {
        let label = RestDurationLabel(
            seconds: workoutSet.restDurationSeconds,
            foregroundColor: .secondary,
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

    private var isTimerActiveForThisSet: Bool {
        workoutRecorder.activeRestTimerSet?.objectID == workoutSet.objectID
            && (chronograph.status == .running || chronograph.status == .paused)
    }

    private var activeTimerTint: Color {
        workoutSet.exercise?.muscleGroup?.color ?? .accentColor
    }

    @ViewBuilder
    private var activeTimerLabel: some View {
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
