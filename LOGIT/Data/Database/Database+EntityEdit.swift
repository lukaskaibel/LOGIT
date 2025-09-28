//
//  Database+EntityEdit.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 03.11.22.
//

import Foundation

public extension Database {
    func addSet(to setGroup: WorkoutSetGroup) {
        let lastSet = setGroup.sets.last
        if let _ = lastSet as? DropSet {
            newDropSet(setGroup: setGroup)
        } else if let _ = lastSet as? SuperSet {
            newSuperSet(setGroup: setGroup)
        } else {
            newStandardSet(setGroup: setGroup)
        }
        setGroup.workout?.objectWillChange.send()
    }

    func duplicateLastSet(from setGroup: WorkoutSetGroup) {
        let lastSet = setGroup.sets.last
        if let standardSet = lastSet as? StandardSet {
            newStandardSet(
                repetitions: Int(standardSet.repetitions),
                weight: Int(standardSet.weight),
                setGroup: setGroup
            )
        } else if let dropSet = lastSet as? DropSet {
            newDropSet(
                repetitions: dropSet.repetitions?.map { Int($0) } ?? [0],
                weights: dropSet.weights?.map { Int($0) } ?? [0],
                setGroup: setGroup
            )
        } else if let superSet = lastSet as? SuperSet {
            newSuperSet(
                repetitionsFirstExercise: Int(superSet.repetitionsFirstExercise),
                repetitionsSecondExercise: Int(superSet.repetitionsSecondExercise),
                weightFirstExercise: Int(superSet.weightFirstExercise),
                weightSecondExercise: Int(superSet.weightSecondExercise),
                setGroup: setGroup
            )
        }
        setGroup.workout?.objectWillChange.send()
    }

    func addSet(to templateSetGroup: TemplateSetGroup) {
        let lastSet = templateSetGroup.sets.last
        if let _ = lastSet as? TemplateDropSet {
            newTemplateDropSet(templateSetGroup: templateSetGroup)
        } else if let _ = lastSet as? TemplateSuperSet {
            newTemplateSuperSet(setGroup: templateSetGroup)
        } else {
            newTemplateStandardSet(setGroup: templateSetGroup)
        }
    }

    func duplicateLastSet(from setGroup: TemplateSetGroup) {
        let lastSet = setGroup.sets.last
        if let standardSet = lastSet as? TemplateStandardSet {
            newTemplateStandardSet(
                repetitions: Int(standardSet.repetitions),
                weight: Int(standardSet.weight),
                setGroup: setGroup
            )
        } else if let dropSet = lastSet as? TemplateDropSet {
            newTemplateDropSet(
                repetitions: dropSet.repetitions?.map { Int($0) } ?? [0],
                weights: dropSet.weights?.map { Int($0) } ?? [0],
                templateSetGroup: setGroup
            )
        } else if let superSet = lastSet as? TemplateSuperSet {
            newTemplateSuperSet(
                repetitionsFirstExercise: Int(superSet.repetitionsFirstExercise),
                repetitionsSecondExercise: Int(superSet.repetitionsSecondExercise),
                weightFirstExercise: Int(superSet.weightFirstExercise),
                weightSecondExercise: Int(superSet.weightSecondExercise),
                setGroup: setGroup
            )
        }
    }
}
