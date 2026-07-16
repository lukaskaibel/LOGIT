//
//  TemplateSuperSet+.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 25.05.22.
//

import Foundation

public extension TemplateSuperSet {
    var secondaryExercise: Exercise? {
        setGroup?.secondaryExercise
    }

    // MARK: Legacy-field fallbacks (see TemplateSet.hasEntry)

    internal override var legacyHasEntry: Bool {
        repetitionsFirstExercise + repetitionsSecondExercise + weightFirstExercise
            + weightSecondExercise > 0
    }
}
