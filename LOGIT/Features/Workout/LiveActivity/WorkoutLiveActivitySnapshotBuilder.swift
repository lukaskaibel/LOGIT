//
//  WorkoutLiveActivitySnapshotBuilder.swift
//  LOGIT
//
//  Created by Codex on 28.03.26.
//

import Foundation

struct WorkoutLiveActivitySnapshot: Equatable {
    let workoutID: UUID
    let startedAt: Date
    let workoutTitle: String
    let exerciseIndex: Int
    let exerciseCount: Int
    let setIndex: Int
    let setCount: Int
    let primaryExerciseName: String
    let secondaryExerciseName: String?
    let primaryMetrics: ExerciseMetricDisplay
    let secondaryMetrics: ExerciseMetricDisplay?
    let themeToken: WorkoutLiveActivityThemeToken

    var attributes: WorkoutLiveActivityAttributes {
        WorkoutLiveActivityAttributes(
            workoutID: workoutID,
            startedAt: startedAt
        )
    }

    var contentState: WorkoutLiveActivityAttributes.ContentState {
        WorkoutLiveActivityAttributes.ContentState(
            workoutTitle: workoutTitle,
            exerciseIndex: exerciseIndex,
            exerciseCount: exerciseCount,
            setIndex: setIndex,
            setCount: setCount,
            primaryExerciseName: primaryExerciseName,
            secondaryExerciseName: secondaryExerciseName,
            primaryMetrics: primaryMetrics,
            secondaryMetrics: secondaryMetrics,
            themeToken: themeToken
        )
    }
}

enum WorkoutLiveActivitySnapshotBuilder {
    static func build(for workout: Workout) -> WorkoutLiveActivitySnapshot? {
        guard let workoutID = workout.id, let startedAt = workout.date else {
            return nil
        }

        let title = resolvedWorkoutTitle(for: workout, startedAt: startedAt)

        guard let currentContext = currentSetContext(in: workout) else {
            return WorkoutLiveActivitySnapshot(
                workoutID: workoutID,
                startedAt: startedAt,
                workoutTitle: title,
                exerciseIndex: 0,
                exerciseCount: workout.setGroups.count,
                setIndex: 0,
                setCount: 0,
                primaryExerciseName: NSLocalizedString("addExercise", comment: ""),
                secondaryExerciseName: nil,
                primaryMetrics: ExerciseMetricDisplay(repetitionsText: nil, weightText: nil),
                secondaryMetrics: nil,
                themeToken: .neutral
            )
        }

        let templateSet = templateSet(for: currentContext.set, in: workout)
        let primaryMetrics = primaryMetricDisplay(
            for: currentContext.set,
            templateSet: templateSet
        )
        let secondaryMetrics = secondaryMetricDisplay(
            for: currentContext.set,
            templateSet: templateSet
        )

        return WorkoutLiveActivitySnapshot(
            workoutID: workoutID,
            startedAt: startedAt,
            workoutTitle: title,
            exerciseIndex: currentContext.exerciseIndex + 1,
            exerciseCount: workout.setGroups.count,
            setIndex: currentContext.setIndex + 1,
            setCount: currentContext.setGroup.sets.count,
            primaryExerciseName: currentContext.setGroup.exercise?.displayName
                ?? NSLocalizedString("exercise", comment: ""),
            secondaryExerciseName: currentContext.setGroup.secondaryExercise?.displayName,
            primaryMetrics: primaryMetrics,
            secondaryMetrics: secondaryMetrics,
            themeToken: themeToken(for: currentContext.setGroup.exercise?.muscleGroup)
        )
    }

    private struct CurrentSetContext {
        let setGroup: WorkoutSetGroup
        let set: WorkoutSet
        let exerciseIndex: Int
        let setIndex: Int
    }

    private struct MetricValues {
        let repetitions: [Int64]
        let weights: [Int64]

        var hasEntry: Bool {
            repetitions.contains(where: { $0 > 0 }) || weights.contains(where: { $0 > 0 })
        }
    }

    private static func currentSetContext(in workout: Workout) -> CurrentSetContext? {
        let setGroups = workout.setGroups
        guard !setGroups.isEmpty else { return nil }

        let hasStarted = workout.sets.contains { $0.hasRepetitionEntry }
        let currentSetGroup: WorkoutSetGroup

        if hasStarted {
            currentSetGroup = setGroups.first(where: { setGroup in
                setGroup.sets.contains { !$0.hasRepetitionEntry }
            }) ?? setGroups.last!
        } else {
            currentSetGroup = setGroups.first!
        }

        guard let exerciseIndex = setGroups.firstIndex(of: currentSetGroup) else {
            return nil
        }

        let currentSet = currentSetGroup.sets.first(where: { !$0.hasRepetitionEntry })
            ?? currentSetGroup.sets.last

        guard let currentSet, let setIndex = currentSetGroup.sets.firstIndex(of: currentSet) else {
            return nil
        }

        return CurrentSetContext(
            setGroup: currentSetGroup,
            set: currentSet,
            exerciseIndex: exerciseIndex,
            setIndex: setIndex
        )
    }

