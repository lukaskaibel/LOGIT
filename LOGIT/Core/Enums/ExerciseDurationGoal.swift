//
//  ExerciseDurationGoal.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 18.08.26.
//

import Foundation

/// Which direction an exercise's duration improves in.
///
/// A hold improves by lasting longer; a timed effort — a sprint, a 500 m row — improves by ending
/// sooner. The same field, opposite goals, and nothing in a recorded set can tell the two apart,
/// so the exercise carries the answer and every duration comparison in the app consults it
/// through `Exercise.isBetter(_:than:for:)`.
///
/// This is deliberately duration-only. Weight has no flag: assistance is recorded as a negative
/// load, which puts "less help" and "more weight" on one scale that already sorts upward.
enum ExerciseDurationGoal: String, CaseIterable, Identifiable {
    /// The default, and the assumption of every comparison written before model v11.
    case longer
    case faster

    var id: String { rawValue }

    var title: String {
        switch self {
        case .longer: return NSLocalizedString("durationGoalLonger", comment: "")
        case .faster: return NSLocalizedString("durationGoalFaster", comment: "")
        }
    }

    /// One line under the picker explaining what a record becomes — the editor's other choices
    /// (measurement, progress metric) each carry one, and this is the least self-evident of them.
    var caption: String {
        switch self {
        case .longer: return NSLocalizedString("durationGoalLongerDescription", comment: "")
        case .faster: return NSLocalizedString("durationGoalFasterDescription", comment: "")
        }
    }
}
