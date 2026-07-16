//
//  SuperSet+.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 25.05.22.
//

import Foundation

public extension SuperSet {
    internal var secondaryExercise: Exercise? {
        setGroup?.secondaryExercise
    }

    // MARK: Legacy-field fallbacks (see WorkoutSet.hasEntry & friends)

    internal override var legacyHasEntry: Bool {
        repetitionsFirstExercise > 0 || repetitionsSecondExercise > 0 || weightFirstExercise > 0
            || weightSecondExercise > 0
    }

    internal override var legacyHasRepetitionEntry: Bool {
        repetitionsFirstExercise > 0 || repetitionsSecondExercise > 0
    }

    internal override func legacyClearEntries() {
        repetitionsFirstExercise = 0
        repetitionsSecondExercise = 0
        weightFirstExercise = 0
        weightSecondExercise = 0
    }
}
