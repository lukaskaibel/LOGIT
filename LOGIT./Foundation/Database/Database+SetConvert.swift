//
//  Database+SetConvert.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 02.11.22.
//

import Foundation

extension Database {
    // MARK: - WorkoutSet Convert Methods

    public func convertSetGroupToStandardSets(_ setGroup: WorkoutSetGroup) {
        setGroup.sets
            .forEach { convertToStandardSet($0) }
    }

    private func convertToStandardSet(_ workoutSet: WorkoutSet) {
        if let dropSet = workoutSet as? DropSet {
            let standardSet = newStandardSet(
                repetitions: Int(dropSet.repetitions?.first ?? 0),
                weight: Int(dropSet.weights?.first ?? 0)
            )
            dropSet.setGroup?.sets
                .replaceValue(
                    at: dropSet.setGroup?.index(of: dropSet) ?? 0,
                    with: standardSet
                )
            delete(dropSet)
        } else if let superSet = workoutSet as? SuperSet {
            let standardSet = newStandardSet(
                repetitions: Int(superSet.repetitionsFirstExercise),
                weight: Int(superSet.weightFirstExercise)
            )
            superSet.setGroup?.sets
                .replaceValue(
                    at: superSet.setGroup?.index(of: superSet) ?? 0,
                    with: standardSet
                )
            delete(superSet)
        }
    }

    public func convertSetGroupToDropSets(_ setGroup: WorkoutSetGroup) {
        setGroup.sets
            .forEach { convertToDropSet($0) }
    }

    private func convertToDropSet(_ workoutSet: WorkoutSet) {
        if let standardSet = workoutSet as? StandardSet {
            let dropSet = newDropSet(
                repetitions: [standardSet.repetitions].map { Int($0) },
                weights: [standardSet.weight].map { Int($0) }
            )
            standardSet.setGroup?.sets
                .replaceValue(
                    at: standardSet.setGroup?.index(of: standardSet) ?? 0,
                    with: dropSet
                )
            delete(workoutSet)
        } else if let superSet = workoutSet as? SuperSet {
            let dropSet = newDropSet(
                repetitions: [superSet.repetitionsFirstExercise].map { Int($0) },
                weights: [superSet.weightFirstExercise].map { Int($0) }
            )
            superSet.setGroup?.sets
                .replaceValue(
                    at: superSet.setGroup?.index(of: superSet) ?? 0,
                    with: dropSet
                )
            delete(superSet)
        }
    }

    public func convertSetGroupToSuperSets(_ setGroup: WorkoutSetGroup) {
        setGroup.sets
            .forEach { convertToSuperSet($0) }
    }

    private func convertToSuperSet(_ workoutSet: WorkoutSet) {
        if let standardSet = workoutSet as? StandardSet {
            let superSet = newSuperSet(
                repetitionsFirstExercise: Int(standardSet.repetitions),
                weightFirstExercise: Int(standardSet.weight)
            )
            standardSet.setGroup?.sets
                .replaceValue(
                    at: standardSet.setGroup?.index(of: standardSet) ?? 0,
                    with: superSet
                )
            delete(standardSet)
        } else if let dropSet = workoutSet as? DropSet {
            let superSet = newSuperSet(
                repetitionsFirstExercise: Int(dropSet.repetitions?.first ?? 0),
                weightFirstExercise: Int(dropSet.weights?.first ?? 0)
            )
            dropSet.setGroup?.sets
                .replaceValue(
                    at: dropSet.setGroup?.index(of: dropSet) ?? 0,
                    with: superSet
                )
            delete(dropSet)
        }
    }

    // MARK: - TemplateSet Converter Methods

    public func convertSetGroupToStandardSets(_ templateSetGroup: TemplateSetGroup) {
        templateSetGroup.sets
            .forEach { convertToStandardSet($0) }
    }

    private func convertToStandardSet(_ templateSet: TemplateSet) {
        if let templateDropSet = templateSet as? TemplateDropSet {
            let templateStandardSet = newTemplateStandardSet(
                repetitions: Int(templateDropSet.repetitions?.first ?? 0),
                weight: Int(templateDropSet.weights?.first ?? 0)
            )
            templateDropSet.setGroup?.sets
                .replaceValue(
                    at: templateDropSet.setGroup?.index(of: templateDropSet) ?? 0,
                    with: templateStandardSet
                )
            delete(templateDropSet)
        } else if let templateSuperSet = templateSet as? TemplateSuperSet {
            let templateStandardSet = newTemplateStandardSet(
                repetitions: Int(templateSuperSet.repetitionsFirstExercise),
                weight: Int(templateSuperSet.weightFirstExercise)
            )
            templateSuperSet.setGroup?.sets
                .replaceValue(
                    at: templateSuperSet.setGroup?.index(of: templateSuperSet) ?? 0,
                    with: templateStandardSet
                )
            delete(templateSuperSet)
        }
    }

    public func convertSetGroupToDropSets(_ templateSetGroup: TemplateSetGroup) {
        templateSetGroup.sets
            .forEach { convertToTemplateDropSet($0) }
    }

    private func convertToTemplateDropSet(_ templateSet: TemplateSet) {
        if let templateStandardSet = templateSet as? TemplateStandardSet {
            let templateDropSet = newTemplateDropSet(
                repetitions: [templateStandardSet.repetitions].map { Int($0) },
                weights: [templateStandardSet.weight].map { Int($0) }
            )
            templateStandardSet.setGroup?.sets
                .replaceValue(
                    at: templateStandardSet.setGroup?.index(of: templateStandardSet) ?? 0,
                    with: templateDropSet
                )
            delete(templateStandardSet)
        } else if let templateSuperSet = templateSet as? TemplateSuperSet {
            let templateDropSet = newTemplateDropSet(
                repetitions: [Int(templateSuperSet.repetitionsFirstExercise)],
                weights: [Int(templateSuperSet.weightFirstExercise)]
            )
            templateSuperSet.setGroup?.sets
                .replaceValue(
                    at: templateSuperSet.setGroup?.index(of: templateSuperSet) ?? 0,
                    with: templateDropSet
                )
            delete(templateSuperSet)
        }
    }

    public func convertSetGroupToSuperSet(_ templateSetGroup: TemplateSetGroup) {
        templateSetGroup.sets
            .forEach { convertToTemplateSuperSet($0) }
    }

    private func convertToTemplateSuperSet(_ templateSet: TemplateSet) {
        if let templateStandardSet = templateSet as? TemplateStandardSet {
            let templateSuperSet = newTemplateSuperSet(
                repetitionsFirstExercise: Int(templateStandardSet.repetitions),
                weightFirstExercise: Int(templateStandardSet.weight)
            )
            templateStandardSet.setGroup?.sets
                .replaceValue(
                    at: templateStandardSet.setGroup?.index(of: templateStandardSet) ?? 0,
                    with: templateSuperSet
                )
            delete(templateStandardSet)
        } else if let templateDropSet = templateSet as? TemplateDropSet {
            let templateSuperSet = newTemplateSuperSet(
                repetitionsFirstExercise: Int(templateDropSet.repetitions?.first ?? 0),
                weightFirstExercise: Int(templateDropSet.weights?.first ?? 0)
            )
            templateDropSet.setGroup?.sets
                .replaceValue(
                    at: templateDropSet.setGroup?.index(of: templateDropSet) ?? 0,
                    with: templateSuperSet
                )
            delete(templateDropSet)
        }
    }
}
