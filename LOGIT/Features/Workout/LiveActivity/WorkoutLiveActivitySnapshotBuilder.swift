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
            let focusesSecondExercise = superSet.repetitionsFirstExercise > 0
            primaryExerciseName = focusesSecondExercise ? partnerExerciseName : firstExerciseName
            secondaryExerciseName = focusesSecondExercise ? firstExerciseName : partnerExerciseName
            supersetPartnerIsLeading = focusesSecondExercise
            primaryMetrics = focusesSecondExercise
                ? currentDisplaySuperSecondary(superSet, templateSet: templateSet)
                : currentDisplaySuperPrimary(superSet, templateSet: templateSet)
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

    private struct MetricValues {
        let repetitions: [Int64]
        let weights: [Int64]

        var hasEntry: Bool {
            repetitions.contains(where: { $0 > 0 }) || weights.contains(where: { $0 > 0 })
        }
    }

    private enum FocusedSupersetExercise {
        case first
        case second
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

    private static var repsLocalizedUnit: String {
        NSLocalizedString("reps", comment: "")
    }

    private static var liveActivityWeightUnit: String {
        WeightUnit.used.rawValue
    }

    private static func primaryMetricDisplay(
        for workoutSet: WorkoutSet,
        templateSet: TemplateSet?
    ) -> ExerciseMetricDisplay {
        if let standardSet = workoutSet as? StandardSet {
            return currentDisplayStandard(standardSet, templateSet: templateSet)
        }
        if let dropSet = workoutSet as? DropSet {
            return currentDisplayDrop(dropSet, templateSet: templateSet)
        }
        if let superSet = workoutSet as? SuperSet {
            return currentDisplaySuperPrimary(superSet, templateSet: templateSet)
        }
        return .emptyForLiveActivity()
    }

    private static func secondaryMetricDisplay(
        for workoutSet: WorkoutSet,
        templateSet: TemplateSet?
    ) -> ExerciseMetricDisplay? {
        guard let superSet = workoutSet as? SuperSet else {
            return nil
        }
        return currentDisplaySuperSecondary(superSet, templateSet: templateSet)
    }

    private static func currentDisplayStandard(
        _ standardSet: StandardSet,
        templateSet: TemplateSet?
    ) -> ExerciseMetricDisplay {
        let template = templateSet as? TemplateStandardSet
        let rAct = standardSet.repetitions
        let wAct = standardSet.weight
        let rShow = rAct > 0 ? rAct : (template?.repetitions ?? 0)
        let wShowGrams = wAct > 0 ? wAct : (template?.weight ?? 0)
        return ExerciseMetricDisplay(
            repetitionSegments: [String(rShow)],
            repetitionSegmentPlaceholders: [rAct == 0],
            repetitionsUnit: repsLocalizedUnit,
            weightSegments: [formatWeightForDisplay(wShowGrams)],
            weightSegmentPlaceholders: [wAct == 0],
            weightUnit: liveActivityWeightUnit
        )
    }

    private static func currentDisplayDrop(
        _ dropSet: DropSet,
        templateSet: TemplateSet?
    ) -> ExerciseMetricDisplay {
        let count = dropSet.repetitions?.count ?? 0
        guard count > 0 else { return .emptyForLiveActivity() }
        let template = templateSet as? TemplateDropSet
        var rSeg: [String] = []
        var rPh: [Bool] = []
        var wSeg: [String] = []
        var wPh: [Bool] = []
        for i in 0 ..< count {
            let ra = dropSet.repetitions?.value(at: i) ?? 0
            let tr = template?.repetitions?.value(at: i) ?? 0
            let rDisp = ra > 0 ? ra : tr
            rSeg.append(String(rDisp))
            rPh.append(ra == 0)

            let wa = dropSet.weights?.value(at: i) ?? 0
            let tw = template?.weights?.value(at: i) ?? 0
            let wDisp = wa > 0 ? wa : tw
            wSeg.append(formatWeightForDisplay(wDisp))
            wPh.append(wa == 0)
        }
        return ExerciseMetricDisplay(
            repetitionSegments: rSeg,
            repetitionSegmentPlaceholders: rPh,
            repetitionsUnit: repsLocalizedUnit,
            weightSegments: wSeg,
            weightSegmentPlaceholders: wPh,
            weightUnit: liveActivityWeightUnit
        )
    }

    private static func currentDisplaySuperPrimary(
        _ superSet: SuperSet,
        templateSet: TemplateSet?
    ) -> ExerciseMetricDisplay {
        let template = templateSet as? TemplateSuperSet
        let rAct = superSet.repetitionsFirstExercise
        let wAct = superSet.weightFirstExercise
        let rShow = rAct > 0 ? rAct : (template?.repetitionsFirstExercise ?? 0)
        let wShow = wAct > 0 ? wAct : (template?.weightFirstExercise ?? 0)
        return ExerciseMetricDisplay(
            repetitionSegments: [String(rShow)],
            repetitionSegmentPlaceholders: [rAct == 0],
            repetitionsUnit: repsLocalizedUnit,
            weightSegments: [formatWeightForDisplay(wShow)],
            weightSegmentPlaceholders: [wAct == 0],
            weightUnit: liveActivityWeightUnit
        )
    }

    private static func currentDisplaySuperSecondary(
        _ superSet: SuperSet,
        templateSet: TemplateSet?
    ) -> ExerciseMetricDisplay {
        let template = templateSet as? TemplateSuperSet
        let rAct = superSet.repetitionsSecondExercise
        let wAct = superSet.weightSecondExercise
        let rShow = rAct > 0 ? rAct : (template?.repetitionsSecondExercise ?? 0)
        let wShow = wAct > 0 ? wAct : (template?.weightSecondExercise ?? 0)
        return ExerciseMetricDisplay(
            repetitionSegments: [String(rShow)],
            repetitionSegmentPlaceholders: [rAct == 0],
            repetitionsUnit: repsLocalizedUnit,
            weightSegments: [formatWeightForDisplay(wShow)],
            weightSegmentPlaceholders: [wAct == 0],
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

        if let superSet = previousSet as? SuperSet, let focusedSupersetExercise {
            let focusedDisplay: ExerciseMetricDisplay
            switch focusedSupersetExercise {
            case .first:
                focusedDisplay = metricDisplayEntriesOnly(
                    actual: MetricValues(
                        repetitions: [superSet.repetitionsFirstExercise],
                        weights: [superSet.weightFirstExercise]
                    )
                )
            case .second:
                focusedDisplay = metricDisplayEntriesOnly(
                    actual: MetricValues(
                        repetitions: [superSet.repetitionsSecondExercise],
                        weights: [superSet.weightSecondExercise]
                    )
                )
            }
            return (focusedDisplay.isEmpty ? nil : focusedDisplay, nil)
        }

        let primary = primaryMetricEntriesOnly(for: previousSet)
        let primaryOut = primary.isEmpty ? nil : primary
        let secondaryOut = secondaryMetricEntriesOnly(for: previousSet)
        return (primaryOut, secondaryOut)
    }

    private static func primaryMetricEntriesOnly(for workoutSet: WorkoutSet) -> ExerciseMetricDisplay {
        if let standardSet = workoutSet as? StandardSet {
            return metricDisplayEntriesOnly(
                actual: MetricValues(
                    repetitions: [standardSet.repetitions],
                    weights: [standardSet.weight]
                )
            )
        }
        if let dropSet = workoutSet as? DropSet {
            return metricDisplayEntriesOnly(
                actual: MetricValues(
                    repetitions: dropSet.repetitions ?? [],
                    weights: dropSet.weights ?? []
                )
            )
        }
        if let superSet = workoutSet as? SuperSet {
            return metricDisplayEntriesOnly(
                actual: MetricValues(
                    repetitions: [superSet.repetitionsFirstExercise],
                    weights: [superSet.weightFirstExercise]
                )
            )
        }
        return .emptyForLiveActivity()
    }

    private static func secondaryMetricEntriesOnly(for workoutSet: WorkoutSet) -> ExerciseMetricDisplay? {
        guard let superSet = workoutSet as? SuperSet else { return nil }
        let display = metricDisplayEntriesOnly(
            actual: MetricValues(
                repetitions: [superSet.repetitionsSecondExercise],
                weights: [superSet.weightSecondExercise]
            )
        )
        return display.isEmpty ? nil : display
    }

    private static func metricDisplayEntriesOnly(actual: MetricValues) -> ExerciseMetricDisplay {
        guard actual.hasEntry else {
            return .emptyForLiveActivity()
        }
        let repValues = actual.repetitions.filter { $0 > 0 }
        let wValues = actual.weights.filter { $0 > 0 }
        let rSeg = repValues.map(String.init)
        let rPh = Array(repeating: false, count: rSeg.count)
        let wSeg = wValues.map(formatWeightForDisplay)
        let wPh = Array(repeating: false, count: wSeg.count)
        return ExerciseMetricDisplay(
            repetitionSegments: rSeg,
            repetitionSegmentPlaceholders: rPh,
            repetitionsUnit: repsLocalizedUnit,
            weightSegments: wSeg,
            weightSegmentPlaceholders: wPh,
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
