//
//  WorkoutRecorderFloatingStopwatchStopButton.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 23.03.26.
//

import SwiftUI

struct WorkoutRecorderFloatingStopwatchStopButton: View {
    @ObservedObject var workoutRecorder: WorkoutRecorder

    let action: () -> Void

    private let buttonSize: CGFloat = 43

    var body: some View {
        Button(action: action) {
            Image(systemName: "stop.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(buttonTint)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .tint(buttonTint.secondaryTranslucentBackground)
        .frame(width: buttonSize, height: buttonSize)
    }

    private var buttonTint: Color {
        if let exerciseColor = workoutRecorder.activeRestTimerSet?.exercise?.muscleGroup?.color {
            return exerciseColor
        }

        return .accentColor
    }
}

private struct WorkoutRecorderFloatingStopwatchStopButtonPreviewWrapper: View {
    @EnvironmentObject private var database: Database
    @EnvironmentObject private var workoutRecorder: WorkoutRecorder

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color.black.opacity(0.82)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            WorkoutRecorderFloatingStopwatchStopButton(
                workoutRecorder: workoutRecorder,
                action: {}
            )
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
}

struct WorkoutRecorderFloatingStopwatchStopButton_Previews: PreviewProvider {
    static var previews: some View {
        WorkoutRecorderFloatingStopwatchStopButtonPreviewWrapper()
            .previewEnvironmentObjects()
    }
}
