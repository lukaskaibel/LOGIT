//
//  WorkoutRecorderFloatingChronoTransportButton.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 23.03.26.
//

import SwiftUI

/// A round glass button beside the floating timer pill: pause while a rest runs, play and stop
/// while it is paused. The caller supplies the action — and with it the haptic — so the button
/// itself stays a plain piece of chrome.
struct WorkoutRecorderFloatingChronoTransportButton: View {
    @ObservedObject var workoutRecorder: WorkoutRecorder

    let systemImage: String
    let accessibilityLabel: String
    var isEnabled: Bool = true
    let action: () -> Void

    /// Level with the timer beside it and with the keyboard accessory's capsules, which the pair
    /// parks next to whenever a keyboard is open.
    private let buttonSize: CGFloat = KEYBOARD_TOOLBAR_HEIGHT

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(buttonTint)
                // Pause → play is one button changing its glyph, not two buttons swapping.
                .contentTransition(.symbolEffect(.replace))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .tint(buttonTint.secondaryTranslucentBackground)
        .frame(width: buttonSize, height: buttonSize)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var buttonTint: Color {
        if let exerciseColor = workoutRecorder.activeRestTimerSet?.exercise?.muscleGroup?.color {
            return exerciseColor
        }

        return .accentColor
    }
}

private struct WorkoutRecorderFloatingChronoTransportButtonPreviewWrapper: View {
    enum Scenario {
        case running
        case paused
        case pausedAtZero
    }

    @EnvironmentObject private var database: Database
    @EnvironmentObject private var workoutRecorder: WorkoutRecorder

    let scenario: Scenario

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color.black.opacity(0.82)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            HStack {
                switch scenario {
                case .running:
                    button("pause.fill", "pause")
                case .paused:
                    button("play.fill", "continue")
                    button("stop.fill", "stop")
                case .pausedAtZero:
                    button("play.fill", "continue", isEnabled: false)
                    button("stop.fill", "stop")
                }
            }
            .padding()
        }
        .frame(height: 120)
        .onAppear {
            if workoutRecorder.workout == nil {
                workoutRecorder.startWorkout(from: database.testTemplate)
            }

            workoutRecorder.activeRestTimerSet = workoutRecorder.workout?.sets.first
        }
    }

    private func button(_ systemImage: String, _ labelKey: String, isEnabled: Bool = true) -> some View {
        WorkoutRecorderFloatingChronoTransportButton(
            workoutRecorder: workoutRecorder,
            systemImage: systemImage,
            accessibilityLabel: NSLocalizedString(labelKey, comment: ""),
            isEnabled: isEnabled,
            action: {}
        )
    }
}

struct WorkoutRecorderFloatingChronoTransportButton_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            WorkoutRecorderFloatingChronoTransportButtonPreviewWrapper(scenario: .running)
                .previewDisplayName("Running")
            WorkoutRecorderFloatingChronoTransportButtonPreviewWrapper(scenario: .paused)
                .previewDisplayName("Paused")
            WorkoutRecorderFloatingChronoTransportButtonPreviewWrapper(scenario: .pausedAtZero)
                .previewDisplayName("Paused at 0")
        }
        .previewEnvironmentObjects()
    }
}