    private static func templateSet(for workoutSet: WorkoutSet, in workout: Workout) -> TemplateSet? {
        guard
            let template = workout.template,
            let setGroup = workoutSet.setGroup,
            let groupIndex = workout.index(of: setGroup),
            let setIndex = setGroup.index(of: workoutSet)
        else {
            return nil
        }

        return template.setGroups.value(at: groupIndex)?.sets.value(at: setIndex)
    }

    private static func primaryMetricDisplay(
        for workoutSet: WorkoutSet,
        templateSet: TemplateSet?
    ) -> ExerciseMetricDisplay {
        if let standardSet = workoutSet as? StandardSet {
            return metricDisplay(
                actual: MetricValues(
                    repetitions: [standardSet.repetitions],
                    weights: [standardSet.weight]
                ),
                placeholder: standardMetricValues(from: templateSet)
            )
        }

        if let dropSet = workoutSet as? DropSet {
            return metricDisplay(
                actual: MetricValues(
                    repetitions: dropSet.repetitions ?? [],
                    weights: dropSet.weights ?? []
                ),
                placeholder: dropMetricValues(from: templateSet)
            )
        }

        if let superSet = workoutSet as? SuperSet {
            return metricDisplay(
                actual: MetricValues(
                    repetitions: [superSet.repetitionsFirstExercise],
                    weights: [superSet.weightFirstExercise]
                ),
                placeholder: firstSuperSetMetricValues(from: templateSet)
            )
        }

        return ExerciseMetricDisplay(repetitionsText: nil, weightText: nil)
    }

    private static func secondaryMetricDisplay(
        for workoutSet: WorkoutSet,
        templateSet: TemplateSet?
    ) -> ExerciseMetricDisplay? {
        guard let superSet = workoutSet as? SuperSet else {
            return nil
        }

        return metricDisplay(
            actual: MetricValues(
                repetitions: [superSet.repetitionsSecondExercise],
                weights: [superSet.weightSecondExercise]
            ),
            placeholder: secondSuperSetMetricValues(from: templateSet)
        )
    }

    private static func metricDisplay(
        actual: MetricValues,
        placeholder: MetricValues?
    ) -> ExerciseMetricDisplay {
        let source = actual.hasEntry ? actual : (placeholder ?? actual)

        return ExerciseMetricDisplay(
            repetitionsText: repetitionsText(for: source.repetitions),
            weightText: weightText(for: source.weights)
        )
    }

    private static func standardMetricValues(from templateSet: TemplateSet?) -> MetricValues? {
        guard let templateStandardSet = templateSet as? TemplateStandardSet else {
            return nil
        }

        return MetricValues(
            repetitions: [templateStandardSet.repetitions],
            weights: [templateStandardSet.weight]
        )
    }

    private static func dropMetricValues(from templateSet: TemplateSet?) -> MetricValues? {
        guard let templateDropSet = templateSet as? TemplateDropSet else {
            return nil
        }

        return MetricValues(
            repetitions: templateDropSet.repetitions ?? [],
            weights: templateDropSet.weights ?? []
        )
    }

    private static func firstSuperSetMetricValues(from templateSet: TemplateSet?) -> MetricValues? {
        guard let templateSuperSet = templateSet as? TemplateSuperSet else {
            return nil
        }

        return MetricValues(
            repetitions: [templateSuperSet.repetitionsFirstExercise],
            weights: [templateSuperSet.weightFirstExercise]
        )
    }

    private static func secondSuperSetMetricValues(from templateSet: TemplateSet?) -> MetricValues? {
        guard let templateSuperSet = templateSet as? TemplateSuperSet else {
            return nil
        }

        return MetricValues(
            repetitions: [templateSuperSet.repetitionsSecondExercise],
            weights: [templateSuperSet.weightSecondExercise]
        )
    }

    private static func repetitionsText(for repetitions: [Int64]) -> String? {
        let values = repetitions.filter { $0 > 0 }
        guard !values.isEmpty else { return nil }
        let joined = values.map(String.init).joined(separator: " / ")
        return "\(joined) \(NSLocalizedString("reps", comment: ""))"
    }

    private static func weightText(for weights: [Int64]) -> String? {
        let values = weights.filter { $0 > 0 }
        guard !values.isEmpty else { return nil }
        let joined = values.map(formatWeightForDisplay).joined(separator: " / ")
        return "\(joined) \(WeightUnit.used.rawValue)"
    }

    private static func themeToken(for muscleGroup: MuscleGroup?) -> WorkoutLiveActivityThemeToken {
        guard let rawValue = muscleGroup?.rawValue else {
            return .neutral
        }
        return WorkoutLiveActivityThemeToken(rawValue: rawValue) ?? .neutral
    }

    private static func resolvedWorkoutTitle(for workout: Workout, startedAt: Date) -> String {
        let trimmedTitle = workout.name?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if trimmedTitle.isEmpty {
            return Workout.getStandardName(for: startedAt)
        }

        return trimmedTitle
    }
}
