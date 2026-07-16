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
    let supersetPartnerIsLeading: Bool
    let primaryMetrics: ExerciseMetricDisplay
    let secondaryMetrics: ExerciseMetricDisplay?
    let previousPrimaryMetrics: ExerciseMetricDisplay?
    let previousSecondaryMetrics: ExerciseMetricDisplay?
    let themeToken: WorkoutLiveActivityThemeToken
    let chronoChip: WorkoutLiveActivityChronoChip?

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
            supersetPartnerIsLeading: supersetPartnerIsLeading,
            primaryMetrics: primaryMetrics,
            secondaryMetrics: secondaryMetrics,
            previousPrimaryMetrics: previousPrimaryMetrics,
            previousSecondaryMetrics: previousSecondaryMetrics,
            themeToken: themeToken,
            chronoChip: chronoChip
        )
    }
}

enum WorkoutLiveActivitySnapshotBuilder {
    static func build(for workout: Workout, chronoChip: WorkoutLiveActivityChronoChip? = nil) -> WorkoutLiveActivitySnapshot? {
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
                supersetPartnerIsLeading: false,
                primaryMetrics: .emptyForLiveActivity(),
                secondaryMetrics: nil,
                previousPrimaryMetrics: nil,
                previousSecondaryMetrics: nil,
                themeToken: .neutral,
                chronoChip: chronoChip
            )
        }

        let templateSet = templateSet(for: currentContext.set, in: workout)
        let firstExerciseName = currentContext.setGroup.exercise?.displayName
            ?? NSLocalizedString("exercise", comment: "")
        let partnerExerciseName = currentContext.setGroup.secondaryExercise?.displayName

        let primaryExerciseName: String
        let secondaryExerciseName: String?
        let supersetPartnerIsLeading: Bool
        let primaryMetrics: ExerciseMetricDisplay
        let secondaryMetrics: ExerciseMetricDisplay?
        let themeMuscle: MuscleGroup?
        let focusedSupersetExercise: FocusedSupersetExercise?

        if let superSet = currentContext.set as? SuperSet,
           let partnerExerciseName,
           !partnerExerciseName.isEmpty
        {
            let focusesSecondExercise =
                superSet.entryValues.first?.hasPerformanceValue ?? false
            primaryExerciseName = focusesSecondExercise ? partnerExerciseName : firstExerciseName
            secondaryExerciseName = focusesSecondExercise ? firstExerciseName : partnerExerciseName
            supersetPartnerIsLeading = focusesSecondExercise
            let focusedEntryIndex = focusesSecondExercise ? 1 : 0
            primaryMetrics = metricDisplay(
                values: [superSet.entryValues.value(at: focusedEntryIndex)].compactMap { $0 },
                templateValues: [templateSet?.entryValues.value(at: focusedEntryIndex)]
                    .compactMap { $0 }
            )
            secondaryMetrics = nil
            themeMuscle = focusesSecondExercise
                ? currentContext.setGroup.secondaryExercise?.muscleGroup
                : currentContext.setGroup.exercise?.muscleGroup
            focusedSupersetExercise = focusesSecondExercise ? .second : .first
        } else {
            primaryExerciseName = firstExerciseName
            secondaryExerciseName = partnerExerciseName
            supersetPartnerIsLeading = false
            primaryMetrics = primaryMetricDisplay(for: currentContext.set, templateSet: templateSet)
            secondaryMetrics = secondaryMetricDisplay(for: currentContext.set, templateSet: templateSet)
            themeMuscle = currentContext.setGroup.exercise?.muscleGroup
            focusedSupersetExercise = nil
        }

        let (previousPrimaryMetrics, previousSecondaryMetrics) = previousSetMetricDisplays(
            in: currentContext.setGroup,
            beforeSetIndex: currentContext.setIndex,
            focusedSupersetExercise: focusedSupersetExercise
        )

        return WorkoutLiveActivitySnapshot(
            workoutID: workoutID,
            startedAt: startedAt,
            workoutTitle: title,
            exerciseIndex: currentContext.exerciseIndex + 1,
            exerciseCount: workout.setGroups.count,
            setIndex: currentContext.setIndex + 1,
            setCount: currentContext.setGroup.sets.count,
            primaryExerciseName: primaryExerciseName,
            secondaryExerciseName: secondaryExerciseName,
            supersetPartnerIsLeading: supersetPartnerIsLeading,
            primaryMetrics: primaryMetrics,
            secondaryMetrics: secondaryMetrics,
            previousPrimaryMetrics: previousPrimaryMetrics,
            previousSecondaryMetrics: previousSecondaryMetrics,
            themeToken: themeToken(for: themeMuscle),
            chronoChip: chronoChip
        )
    }

    private struct CurrentSetContext {
        let setGroup: WorkoutSetGroup
        let set: WorkoutSet
        let exerciseIndex: Int
        let setIndex: Int
    }

    private enum FocusedSupersetExercise {
        case first
        case second
    }

    private static func currentSetContext(in workout: Workout) -> CurrentSetContext? {
        let setGroups = workout.setGroups
        guard !setGroups.isEmpty else { return nil }

        let hasStarted = workout.sets.contains { setHasStartedForLiveActivity($0) }
        let currentSetGroup: WorkoutSetGroup

        if hasStarted {
            currentSetGroup = setGroups.first(where: { setGroup in
                setGroup.sets.contains { setNeedsLiveActivityAttention($0) }
            }) ?? setGroups.last!
        } else {
            currentSetGroup = setGroups.first!
        }

        guard let exerciseIndex = setGroups.firstIndex(of: currentSetGroup) else {
            return nil
        }

        let currentSet = currentSetGroup.sets.first(where: { setNeedsLiveActivityAttention($0) })
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

    private static func setHasStartedForLiveActivity(_ workoutSet: WorkoutSet) -> Bool {
        workoutSet.hasRepetitionEntry
    }

    /// Supersets stay "current" until both exercise entries are complete, so the Live Activity can hand off from
    /// the first exercise to the second within the same set instead of jumping to the next untouched set.
    private static func setNeedsLiveActivityAttention(_ workoutSet: WorkoutSet) -> Bool {
        if workoutSet is SuperSet {
            return workoutSet.entryValues.contains { !$0.hasPerformanceValue }
        }

        return !workoutSet.hasRepetitionEntry
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

    private static var repsLocalizedUnit: String {
        NSLocalizedString("reps", comment: "")
    }

    private static var secondsLocalizedUnit: String {
        NSLocalizedString("sec", comment: "")
    }

    private static var liveActivityWeightUnit: String {
        WeightUnit.used.rawValue
    }

    /// The values shown on the "current set" side: for compound sets the first exercise's
    /// entry (the focused-side variant is built inline in `build`), otherwise all entries
    /// (a drop set shows one segment per drop).
    private static func primaryMetricDisplay(
        for workoutSet: WorkoutSet,
        templateSet: TemplateSet?
    ) -> ExerciseMetricDisplay {
        if workoutSet is SuperSet {
            return metricDisplay(
                values: [workoutSet.entryValues.first].compactMap { $0 },
                templateValues: [templateSet?.entryValues.first].compactMap { $0 }
            )
        }
        return metricDisplay(
            values: workoutSet.entryValues,
            templateValues: templateSet?.entryValues ?? []
        )
    }

    private static func secondaryMetricDisplay(
        for workoutSet: WorkoutSet,
        templateSet: TemplateSet?
    ) -> ExerciseMetricDisplay? {
        guard workoutSet is SuperSet else {
            return nil
        }
        return metricDisplay(
            values: [workoutSet.entryValues.value(at: 1)].compactMap { $0 },
            templateValues: [templateSet?.entryValues.value(at: 1)].compactMap { $0 }
        )
    }

    /// One display from entry values: the performance segments carry repetitions for
    /// rep-based entries and a formatted duration ("1:30") for time-based ones; the weight
    /// segments only exist for weight-carrying entries. Template values fill untouched
    /// fields as placeholders, position by position.
    private static func metricDisplay(
        values: [SetEntryValues],
        templateValues: [SetEntryValues]
    ) -> ExerciseMetricDisplay {
        guard !values.isEmpty else { return .emptyForLiveActivity() }
        var performanceSegments: [String] = []
        var performancePlaceholders: [Bool] = []
        var weightSegments: [String] = []
        var weightPlaceholders: [Bool] = []
        for (index, value) in values.enumerated() {
            let template = templateValues.value(at: index)
            if value.type.usesRepetitions {
                let shown = value.repetitions > 0
                    ? value.repetitions : (template?.repetitions ?? 0)
                performanceSegments.append(String(shown))
                performancePlaceholders.append(value.repetitions == 0)
            } else if value.type.usesDuration {
                let shown = value.duration > 0 ? value.duration : (template?.duration ?? 0)
                performanceSegments.append(String(shown))
                performancePlaceholders.append(value.duration == 0)
            }
            if value.type.usesWeight {
                let shown = value.weight > 0 ? value.weight : (template?.weight ?? 0)
                weightSegments.append(formatWeightForDisplay(shown))
                weightPlaceholders.append(value.weight == 0)
            }
        }
        let usesRepetitions = values.first?.type.usesRepetitions ?? true
        return ExerciseMetricDisplay(
            repetitionSegments: performanceSegments,
            repetitionSegmentPlaceholders: performancePlaceholders,
            repetitionsUnit: usesRepetitions ? repsLocalizedUnit : secondsLocalizedUnit,
            weightSegments: weightSegments,
            weightSegmentPlaceholders: weightPlaceholders,
            weightUnit: liveActivityWeightUnit
        )
    }

    private static func previousSetMetricDisplays(
        in setGroup: WorkoutSetGroup,
        beforeSetIndex: Int,
        focusedSupersetExercise: FocusedSupersetExercise?
    ) -> (ExerciseMetricDisplay?, ExerciseMetricDisplay?) {
        guard beforeSetIndex > 0 else { return (nil, nil) }
        let sets = setGroup.sets
        guard beforeSetIndex <= sets.count else { return (nil, nil) }
        let previousSet = sets[beforeSetIndex - 1]
        let previousValues = previousSet.entryValues

        if previousSet is SuperSet, let focusedSupersetExercise {
            let focusedEntryIndex = focusedSupersetExercise == .first ? 0 : 1
            let focusedDisplay = metricDisplayEntriesOnly(
                values: [previousValues.value(at: focusedEntryIndex)].compactMap { $0 }
            )
            return (focusedDisplay.isEmpty ? nil : focusedDisplay, nil)
        }

        let primaryValues = previousSet is SuperSet
            ? [previousValues.first].compactMap { $0 } : previousValues
        let primary = metricDisplayEntriesOnly(values: primaryValues)
        let primaryOut = primary.isEmpty ? nil : primary
        let secondaryOut: ExerciseMetricDisplay?
        if previousSet is SuperSet {
            let secondary = metricDisplayEntriesOnly(
                values: [previousValues.value(at: 1)].compactMap { $0 }
            )
            secondaryOut = secondary.isEmpty ? nil : secondary
        } else {
            secondaryOut = nil
        }
        return (primaryOut, secondaryOut)
    }

    /// Like `metricDisplay(values:templateValues:)` but for the *previous* set's summary:
    /// only recorded values appear — no placeholders.
    private static func metricDisplayEntriesOnly(values: [SetEntryValues]) -> ExerciseMetricDisplay {
        var performanceSegments: [String] = []
        var weightSegments: [String] = []
        for value in values {
            if value.type.usesRepetitions, value.repetitions > 0 {
                performanceSegments.append(String(value.repetitions))
            } else if value.type.usesDuration, !value.type.usesRepetitions, value.duration > 0 {
                performanceSegments.append(String(value.duration))
            }
            if value.type.usesWeight, value.weight > 0 {
                weightSegments.append(formatWeightForDisplay(value.weight))
            }
        }
        guard !performanceSegments.isEmpty || !weightSegments.isEmpty else {
            return .emptyForLiveActivity()
        }
        let usesRepetitions = values.first?.type.usesRepetitions ?? true
        return ExerciseMetricDisplay(
            repetitionSegments: performanceSegments,
            repetitionSegmentPlaceholders: Array(repeating: false, count: performanceSegments.count),
            repetitionsUnit: usesRepetitions ? repsLocalizedUnit : secondsLocalizedUnit,
            weightSegments: weightSegments,
            weightSegmentPlaceholders: Array(repeating: false, count: weightSegments.count),
            weightUnit: liveActivityWeightUnit
        )
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
