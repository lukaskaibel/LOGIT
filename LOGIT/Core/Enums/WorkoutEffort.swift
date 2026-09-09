//
//  WorkoutEffort.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 23.08.26.
//

import Foundation

/// How hard a workout felt, on the same 1…10 scale Apple Fitness calls *Effort*.
///
/// The bucket boundaries are Apple's, not ours: a 7 rated in LOGIT has to read "Hard" in the
/// Fitness app too, because the score is exported verbatim as a `workoutEffortScore` sample and
/// both apps then describe the same number (see `HealthKitSyncManager`).
enum WorkoutEffort: CaseIterable, Identifiable {
    case easy, moderate, hard, allOut

    /// The valid range of a rating. 0 is not a low rating — it is how the store spells "unrated"
    /// (see `Workout.effortScore`).
    static let scoreRange = 1...10

    /// Where the finish panel's scale starts, the way Apple's effort screen does: in the middle,
    /// so rating is a nudge from a neutral position rather than a pick from nothing. The centre of
    /// the range and of the Moderate band both land on 5.
    static let defaultScore = 5

    init?(score: Int) {
        switch score {
        case 1...3: self = .easy
        case 4...6: self = .moderate
        case 7...8: self = .hard
        case 9...10: self = .allOut
        default: return nil
        }
    }

    var id: Self { self }

    var name: String {
        switch self {
        case .easy: return NSLocalizedString("effortEasy", comment: "")
        case .moderate: return NSLocalizedString("effortModerate", comment: "")
        case .hard: return NSLocalizedString("effortHard", comment: "")
        case .allOut: return NSLocalizedString("effortAllOut", comment: "")
        }
    }

}
