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

    // MARK: Overrides from WorkoutSet

    override var hasEntry: Bool {
        repetitionsFirstExercise > 0 || repetitionsSecondExercise > 0 || weightFirstExercise > 0
            || weightSecondExercise > 0
    }

    override func clearEntries() {
        repetitionsFirstExercise = 0
        repetitionsSecondExercise = 0
        weightFirstExercise = 0
        weightSecondExercise = 0
    }
}
