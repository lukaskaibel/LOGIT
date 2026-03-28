//
//  WorkoutLiveActivityAttributes.swift
//  LOGIT
//
//  Created by Codex on 28.03.26.
//

import ActivityKit
import Foundation

struct WorkoutLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let workoutTitle: String
        let exerciseIndex: Int
        let exerciseCount: Int
        let setIndex: Int
        let setCount: Int
        let primaryExerciseName: String
        let secondaryExerciseName: String?
        let primaryMetrics: ExerciseMetricDisplay
        let secondaryMetrics: ExerciseMetricDisplay?
        let themeToken: WorkoutLiveActivityThemeToken

        /// Current set index within the active set group (e.g. `2/4`). Nil when there is no set group.
        var setFractionLabel: String? {
            guard setCount > 0 else { return nil }
            return "\(max(setIndex, 0))/\(max(setCount, 0))"
        }
    }

    let workoutID: UUID
    let startedAt: Date
}

struct ExerciseMetricDisplay: Codable, Hashable {
    let repetitionsText: String?
    let weightText: String?

    var isEmpty: Bool {
        repetitionsText == nil && weightText == nil
    }
}

enum WorkoutLiveActivityThemeToken: String, Codable, Hashable {
    case chest
    case triceps
    case shoulders
    case biceps
    case back
    case legs
    case abdominals
    case cardio
    case neutral
}
