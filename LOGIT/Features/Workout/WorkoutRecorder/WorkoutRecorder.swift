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

/// How a rest that ends before its timer reaches zero is written down.
enum RestRecordingMode: String, CaseIterable {
    /// The seconds actually spent resting.
    case elapsed
    /// The rest the timer was set to, however early it was stopped.
    case fullDuration
}

/// Why a running rest is ending — it decides what gets recorded.
enum RestEndReason {
    /// The timer counted down to zero.
    case timerCompleted
    /// The athlete stopped it, or finished the workout while it ran.
    case stopped
    /// The next set was logged while it was still running.
    case superseded
    /// The workout is being thrown away — record nothing.
    case workoutDiscarded
}

/// The one place the auto-rest settings are named and read.
///
/// `autoRestEnabled` replaced a pair of mode-scoped switches (`autoTimerEnabled` /
/// `autoStopwatchEnabled`) that could only ever be seen one at a time, so the one you
/// weren't looking at stayed armed invisibly. `migrateLegacySwitchesIfNeeded` folds the
/// old pair into it once, so whatever was on stays on.
enum AutoRestSettings {
    static let enabledKey = "autoRestEnabled"
    static let recordingModeKey = "restRecordingMode"

    private static let legacyTimerKey = "autoTimerEnabled"
    private static let legacyStopwatchKey = "autoStopwatchEnabled"
    private static let legacyMigrationDoneKey = "autoRestSwitchesMerged"

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: enabledKey)
    }

    static func recordingMode(in defaults: UserDefaults = .standard) -> RestRecordingMode {
        defaults.string(forKey: recordingModeKey)
            .flatMap(RestRecordingMode.init(rawValue:)) ?? .elapsed
    }

    /// Folds the two retired switches into the single one, once per install.
    static func migrateLegacySwitchesIfNeeded(in defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: legacyMigrationDoneKey) else { return }
        defaults.set(true, forKey: legacyMigrationDoneKey)

        // Either one having been on means the athlete wanted rests to start by themselves.
        if defaults.bool(forKey: legacyTimerKey) || defaults.bool(forKey: legacyStopwatchKey) {
            defaults.set(true, forKey: enabledKey)
        }

        defaults.removeObject(forKey: legacyTimerKey)
        defaults.removeObject(forKey: legacyStopwatchKey)
    }
}

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

    /// The sets that hold a repetition entry, by their own `id`.
    ///
    /// Not by `objectID`: a set added mid-workout has a temporary one until the autosave hands it a
    /// permanent one, and the same set then read as newly logged — its rest started over, or a newer
    /// set's rest never started.
    func repetitionEnteredSetIDs(in workout: Workout) -> Set<UUID> {
        Set(workout.sets.filter { $0.hasRepetitionEntry }.compactMap(\.id))
    }

    func autoRestTriggerSet(
        in workout: Workout,
        previousRepetitionEntrySetIDs: Set<UUID>,
        preferredSet: WorkoutSet? = nil
    ) -> (triggerSet: WorkoutSet?, repetitionEntrySetIDs: Set<UUID>) {
        let currentRepetitionEntrySetIDs = repetitionEnteredSetIDs(in: workout)
        let newlyEnteredSetIDs = currentRepetitionEntrySetIDs.subtracting(previousRepetitionEntrySetIDs)

        let triggerSet: WorkoutSet?
        if let preferredSet, let id = preferredSet.id, newlyEnteredSetIDs.contains(id) {
            triggerSet = preferredSet
        } else {
            // Choose deterministically based on workout.sets order
            triggerSet = workout.sets.first(where: { $0.id.map(newlyEnteredSetIDs.contains) ?? false })
        }

        // The tally only ever grows. A set whose rest has already started stays in it even
        // while its field is momentarily empty, so correcting a logged set — clearing the
        // reps and typing them again — doesn't count as a fresh entry and re-arm the rest.
        return (triggerSet, previousRepetitionEntrySetIDs.union(currentRepetitionEntrySetIDs))
    }

    /// Returns the applicable auto-rest behavior for the given set.
    /// The set being entered is treated as just completed, so its own rest duration applies.
    func autoRestBehavior(
        forSet workoutSet: WorkoutSet,
        usesStopwatch: Bool,
        autoRestEnabled: Bool,
        timerDuration: Int
    ) -> AutoRestBehavior? {
        // The switch is the only gate. Off means nothing ever starts by itself, whatever
        // rest the set happens to carry — a rest planned in a template still shows under
        // the set and still sets the duration, it just doesn't start anything.
        guard autoRestEnabled else { return nil }

        if usesStopwatch {
            return .stopwatch
        }

        // A rest the set already carries is what it rests for; the sheet's duration is
        // only the fallback for a set that has none.
        if workoutSet.restDurationSeconds > 0 {
            return .timer(workoutSet.restDurationSeconds)
        }

        if timerDuration > 0 {
            return .timer(timerDuration)
        }

        return nil
    }

    /// Records the actual rest duration for a completed set.
    func recordRestDuration(_ seconds: Int, for workoutSet: WorkoutSet) {
        workoutSet.restDurationSeconds = seconds
        objectWillChange.send()
    }

    /// The one way a rest ends. Every exit — the timer running out, either stop button, the
    /// next set being logged, switching between timer and stopwatch, finishing the workout —
    /// comes through here, so they all write the same number down for the same situation.
    ///
    /// Stops the chronograph either way. Safe to call with nothing running.
    ///
    /// Stopping doesn't silence a timer that ran out: for `.timerCompleted` the chronograph has
    /// already handed its ringing alert to its own auto-dismiss (see
    /// `Chronograph.scheduleAlarmAutoDismiss`), so the `cancel()` below leaves the sound to finish,
    /// exactly as a manual timer's does. Every other reason ends a rest that is still counting, and
    /// the same `cancel()` takes its pending alarm down at once.
    func endRest(
        using chronograph: Chronograph,
        reason: RestEndReason,
        recordingMode: RestRecordingMode = .elapsed
    ) {
        // Read before the deferred cancel resets the chronograph.
        let duration = restDuration(for: chronograph, reason: reason, recordingMode: recordingMode)

        defer {
            chronograph.onTimerFired = nil
            chronograph.cancel()
            activeRestTimerSet = nil
        }

        // Nothing to write for a chronograph the athlete started by hand, for a workout that is
        // being thrown away, or for a rest too short to have been one.
        guard reason != .workoutDiscarded, let activeRestSet = activeRestTimerSet, let duration else {
            return
        }

        recordRestDuration(duration, for: activeRestSet)
    }

    /// A measured rest shorter than this isn't recorded.
    ///
    /// Sets logged a few seconds apart, typically all at once after the fact, each cut the
    /// previous rest short. Written down, those 2–3 s replaced a template's planned rest, and
    /// Duplicate and Save as Template carried them on, so the next auto rest was a 3-second
    /// timer. Nobody rests for less than this, so the set keeps the rest it already had.
    static let shortestRecordedRestSeconds = 10

    /// What a rest ending for `reason` is worth, in seconds, or nil when it is not worth recording:
    /// a measured rest shorter than `shortestRecordedRestSeconds`.
    func restDuration(
        for chronograph: Chronograph,
        reason: RestEndReason,
        recordingMode: RestRecordingMode
    ) -> Int? {
        let elapsed = chronograph.elapsedSeconds
        let measured = elapsed >= Self.shortestRecordedRestSeconds ? elapsed : nil

        switch chronograph.mode {
        case .stopwatch:
            // A stopwatch has no prescribed length — measuring is the whole point of it.
            return measured

        case .timer:
            let fullDuration = max(0, Int(chronograph.initialTimerSeconds.rounded(.down)))
            if reason == .timerCompleted {
                return fullDuration
            }
            // The full-duration setting records the timer's value, which is the plan itself —
            // nothing a short interruption could skew.
            return recordingMode == .fullDuration ? fullDuration : measured
        }
    }

    /// Returns the next workout set to be executed. This is the first workout set, that has no workout set with entries after it.
    var nextPerformedWorkoutSet: WorkoutSet? {
        workout?.sets.reversed().reduce(nil) { $1.hasEntry ? $0 : $1 }
    }
}
