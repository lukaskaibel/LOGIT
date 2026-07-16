//
//  Database+Entity Creation.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 16.04.22.
//

import Foundation

extension Database {
    /// The measurement type for a factory-created entry: values passed in are always legacy
    /// reps+weight data (previews, imports), so they keep that type no matter how the exercise
    /// is tracked — recorded values must never become invisible behind a mismatched type.
    /// Empty placeholders adopt the exercise's default.
    private func factoryEntryType(
        repetitions: Int, weight: Int, exercise: Exercise?
    ) -> SetMeasurementType {
        if repetitions != 0 || weight != 0 { return .repsAndWeight }
        return exercise?.measurementType ?? .repsAndWeight
    }

    // MARK: - Normal Entitiy Creation

    @discardableResult
    func newWorkout(
        name: String = "",
        date: Date = Date(),
        setGroups: [WorkoutSetGroup] = [WorkoutSetGroup]()
    ) -> Workout {
        let workout = Workout(context: context)
        workout.id = UUID()
        workout.name = name
        workout.date = date
        workout.setGroups = setGroups
        return workout
    }

    @discardableResult
    func newWorkoutSetGroup(
        sets: [WorkoutSet] = [],
        createFirstSetAutomatically: Bool = true,
        exercise: Exercise? = nil,
        workout: Workout? = nil
    ) -> WorkoutSetGroup {
        let setGroup = WorkoutSetGroup(context: context)
        setGroup.id = UUID()
        if !sets.isEmpty {
            setGroup.sets = sets
        } else if createFirstSetAutomatically {
            newStandardSet(setGroup: setGroup)
        }
        setGroup.exercise = exercise
        workout?.setGroups.append(setGroup)
        return setGroup
    }

    @discardableResult
    func newStandardSet(
        repetitions: Int = 0,
        weight: Int = 0,
        restDuration: Int = 0,
        setGroup: WorkoutSetGroup? = nil
    ) -> StandardSet {
        let standardSet = StandardSet(context: context)
        standardSet.id = UUID()
        standardSet.restDuration = Int64(restDuration)
        setGroup?.sets.append(standardSet)
        standardSet.insertEntry(
            from: SetEntryValues(
                type: factoryEntryType(
                    repetitions: repetitions, weight: weight, exercise: setGroup?.exercise
                ),
                order: 0,
                repetitions: Int64(repetitions),
                weight: Int64(weight),
                duration: 0,
                exercise: setGroup?.exercise
            )
        )
        return standardSet
    }

    @discardableResult
    func newDropSet(
        repetitions: [Int] = [0],
        weights: [Int] = [0],
        restDuration: Int = 0,
        setGroup: WorkoutSetGroup? = nil
    ) -> DropSet {
        let dropSet = DropSet(context: context)
        dropSet.id = UUID()
        dropSet.restDuration = Int64(restDuration)
        setGroup?.sets.append(dropSet)
        let dropCount = max(repetitions.count, weights.count, 1)
        for index in 0..<dropCount {
            let dropRepetitions = repetitions.value(at: index) ?? 0
            let dropWeight = weights.value(at: index) ?? 0
            dropSet.insertEntry(
                from: SetEntryValues(
                    type: factoryEntryType(
                        repetitions: dropRepetitions, weight: dropWeight,
                        exercise: setGroup?.exercise
                    ),
                    order: Int64(index),
                    repetitions: Int64(dropRepetitions),
                    weight: Int64(dropWeight),
                    duration: 0,
                    exercise: setGroup?.exercise
                )
            )
        }
        return dropSet
    }

    @discardableResult
    func newDropSet(
        from templateDropSet: TemplateDropSet,
        setGroup: WorkoutSetGroup? = nil
    ) -> DropSet {
        let dropSet = DropSet(context: context)
        dropSet.id = UUID()
        dropSet.restDuration = templateDropSet.restDuration
        setGroup?.sets.append(dropSet)
        // Mirror the template's planned structure — drop count and entry types — with empty
        // values for the athlete to fill in.
        for value in templateDropSet.entryValues {
            dropSet.insertEntry(
                from: SetEntryValues(
                    type: value.type,
                    order: value.order,
                    repetitions: 0,
                    weight: 0,
                    duration: 0,
                    exercise: setGroup?.exercise
                )
            )
        }
        return dropSet
    }

