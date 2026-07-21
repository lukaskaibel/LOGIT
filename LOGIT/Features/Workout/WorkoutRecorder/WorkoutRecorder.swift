//
//  WorkoutRecorder.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 02.03.24.
//

import Combine
import CoreData
import Foundation
import OSLog

final class WorkoutRecorder: ObservableObject {
    enum AutoRestBehavior: Equatable {
        case timer(Int)
        case stopwatch
    }

    // MARK: - Static

    private static let logger = Logger(subsystem: ".com.lukaskbl.LOGIT", category: "WorkoutRecorder")
    private static let CURRENT_WORKOUT_ID_KEY = "CURRENT_WORKOUT_ID_KEY"

    // MARK: - Public Variables

    @Published var workout: Workout?

    /// The set whose rest timer is currently active (the set that was just completed).
    @Published var activeRestTimerSet: WorkoutSet?

    // MARK: - Private Variables

    private let database: Database
    private let healthKitSync: HealthKitSyncManager?
    private var workoutSetTemplateSetDictionary = [WorkoutSet: TemplateSet]()
    private var cancellable: AnyCancellable?

    // MARK: - Init

    init(database: Database, healthKitSync: HealthKitSyncManager? = nil) {
        self.database = database
        self.healthKitSync = healthKitSync
        workout = (database.fetch(Workout.self, predicate: NSPredicate(format: "isCurrentWorkout == true")) as? [Workout])?.first
    }

    // MARK: - Public Methods

    func startWorkout(from template: Template? = nil) {
        workout = database.newWorkout()
        workout?.isCurrentWorkout = true
        if let template = template {
            template.workouts.append(workout!)
            workout!.name = template.resolvedName
            for templateSetGroup in template.setGroups {
                let setGroup = database.newWorkoutSetGroup(
                    createFirstSetAutomatically: false,
                    exercise: templateSetGroup.exercise,
                    workout: workout
                )
                for templateSet in templateSetGroup.sets {
                    let workoutSet: WorkoutSet
                    if templateSet is TemplateDropSet {
                        workoutSet = database.newDropSet(setGroup: setGroup)
                    } else if templateSet is TemplateSuperSet {
                        workoutSet = database.newSuperSet(setGroup: setGroup)
                        setGroup.secondaryExercise = templateSetGroup.secondaryExercise
                    } else {
                        workoutSet = database.newStandardSet(setGroup: setGroup)
                    }
                    workoutSet.restDuration = templateSet.restDuration
                    // Mirror the template's planned structure — drop count and per-entry
                    // measurement types (a template can override its exercise's default).
                    workoutSet.matchStructure(toEntryValues: templateSet.entryValues)
                    workoutSetTemplateSetDictionary[workoutSet] = templateSet
                }
            }
        }
        database.save()
        objectWillChange.send()
    }

    func saveWorkout() {
        guard let workout = workout else {
            Self.logger.warning("Attempted to save empty workout")
            return
        }

        workout.isCurrentWorkout = false
        objectWillChange.send()
        // Use a local copy of the workout for the deferred cleanup to avoid race conditions
        let workoutCopy = workout
        self.workout = nil

        // The context is main-queue-confined, so the workout must only be read and mutated
        // on its queue — never on a global background queue.
        database.context.perform { [weak self] in
            guard let database = self?.database else {
                Self.logger.error("Failed to clean up workout after finish: self already uninitialized")
                return
            }
            let healthKitSync = self?.healthKitSync

            if workoutCopy.name?.isEmpty ?? true {
                workoutCopy.name = Workout.getStandardName(for: workoutCopy.date!)
            }
            workoutCopy.endDate = .now
            for setGroup in workoutCopy.setGroups {
                if setGroup.setType == .superSet && setGroup.secondaryExercise == nil {
                    database.convertSetGroupToStandardSets(setGroup)
                }
            }

            workoutCopy.exercises.forEach { database.unflagAsTemporary($0) }
            database.deleteAllTemporaryObjects()

            workoutCopy.sets.filter { !$0.hasEntry }.forEach { database.delete($0) }

            // database.delete only enqueues the deletions on the context's queue, so evaluate
            // isEmpty in a follow-up block that runs after they have been processed.
            database.context.perform {
                if workoutCopy.isEmpty {
                    database.delete(workoutCopy, saveContext: true)
                } else {
                    healthKitSync?.syncWorkout(workoutCopy.healthKitPayload)
                }
                database.save()
            }
        }
    }

    func discardWorkout() {
        guard let workout = workout else {
            Self.logger.warning("Attempted to discard empty workout")
            return
        }

        workout.isCurrentWorkout = false
        objectWillChange.send()

        let workoutCopy = workout
        self.workout = nil

        // See saveWorkout: the workout must only be accessed on the context's queue.
        database.context.perform { [weak self] in
            guard let database = self?.database else {
                Self.logger.error("Failed to discard workout: self already uninitialized")
                return
            }
            database.deleteAllTemporaryObjects()

            workoutCopy.sets.filter { !$0.hasEntry }.forEach { database.delete($0) }

            database.delete(workoutCopy, saveContext: true)
        }
    }

