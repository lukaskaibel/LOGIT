//
//  WorkoutLiveActivityAttributes.swift
//  LOGIT
//
//  Created by Codex on 28.03.26.
//

import ActivityKit
import Foundation

enum WorkoutLiveActivityChronoPhase: String, Codable, Hashable {
    case timerRunning
    case timerPaused
    case stopwatchRunning
    case stopwatchPaused
}

/// Drives rest-chip coloring to mirror `WorkoutRecorderFloatingTimerButton` (muscle tint for auto rest timer, distinct stopwatch rest, accent for manual).
enum WorkoutLiveActivityChronoTintKind: String, Codable, Hashable {
    case restTimer
    case restStopwatch
    case manual
}

struct WorkoutLiveActivityChronoChip: Codable, Hashable {
    let phase: WorkoutLiveActivityChronoPhase
    let tintKind: WorkoutLiveActivityChronoTintKind
    /// Set for `tintKind == .restTimer` (muscle group of the set that triggered rest).
    let muscleThemeToken: WorkoutLiveActivityThemeToken?
    let timerEndDate: Date?
    let timerTotalSeconds: Double?
    let staticTickSeconds: Int?
    let stopwatchStartDate: Date?

    static func == (lhs: WorkoutLiveActivityChronoChip, rhs: WorkoutLiveActivityChronoChip) -> Bool {
        lhs.phase == rhs.phase
            && lhs.tintKind == rhs.tintKind
            && lhs.muscleThemeToken == rhs.muscleThemeToken
            && lhs.timerEndDate == rhs.timerEndDate
            && lhs.timerTotalSeconds == rhs.timerTotalSeconds
            && lhs.staticTickSeconds == rhs.staticTickSeconds
            && {
                if lhs.phase == .stopwatchRunning, rhs.phase == .stopwatchRunning { return true }
                return lhs.stopwatchStartDate == rhs.stopwatchStartDate
            }()
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(phase)
        hasher.combine(tintKind)
        hasher.combine(muscleThemeToken)
        hasher.combine(timerEndDate)
        hasher.combine(timerTotalSeconds)
        hasher.combine(staticTickSeconds)
        if phase != .stopwatchRunning {
            hasher.combine(stopwatchStartDate)
        }
    }
}

struct WorkoutLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let workoutTitle: String
        let exerciseIndex: Int
        let exerciseCount: Int
        let setIndex: Int
        let setCount: Int
        /// For supersets, the **focused** exercise (first until `repetitionsFirstExercise > 0`, then the second).
        let primaryExerciseName: String
        /// Superset **partner** exercise shown smaller beside the primary name with an arrow; `nil` when not a superset.
        let secondaryExerciseName: String?
        /// `true` when the partner label is **leading** (`Partner ← Main`); `false` when **trailing** (`Main → Partner`).
        /// Optional for decoding older payloads that omit this key (`nil` treated as `false` in the widget).
        let supersetPartnerIsLeading: Bool?
        let primaryMetrics: ExerciseMetricDisplay
        /// Only used for non-superset sets; supersets surface a single focused row in `primaryMetrics`.
        let secondaryMetrics: ExerciseMetricDisplay?
        /// Logged metrics from the prior set in the same set group (nil on first set or when nothing was entered).
        let previousPrimaryMetrics: ExerciseMetricDisplay?
        let previousSecondaryMetrics: ExerciseMetricDisplay?
        let themeToken: WorkoutLiveActivityThemeToken
        let chronoChip: WorkoutLiveActivityChronoChip?

        /// Current set index within the active set group (e.g. `2/4`). Nil when there is no set group.
        var setFractionLabel: String? {
            guard setCount > 0 else { return nil }
            return "\(max(setIndex, 0))/\(max(setCount, 0))"
        }
    }

    let workoutID: UUID
    let startedAt: Date
}

/// Segmented reps/weight for Live Activity, mirroring `IntegerField` / `DecimalField` in `WorkoutSetCell`
/// (placeholder gray when the stored value is still 0; filled white + secondary unit when entered).
struct ExerciseMetricDisplay: Codable, Hashable {
    let repetitionSegments: [String]
    let repetitionSegmentPlaceholders: [Bool]
    let repetitionsUnit: String
    let weightSegments: [String]
    let weightSegmentPlaceholders: [Bool]
    let weightUnit: String

    var isEmpty: Bool {
        repetitionSegments.isEmpty && weightSegments.isEmpty
    }

    /// First weight value for compact Dynamic Island leading (includes placeholder flag for `WorkoutSetCell`-style tint).
    var compactWeightValueUnitAndPlaceholder: (value: String, unit: String, isPlaceholder: Bool)? {
        guard let value = weightSegments.first else { return nil }
        let isPlaceholder = weightSegmentPlaceholders.first ?? false
        return (value, weightUnit, isPlaceholder)
    }

    static func emptyForLiveActivity() -> ExerciseMetricDisplay {
        let weightUnitRaw = UserDefaults.standard.string(forKey: "weightUnit") ?? "kg"
        return ExerciseMetricDisplay(
            repetitionSegments: [],
            repetitionSegmentPlaceholders: [],
            repetitionsUnit: NSLocalizedString("reps", comment: ""),
            weightSegments: [],
            weightSegmentPlaceholders: [],
            weightUnit: weightUnitRaw
        )
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
