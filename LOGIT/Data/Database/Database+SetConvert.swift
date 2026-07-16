//
//  Database+SetConvert.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 02.11.22.
//

import Foundation

/// Converts a set group between standard / drop / super sets by regrouping its entries.
///
/// The rules mirror the pre-entry behavior: the source's primary-exercise entries carry over
/// (a super set contributes only its first-exercise entry), a conversion to standard keeps the
/// first entry, a conversion to super gains an empty second-exercise entry. Entry types and
/// durations travel with the values, and rest durations are preserved.
extension Database {
    // MARK: - WorkoutSet Convert Methods

    public func convertSetGroupToStandardSets(_ setGroup: WorkoutSetGroup) {
        setGroup.sets.forEach { convert($0, to: .standard) }
    }

    public func convertSetGroupToDropSets(_ setGroup: WorkoutSetGroup) {
        setGroup.sets.forEach { convert($0, to: .dropSet) }
    }

    public func convertSetGroupToSuperSets(_ setGroup: WorkoutSetGroup) {
        setGroup.sets.forEach { convert($0, to: .superSet) }
    }

    private func convert(_ workoutSet: WorkoutSet, to type: WorkoutSetGroup.SetType) {
        guard let setGroup = workoutSet.setGroup,
              let index = setGroup.index(of: workoutSet)
        else { return }

        // Entries attributed to the primary exercise are what carries over; a super set's
        // second-exercise entry belongs to an exercise the target set no longer trains.
        let carriedValues = carriedPrimaryValues(of: workoutSet)

        let newSet: WorkoutSet
        let newValues: [SetEntryValues]
        switch type {
        case .standard:
            guard !(workoutSet is StandardSet) else { return }
            newSet = newStandardSet(restDuration: workoutSet.restDurationSeconds)
            newValues = Array(carriedValues.prefix(1))
        case .dropSet:
            guard !(workoutSet is DropSet) else { return }
            newSet = newDropSet(restDuration: workoutSet.restDurationSeconds)
            newValues = carriedValues
        case .superSet:
            guard !(workoutSet is SuperSet) else { return }
            newSet = newSuperSet(restDuration: workoutSet.restDurationSeconds)
            newValues = Array(carriedValues.prefix(1)) + [
                SetEntryValues(
                    type: .repsAndWeight, order: 1,
                    repetitions: 0, weight: 0, duration: 0, exercise: nil
                )
            ]
        }

        setGroup.sets.replaceValue(at: index, with: newSet)
        rebuildEntries(of: newSet, from: newValues)
        delete(workoutSet)
    }

    // MARK: - TemplateSet Converter Methods

    public func convertSetGroupToStandardSets(_ templateSetGroup: TemplateSetGroup) {
        templateSetGroup.sets.forEach { convert($0, to: .standard) }
    }

    public func convertSetGroupToDropSets(_ templateSetGroup: TemplateSetGroup) {
        templateSetGroup.sets.forEach { convert($0, to: .dropSet) }
    }

    public func convertSetGroupToSuperSet(_ templateSetGroup: TemplateSetGroup) {
        templateSetGroup.sets.forEach { convert($0, to: .superSet) }
    }

    private func convert(_ templateSet: TemplateSet, to type: TemplateSetGroup.SetType) {
        guard let setGroup = templateSet.setGroup,
              let index = setGroup.index(of: templateSet)
        else { return }

        let carriedValues = carriedPrimaryValues(of: templateSet)

        let newSet: TemplateSet
        let newValues: [SetEntryValues]
        switch type {
        case .standard:
            guard !(templateSet is TemplateStandardSet) else { return }
            newSet = newTemplateStandardSet(restDuration: templateSet.restDurationSeconds)
            newValues = Array(carriedValues.prefix(1))
        case .dropSet:
            guard !(templateSet is TemplateDropSet) else { return }
            newSet = newTemplateDropSet(restDuration: templateSet.restDurationSeconds)
            newValues = carriedValues
        case .superSet:
            guard !(templateSet is TemplateSuperSet) else { return }
            newSet = newTemplateSuperSet(restDuration: templateSet.restDurationSeconds)
            newValues = Array(carriedValues.prefix(1)) + [
                SetEntryValues(
                    type: .repsAndWeight, order: 1,
                    repetitions: 0, weight: 0, duration: 0, exercise: nil
                )
            ]
        }

        var updatedSets = setGroup.sets
        updatedSets.replaceValue(at: index, with: newSet)
        setGroup.sets = updatedSets
        rebuildEntries(of: newSet, from: newValues)
        delete(templateSet)
    }

    // MARK: - Shared

    /// The source set's primary-exercise entry values, renumbered 0..n-1.
    private func carriedPrimaryValues(of workoutSet: WorkoutSet) -> [SetEntryValues] {
        let values = workoutSet is SuperSet
            ? workoutSet.entryValues.filter { $0.order == 0 }
            : workoutSet.entryValues
        return renumbered(values)
    }

    private func carriedPrimaryValues(of templateSet: TemplateSet) -> [SetEntryValues] {
        let values = templateSet is TemplateSuperSet
            ? templateSet.entryValues.filter { $0.order == 0 }
            : templateSet.entryValues
        return renumbered(values)
    }

    private func renumbered(_ values: [SetEntryValues]) -> [SetEntryValues] {
        values.enumerated().map { index, value in
            var renumberedValue = value
            renumberedValue.order = Int64(index)
            return renumberedValue
        }
    }

    /// Replaces the factory-created default entries with the carried-over values, re-resolving
    /// exercise attribution against the set's own group.
    private func rebuildEntries(of workoutSet: WorkoutSet, from values: [SetEntryValues]) {
        workoutSet.removeAllEntries()
        for value in values {
            var resolved = value
            resolved.exercise =
                workoutSet.positionalExercise(forOrder: value.order) ?? value.exercise
            workoutSet.insertEntry(from: resolved)
        }
    }

    private func rebuildEntries(of templateSet: TemplateSet, from values: [SetEntryValues]) {
        templateSet.removeAllEntries()
        for value in values {
            var resolved = value
            resolved.exercise =
                templateSet.positionalExercise(forOrder: value.order) ?? value.exercise
            templateSet.insertEntry(from: resolved)
        }
    }
}
