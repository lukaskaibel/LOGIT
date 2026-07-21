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
        let newSet: WorkoutSet
        if lastSet is DropSet {
            newSet = newDropSet(setGroup: setGroup)
        } else if lastSet is SuperSet {
            newSet = newSuperSet(setGroup: setGroup)
        } else {
            newSet = newStandardSet(setGroup: setGroup)
        }
        // Continue the group's shape: same drop count and same measurement types as the set
        // before, values left empty for the athlete to fill in.
        if let lastSet {
            newSet.matchStructure(toEntryValues: lastSet.entryValues)
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
        guard let lastSet = setGroup.sets.last else { return }
        let duplicatedSet = copy(of: lastSet)
        insert(duplicatedSet, into: setGroup, at: setGroup.sets.count)
        setGroup.workout?.objectWillChange.send()
    }

    func duplicateLastWeight(from setGroup: WorkoutSetGroup) {
        duplicateLastSet(from: setGroup, keepingWeight: true, keepingRepetitions: false)
    }

    func duplicateLastRepetitions(from setGroup: WorkoutSetGroup) {
        duplicateLastSet(from: setGroup, keepingWeight: false, keepingRepetitions: true)
    }

    /// Appends a copy of the group's last set that keeps only one field per entry — the
    /// "same weight again" / "same reps again" quick actions.
    private func duplicateLastSet(
        from setGroup: WorkoutSetGroup, keepingWeight: Bool, keepingRepetitions: Bool
    ) {
        guard let lastSet = setGroup.sets.last else { return }
        let newSet = emptySet(matching: lastSet)
        insert(newSet, into: setGroup, at: setGroup.sets.count)
        newSet.matchStructure(toEntryValues: lastSet.entryValues)
        for (entry, value) in zip(newSet.entries, lastSet.entryValues) {
            if keepingWeight { entry.weight = value.weight }
            if keepingRepetitions { entry.repetitions = value.repetitions }
        }
        setGroup.workout?.objectWillChange.send()
    }

    func addSet(to templateSetGroup: TemplateSetGroup) {
        let lastSet = templateSetGroup.sets.last
        let newSet: TemplateSet
        if lastSet is TemplateDropSet {
            newSet = newTemplateDropSet(templateSetGroup: templateSetGroup)
        } else if lastSet is TemplateSuperSet {
            newSet = newTemplateSuperSet(setGroup: templateSetGroup)
        } else {
            newSet = newTemplateStandardSet(setGroup: templateSetGroup)
        }
        if let lastSet {
            newSet.matchStructure(toEntryValues: lastSet.entryValues)
        }
    }

    func duplicateLastSet(from setGroup: TemplateSetGroup) {
        guard let lastSet = setGroup.sets.last else { return }
        let duplicatedSet = copy(of: lastSet)
        insert(duplicatedSet, into: setGroup, at: setGroup.sets.count)
    }

    func addSet(before templateSet: TemplateSet) {
        insertEmptyTemplateSet(relativeTo: templateSet, offset: 0)
    }

    func addSet(after templateSet: TemplateSet) {
        insertEmptyTemplateSet(relativeTo: templateSet, offset: 1)
    }

    func duplicateSet(_ templateSet: TemplateSet) {
        guard
            let setGroup = templateSet.setGroup,
            let index = setGroup.sets.firstIndex(of: templateSet)
        else {
            return
        }

        let duplicatedSet = copy(of: templateSet)
        insert(duplicatedSet, into: setGroup, at: index + 1)
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
        newSet.matchStructure(toEntryValues: workoutSet.entryValues)
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

    private func insertEmptyTemplateSet(relativeTo templateSet: TemplateSet, offset: Int) {
        guard
            let setGroup = templateSet.setGroup,
            let index = setGroup.sets.firstIndex(of: templateSet)
        else {
            return
        }

        let newSet = emptySet(matching: templateSet)
        insert(newSet, into: setGroup, at: index + offset)
        newSet.matchStructure(toEntryValues: templateSet.entryValues)
    }

    private func emptySet(matching templateSet: TemplateSet) -> TemplateSet {
        if templateSet is TemplateDropSet {
            return newTemplateDropSet()
        } else if templateSet is TemplateSuperSet {
            return newTemplateSuperSet()
        } else {
            return newTemplateStandardSet()
        }
    }

    private func copy(of templateSet: TemplateSet) -> TemplateSet {
        let duplicatedSet = emptySet(matching: templateSet)
        duplicatedSet.match(templateSet)
        return duplicatedSet
    }

    private func insert(_ templateSet: TemplateSet, into setGroup: TemplateSetGroup, at index: Int) {
        var updatedSets = setGroup.sets
        let clampedIndex = max(0, min(index, updatedSets.count))
        updatedSets.insert(templateSet, at: clampedIndex)
        setGroup.sets = updatedSets
    }
}
