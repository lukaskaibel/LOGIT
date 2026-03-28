//
//  TemplateSet+.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 21.05.22.
//

import Foundation

public extension TemplateSet {
    @objc var hasEntry: Bool {
        fatalError("TemplateSet+: hasEntry must be implemented in subclass of TemplateSet")
    }

    /// Rest duration in seconds after completing this set. 0 means no rest defined.
    var restDurationSeconds: Int {
        get { Int(restDuration) }
        set { restDuration = Int64(newValue) }
    }

    var exercise: Exercise? {
        setGroup?.exercise
    }

    func match(_ templateSet: TemplateSet) {
        if let standardSet = self as? TemplateStandardSet,
           let sourceStandardSet = templateSet as? TemplateStandardSet
        {
            standardSet.repetitions = sourceStandardSet.repetitions
            standardSet.weight = sourceStandardSet.weight
        } else if let dropSet = self as? TemplateDropSet,
                  let sourceDropSet = templateSet as? TemplateDropSet
        {
            dropSet.repetitions = sourceDropSet.repetitions
            dropSet.weights = sourceDropSet.weights
        } else if let superSet = self as? TemplateSuperSet,
                  let sourceSuperSet = templateSet as? TemplateSuperSet
        {
            superSet.repetitionsFirstExercise = sourceSuperSet.repetitionsFirstExercise
            superSet.repetitionsSecondExercise = sourceSuperSet.repetitionsSecondExercise
            superSet.weightFirstExercise = sourceSuperSet.weightFirstExercise
            superSet.weightSecondExercise = sourceSuperSet.weightSecondExercise
        }

        restDuration = templateSet.restDuration
    }
}