    func addSetGroup(with exercise: Exercise) {
        database.newWorkoutSetGroup(
            createFirstSetAutomatically: true,
            exercise: exercise,
            workout: workout
        )
        objectWillChange.send()
    }

    func moveSetGroups(from source: IndexSet, to destination: Int) {
        workout?.setGroups.move(fromOffsets: source, toOffset: destination)
        objectWillChange.send()
    }

    func toggleSetCompleted(for workoutSet: WorkoutSet) {
        if let templateSet = workoutSetTemplateSetDictionary[workoutSet] {
            if workoutSet.hasEntry {
                workoutSet.clearEntries()
            } else {
                workoutSet.match(templateSet)
            }
            objectWillChange.send()
        }
    }

    func toggleCopyPrevious(for workoutSet: WorkoutSet) {
        if workoutSet.hasEntry {
            workoutSet.clearEntries()
        } else {
            guard let previousSet = workoutSet.previousSetInSetGroup else { return }
            workoutSet.match(previousSet)
        }
        objectWillChange.send()
    }

    func templateSet(for workoutSet: WorkoutSet) -> TemplateSet? {
        workoutSetTemplateSetDictionary[workoutSet]
    }

    func repetitionEnteredSetIDs(in workout: Workout) -> Set<NSManagedObjectID> {
        Set(workout.sets.filter { $0.hasRepetitionEntry }.map(\.objectID))
    }

    func autoRestTriggerSet(
        in workout: Workout,
        previousRepetitionEntrySetIDs: Set<NSManagedObjectID>,
        preferredSet: WorkoutSet? = nil
    ) -> (triggerSet: WorkoutSet?, repetitionEntrySetIDs: Set<NSManagedObjectID>) {
        let currentRepetitionEntrySetIDs = repetitionEnteredSetIDs(in: workout)
        let newlyEnteredSetIDs = currentRepetitionEntrySetIDs.subtracting(previousRepetitionEntrySetIDs)

        let triggerSet: WorkoutSet?
        if let preferredSet, newlyEnteredSetIDs.contains(preferredSet.objectID) {
            triggerSet = preferredSet
        } else {
            // Choose deterministically based on workout.sets order
            triggerSet = workout.sets.first(where: { newlyEnteredSetIDs.contains($0.objectID) })
        }

        return (triggerSet, currentRepetitionEntrySetIDs)
    }

    /// Returns the applicable auto-rest behavior for the given set.
    /// The set being entered is treated as just completed, so its own rest duration applies.
    func autoRestBehavior(
        forSet workoutSet: WorkoutSet,
        usesStopwatch: Bool,
        autoTimerEnabled: Bool,
        autoStopwatchEnabled: Bool,
        timerDuration: Int
    ) -> AutoRestBehavior? {
        if usesStopwatch {
            return autoStopwatchEnabled ? .stopwatch : nil
        }

        if workoutSet.restDurationSeconds > 0 {
            return .timer(workoutSet.restDurationSeconds)
        }

        if autoTimerEnabled && timerDuration > 0 {
            return .timer(timerDuration)
        }

        return nil
    }

    /// Compatibility wrapper for call sites that only support automatic timers.
    func applicableRestDuration(
        forSet workoutSet: WorkoutSet,
        autoTimerEnabled: Bool,
        timerDuration: Int
    ) -> Int? {
        switch autoRestBehavior(
            forSet: workoutSet,
            usesStopwatch: false,
            autoTimerEnabled: autoTimerEnabled,
            autoStopwatchEnabled: false,
            timerDuration: timerDuration
        ) {
        case let .timer(seconds):
            return seconds
        case .stopwatch, .none:
            return nil
        }
    }

    /// Records the actual rest duration for a completed set.
    func recordRestDuration(_ seconds: Int, for workoutSet: WorkoutSet) {
        workoutSet.restDurationSeconds = seconds
        objectWillChange.send()
    }

    func finishRestAndStopChronograph(
        using chronograph: Chronograph,
        persistTrackedValue: Bool
    ) {
        defer {
            chronograph.onTimerFired = nil
            chronograph.cancel()
            activeRestTimerSet = nil
        }

        guard persistTrackedValue, let activeRestSet = activeRestTimerSet else { return }

        switch chronograph.mode {
        case .stopwatch:
            let elapsed = chronograph.elapsedSeconds
            if elapsed > 0 {
                recordRestDuration(elapsed, for: activeRestSet)
            }

        case .timer:
            guard activeRestSet.restDurationSeconds == 0 else { return }
            let elapsed = chronograph.elapsedSeconds
            if elapsed > 0 {
                recordRestDuration(elapsed, for: activeRestSet)
            }
        }
    }

    func endStopwatch(using chronograph: Chronograph) {
        guard chronograph.mode == .stopwatch else { return }
        finishRestAndStopChronograph(using: chronograph, persistTrackedValue: true)
    }

    /// Returns the next workout set to be executed. This is the first workout set, that has no workout set with entries after it.
    var nextPerformedWorkoutSet: WorkoutSet? {
        workout?.sets.reversed().reduce(nil) { $1.hasEntry ? $0 : $1 }
    }
}
