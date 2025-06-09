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

    // MARK: Overrides from TemplateSet

    override var hasEntry: Bool {
        repetitionsFirstExercise + repetitionsSecondExercise + weightFirstExercise
            + weightSecondExercise > 0
    }
}
