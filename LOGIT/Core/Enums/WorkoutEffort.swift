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

    /// The ratings this band holds. The picker's four bars are this wide — three slots for Easy
    /// and Moderate, two for Hard and All Out — so a bar's width *is* how many answers it covers.
    var scores: ClosedRange<Int> {
        switch self {
        case .easy: return 1...3
        case .moderate: return 4...6
        case .hard: return 7...8
        case .allOut: return 9...10
        }
    }

    var name: String {
        switch self {
        case .easy: return NSLocalizedString("effortEasy", comment: "")
        case .moderate: return NSLocalizedString("effortModerate", comment: "")
        case .hard: return NSLocalizedString("effortHard", comment: "")
        case .allOut: return NSLocalizedString("effortAllOut", comment: "")
        }
    }

    /// How the band feels while it happens — the first line under its heading in the description
    /// list. Kept in step with the wording Fitness uses for the same bucket: the rating LOGIT
    /// writes is read back there, so the two apps must not describe one number two ways.
    var feelDescription: String {
        switch self {
        case .easy: return NSLocalizedString("effortEasyFeel", comment: "")
        case .moderate: return NSLocalizedString("effortModerateFeel", comment: "")
        case .hard: return NSLocalizedString("effortHardFeel", comment: "")
        case .allOut: return NSLocalizedString("effortAllOutFeel", comment: "")
        }
    }

    /// How long you could keep it up — the second line.
    var enduranceDescription: String {
        switch self {
        case .easy: return NSLocalizedString("effortEasyEndurance", comment: "")
        case .moderate: return NSLocalizedString("effortModerateEndurance", comment: "")
        case .hard: return NSLocalizedString("effortHardEndurance", comment: "")
        case .allOut: return NSLocalizedString("effortAllOutEndurance", comment: "")
        }
    }
}