    @discardableResult
    func newSuperSet(
        repetitionsFirstExercise: Int = 0,
        repetitionsSecondExercise: Int = 0,
        weightFirstExercise: Int = 0,
        weightSecondExercise: Int = 0,
        restDuration: Int = 0,
        setGroup: WorkoutSetGroup? = nil
    ) -> SuperSet {
        let superSet = SuperSet(context: context)
        superSet.id = UUID()
        superSet.restDuration = Int64(restDuration)
        setGroup?.sets.append(superSet)
        superSet.insertEntry(
            from: SetEntryValues(
                type: factoryEntryType(
                    repetitions: repetitionsFirstExercise, weight: weightFirstExercise,
                    exercise: setGroup?.exercise
                ),
                order: 0,
                repetitions: Int64(repetitionsFirstExercise),
                weight: Int64(weightFirstExercise),
                duration: 0,
                exercise: setGroup?.exercise
            )
        )
        superSet.insertEntry(
            from: SetEntryValues(
                type: factoryEntryType(
                    repetitions: repetitionsSecondExercise, weight: weightSecondExercise,
                    exercise: setGroup?.secondaryExercise
                ),
                order: 1,
                repetitions: Int64(repetitionsSecondExercise),
                weight: Int64(weightSecondExercise),
                duration: 0,
                exercise: setGroup?.secondaryExercise
            )
        )
        return superSet
    }

    @discardableResult
    func newSuperSet(
        from templateSuperSet: TemplateSuperSet,
        setGroup: WorkoutSetGroup? = nil
    ) -> SuperSet {
        let superSet = newSuperSet(
            restDuration: Int(templateSuperSet.restDuration),
            setGroup: setGroup
        )
        setGroup?.secondaryExercise = templateSuperSet.secondaryExercise
        return superSet
    }

    @discardableResult
    func newExercise(
        name: String = "",
        muscleGroup: MuscleGroup? = nil,
        measurementType: SetMeasurementType = .repsAndWeight,
        setGroups: [WorkoutSetGroup] = []
    ) -> Exercise {
        let exercise = Exercise(context: context)
        exercise.id = UUID()
        exercise.name = name
        exercise.muscleGroup = muscleGroup
        exercise.measurementType = measurementType
        setGroups.forEach { $0.exercise = exercise }
        return exercise
    }

    // MARK: - Template Entitiy Creation

    @discardableResult
    func newTemplate(
        name: String = "",
        setGroups: [TemplateSetGroup] = [TemplateSetGroup]()
    ) -> Template {
        let template = Template(context: context)
        template.id = UUID()
        template.name = name
        template.creationDate = Date.now
        template.setGroups = setGroups
        return template
    }

    @discardableResult
    func newTemplate(from workout: Workout) -> Template {
        let template = newTemplate(name: workout.name ?? "")
        workout.template = template
        for setGroup in workout.setGroups {
            let templateSetGroup = newTemplateSetGroup(
                createFirstSetAutomatically: false,
                exercise: setGroup.exercise,
                template: template
            )
            for workoutSet in setGroup.sets {
                newTemplateSet(from: workoutSet, templateSetGroup: templateSetGroup)
            }
        }
        return template
    }

    @discardableResult
    func newTemplateSetGroup(
        templateSets: [TemplateSet]? = nil,
        createFirstSetAutomatically: Bool = true,
        exercise: Exercise? = nil,
        template: Template? = nil
    ) -> TemplateSetGroup {
        let templateSetGroup = TemplateSetGroup(context: context)
        templateSetGroup.id = UUID()
        if let templateSets = templateSets, !templateSets.isEmpty {
            templateSetGroup.sets = templateSets
        } else if createFirstSetAutomatically {
            newTemplateStandardSet(setGroup: templateSetGroup)
        }
        templateSetGroup.exercise = exercise
        template?.setGroups.append(templateSetGroup)
        return templateSetGroup
    }

