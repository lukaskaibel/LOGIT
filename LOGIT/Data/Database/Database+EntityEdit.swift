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

    func addSet(before workoutSet: WorkoutSet) {
        insertEmptySet(relativeTo: workoutSet, offset: 0)
    }

    func addSet(after workoutSet: WorkoutSet) {
        insertEmptySet(relativeTo: workoutSet, offset: 1)
    }

    func duplicateSet(_ workoutSet: WorkoutSet) {
        guard
            let setGroup = workoutSet.setGroup,
            let index = setGroup.sets.firstIndex(of: workoutSet)
        else {
            return
        }

        let duplicatedSet = copy(of: workoutSet)
        insert(duplicatedSet, into: setGroup, at: index + 1)
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
    
    func duplicateLastWeight(from setGroup: WorkoutSetGroup) {
        guard let lastSet = setGroup.sets.last else { return }
        if let standardSet = lastSet as? StandardSet {
            newStandardSet(
                repetitions: 0,
                weight: Int(standardSet.weight),
                setGroup: setGroup
            )
        } else if let dropSet = lastSet as? DropSet {
            let previousWeights = dropSet.weights?.map { Int($0) } ?? [0]
            newDropSet(
                repetitions: previousWeights.map { _ in 0 },
                weights: previousWeights,
                setGroup: setGroup
            )
        } else if let superSet = lastSet as? SuperSet {
            newSuperSet(
                repetitionsFirstExercise: 0,
                repetitionsSecondExercise: 0,
                weightFirstExercise: Int(superSet.weightFirstExercise),
                weightSecondExercise: Int(superSet.weightSecondExercise),
                setGroup: setGroup
            )
        }
        setGroup.workout?.objectWillChange.send()
    }
    
    func duplicateLastRepetitions(from setGroup: WorkoutSetGroup) {
        guard let lastSet = setGroup.sets.last else { return }
        if let standardSet = lastSet as? StandardSet {
            newStandardSet(
                repetitions: Int(standardSet.repetitions),
                weight: 0,
                setGroup: setGroup
            )
        } else if let dropSet = lastSet as? DropSet {
            let previousReps = dropSet.repetitions?.map { Int($0) } ?? [0]
            newDropSet(
                repetitions: previousReps,
                weights: previousReps.map { _ in 0 },
                setGroup: setGroup
            )
        } else if let superSet = lastSet as? SuperSet {
            newSuperSet(
                repetitionsFirstExercise: Int(superSet.repetitionsFirstExercise),
                repetitionsSecondExercise: Int(superSet.repetitionsSecondExercise),
                weightFirstExercise: 0,
                weightSecondExercise: 0,
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

    private func insertEmptySet(relativeTo workoutSet: WorkoutSet, offset: Int) {
        guard
            let setGroup = workoutSet.setGroup,
            let index = setGroup.sets.firstIndex(of: workoutSet)
        else {
            return
        }

        let newSet = emptySet(matching: workoutSet)
        insert(newSet, into: setGroup, at: index + offset)
        setGroup.workout?.objectWillChange.send()
    }

    private func emptySet(matching workoutSet: WorkoutSet) -> WorkoutSet {
        if workoutSet is DropSet {
            return newDropSet()
        } else if workoutSet is SuperSet {
            return newSuperSet()
        } else {
            return newStandardSet()
        }
    }

    private func copy(of workoutSet: WorkoutSet) -> WorkoutSet {
        let duplicatedSet = emptySet(matching: workoutSet)
        duplicatedSet.match(workoutSet)
        return duplicatedSet
    }

    private func insert(_ workoutSet: WorkoutSet, into setGroup: WorkoutSetGroup, at index: Int) {
        var updatedSets = setGroup.sets
        let clampedIndex = max(0, min(index, updatedSets.count))
        updatedSets.insert(workoutSet, at: clampedIndex)
        setGroup.sets = updatedSets
    }
}
