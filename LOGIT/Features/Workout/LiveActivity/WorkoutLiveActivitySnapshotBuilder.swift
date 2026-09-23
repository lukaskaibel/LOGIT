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
    let themeToken: WorkoutLiveActivityThemeToken
    let chronoChip: WorkoutLiveActivityChronoChip?
    let hasPendingSet: Bool

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
            themeToken: themeToken,
            chronoChip: chronoChip,
            hasPendingSet: hasPendingSet
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
                themeToken: .neutral,
                chronoChip: chronoChip,
                hasPendingSet: false
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
        let themeMuscle: MuscleGroup?

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
            themeMuscle = focusesSecondExercise
                ? currentContext.setGroup.secondaryExercise?.muscleGroup
                : currentContext.setGroup.exercise?.muscleGroup
        } else {
            primaryExerciseName = firstExerciseName
            secondaryExerciseName = partnerExerciseName
            supersetPartnerIsLeading = false
            primaryMetrics = primaryMetricDisplay(for: currentContext.set, templateSet: templateSet)
            themeMuscle = currentContext.setGroup.exercise?.muscleGroup
        }

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
            themeToken: themeToken(for: themeMuscle),
            chronoChip: chronoChip,
            hasPendingSet: workout.sets.contains { setNeedsLiveActivityAttention($0) }
        )
    }

    private struct CurrentSetContext {
        let setGroup: WorkoutSetGroup
        let set: WorkoutSet
        let exerciseIndex: Int
        let setIndex: Int
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

    private static var liveActivityWeightUnit: String {
        WeightUnit.used.rawValue
    }

    /// The unit label for an entry's performance slot: reps for rep-based entries, the
    /// distance unit for distance-tracking ones (distance is their primary field on this
    /// glanceable surface), and none for durations — those are written "1:30", which carries
    /// its own separator.
    private static func performanceLocalizedUnit(for value: SetEntryValues?) -> String {
        guard let value else { return repsLocalizedUnit }
        if value.type.usesRepetitions { return repsLocalizedUnit }
        if let distanceStyle = value.type.distanceStyle(for: value.exercise) {
            return distanceUnitTitle(for: distanceStyle)
        }
        return ""
    }

    /// The values shown in the set row: for compound sets the first exercise's entry (the
    /// focused-side variant is built inline in `build`), otherwise all entries (a drop set shows
    /// one segment per drop).
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
            } else if let distanceStyle = value.type.distanceStyle(for: value.exercise) {
                let shown = value.distanceMm > 0 ? value.distanceMm : (template?.distanceMm ?? 0)
                performanceSegments.append(formatDistanceForDisplay(shown, style: distanceStyle))
                performancePlaceholders.append(value.distanceMm == 0)
            } else if value.type.usesDuration {
                let shown = value.durationMs > 0 ? value.durationMs : (template?.durationMs ?? 0)
                performanceSegments.append(formatDurationForDisplay(milliseconds: Int64(shown)))
                performancePlaceholders.append(value.durationMs == 0)
            }
            if value.type.usesWeight {
                // Any weight but 0 was entered: assistance is stored as a negative weight, and a
                // `> 0` test showed the template's plan — or a solid "0 KG" — in place of a logged
                // −20 kg.
                let shown = value.weight != 0 ? value.weight : (template?.weight ?? 0)
                weightSegments.append(formatWeightForDisplay(shown))
                weightPlaceholders.append(value.weight == 0)
            }
        }
        return ExerciseMetricDisplay(
            repetitionSegments: performanceSegments,
            repetitionSegmentPlaceholders: performancePlaceholders,
            repetitionsUnit: performanceLocalizedUnit(for: values.first),
            weightSegments: weightSegments,
            weightSegmentPlaceholders: weightPlaceholders,
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