    @discardableResult
    func newTemplateSet(
        from workoutSet: WorkoutSet,
        templateSetGroup: TemplateSetGroup? = nil
    ) -> TemplateSet {
        let templateSet: TemplateSet
        if workoutSet is DropSet {
            templateSet = TemplateDropSet(context: context)
        } else if workoutSet is SuperSet {
            templateSet = TemplateSuperSet(context: context)
        } else {
            templateSet = TemplateStandardSet(context: context)
        }
        templateSet.id = UUID()
        templateSet.restDuration = workoutSet.restDuration
        templateSetGroup?.sets.append(templateSet)
        if workoutSet is SuperSet {
            templateSetGroup?.secondaryExercise = workoutSet.setGroup?.secondaryExercise
        }
        // Carry the performed entries over as the template's planned entries. Exercise
        // attribution is re-resolved against the template's own group.
        for value in workoutSet.entryValues {
            var resolved = value
            resolved.exercise =
                templateSet.positionalExercise(forOrder: value.order) ?? value.exercise
            templateSet.insertEntry(from: resolved)
        }
        return templateSet
    }

    @discardableResult
    func newTemplateStandardSet(
        repetitions: Int = 0,
        weight: Int = 0,
        restDuration: Int = 0,
        setGroup: TemplateSetGroup? = nil
    ) -> TemplateStandardSet {
        let templateSet = TemplateStandardSet(context: context)
        templateSet.id = UUID()
        templateSet.restDuration = Int64(restDuration)
        setGroup?.sets.append(templateSet)
        templateSet.insertEntry(
            from: SetEntryValues(
                type: factoryEntryType(
                    repetitions: repetitions, weight: weight, exercise: setGroup?.exercise
                ),
                order: 0,
                repetitions: Int64(repetitions),
                weight: Int64(weight),
                duration: 0,
                exercise: setGroup?.exercise
            )
        )
        return templateSet
    }

    @discardableResult
    func newTemplateDropSet(
        repetitions: [Int] = [0],
        weights: [Int] = [0],
        restDuration: Int = 0,
        templateSetGroup: TemplateSetGroup? = nil
    ) -> TemplateDropSet {
        let templateDropSet = TemplateDropSet(context: context)
        templateDropSet.id = UUID()
        templateDropSet.restDuration = Int64(restDuration)
        templateSetGroup?.sets.append(templateDropSet)
        let dropCount = max(repetitions.count, weights.count, 1)
        for index in 0..<dropCount {
            let dropRepetitions = repetitions.value(at: index) ?? 0
            let dropWeight = weights.value(at: index) ?? 0
            templateDropSet.insertEntry(
                from: SetEntryValues(
                    type: factoryEntryType(
                        repetitions: dropRepetitions, weight: dropWeight,
                        exercise: templateSetGroup?.exercise
                    ),
                    order: Int64(index),
                    repetitions: Int64(dropRepetitions),
                    weight: Int64(dropWeight),
                    duration: 0,
                    exercise: templateSetGroup?.exercise
                )
            )
        }
        return templateDropSet
    }

    @discardableResult
    func newTemplateSuperSet(
        repetitionsFirstExercise: Int = 0,
        repetitionsSecondExercise: Int = 0,
        weightFirstExercise: Int = 0,
        weightSecondExercise: Int = 0,
        restDuration: Int = 0,
        setGroup: TemplateSetGroup? = nil
    ) -> TemplateSuperSet {
        let templateSuperSet = TemplateSuperSet(context: context)
        templateSuperSet.id = UUID()
        templateSuperSet.restDuration = Int64(restDuration)
        setGroup?.sets.append(templateSuperSet)
        templateSuperSet.insertEntry(
            from: SetEntryValues(
                type: factoryEntryType(
                    repetitions: repetitionsFirstExercise, weight: weightFirstExercise,
                    exercise: setGroup?.exercise
                ),
                order: 0,
                repetitions: Int64(repetitionsFirstExercise),
                weight: Int64(weightFirstExercise),
                duration: 0,
                exercise: setGroup?.exercise
            )
        )
        templateSuperSet.insertEntry(
            from: SetEntryValues(
                type: factoryEntryType(
                    repetitions: repetitionsSecondExercise, weight: weightSecondExercise,
                    exercise: setGroup?.secondaryExercise
                ),
                order: 1,
                repetitions: Int64(repetitionsSecondExercise),
                weight: Int64(weightSecondExercise),
                duration: 0,
                exercise: setGroup?.secondaryExercise
            )
        )
        return templateSuperSet
    }
}
