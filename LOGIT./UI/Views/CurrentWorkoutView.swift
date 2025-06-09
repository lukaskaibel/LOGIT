//
//  CurrentWorkoutView.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 12.03.24.
//

import SwiftUI

struct CurrentWorkoutView: View {
    let workoutName: String?
    let workoutDate: Date?

    var body: some View {
        HStack {
            Text(workoutHasName ? workoutName! : Workout.getStandardName(for: workoutDate ?? .now))
                .fontWeight(.bold)
                .lineLimit(1)
            Spacer()
            Group {
                if let workoutStartTime = workoutDate {
                    StopwatchView(startTime: workoutStartTime)
                } else {
                    Text("-:--:--")
                }
            }
            .font(.body.monospacedDigit())
//            .foregroundStyle(Color.accentColor.gradient)
        }
        .padding(20)
    }

    private var workoutHasName: Bool {
        !(workoutName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

// MARK: - Preview

private struct PreviewWrapper: View {
    @EnvironmentObject var database: Database

    var body: some View {
        CurrentWorkoutView(workoutName: database.testWorkout.name, workoutDate: database.testWorkout.date)
            .previewEnvironmentObjects()
            .padding(.horizontal, 8)
            .padding(.bottom, 2)
    }
}

#Preview {
    PreviewWrapper()
        .previewEnvironmentObjects()
}
