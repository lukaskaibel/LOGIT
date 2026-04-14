//
//  WorkoutLiveActivityManager.swift
//  LOGIT
//
//  Created by Codex on 28.03.26.
//

import ActivityKit
import Combine
import Foundation
import OSLog

@MainActor
final class WorkoutLiveActivityManager: ObservableObject {
    private static let logger = Logger(
        subsystem: ".com.lukaskbl.LOGIT",
        category: "WorkoutLiveActivity"
    )

    private let workoutRecorder: WorkoutRecorder
    private let database: Database
    private let chronograph: Chronograph
    private var cancellables = Set<AnyCancellable>()
    private var latestSnapshot: WorkoutLiveActivitySnapshot?

    init(workoutRecorder: WorkoutRecorder, database: Database, chronograph: Chronograph) {
        self.workoutRecorder = workoutRecorder
        self.database = database
        self.chronograph = chronograph

        observeWorkoutLifecycle()

        Task {
            await reconcileCurrentState()
        }
    }

    private func observeWorkoutLifecycle() {
        workoutRecorder.$workout
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.reconcileCurrentState() }
            }
            .store(in: &cancellables)

        // Chronograph does not publish on each tick; only real changes (start/stop/pause, duration edits, etc.).
        // The Live Activity chip animates countdown/stopwatch text locally via `Text(timerInterval:)` in the widget.
        chronograph.objectWillChange
            .receive(on: RunLoop.main)
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.reconcileCurrentState() }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(
            for: .NSManagedObjectContextObjectsDidChange,
            object: database.context
        )
        .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
        .sink { [weak self] _ in
            guard let self else { return }
            Task { await self.reconcileCurrentState() }
        }
        .store(in: &cancellables)
    }

    private func reconcileCurrentState() async {
        guard let workout = workoutRecorder.workout else {
            latestSnapshot = nil
            await endAllActivities()
            return
        }

        let chip = makeChronoChip()
        guard let snapshot = WorkoutLiveActivitySnapshotBuilder.build(for: workout, chronoChip: chip) else {
            latestSnapshot = nil
            await endAllActivities()
            return
        }

        await upsertActivity(using: snapshot)
    }

    private func makeChronoChip() -> WorkoutLiveActivityChronoChip? {
        switch chronograph.status {
        case .idle:
            return nil
        case .paused:
            return makeChronoChipPaused()
        case .running:
            return makeChronoChipRunning()
        }
    }

    private func makeChronoChipRunning() -> WorkoutLiveActivityChronoChip? {
        let activeRest = workoutRecorder.activeRestTimerSet != nil

        switch chronograph.mode {
        case .timer:
            let displayedRemainingSeconds = max(0, Int(chronograph.seconds.rounded(.down)))
            let endDate = Date().addingTimeInterval(TimeInterval(displayedRemainingSeconds))
            let tintKind: WorkoutLiveActivityChronoTintKind = activeRest ? .restTimer : .manual
            let muscle = activeRest ? muscleThemeToken(for: workoutRecorder.activeRestTimerSet) : nil
            let total = max(Double(Int(chronograph.initialTimerSeconds.rounded(.down))), 0.001)
            return WorkoutLiveActivityChronoChip(
                phase: .timerRunning,
                tintKind: tintKind,
                muscleThemeToken: muscle,
                timerEndDate: endDate,
                timerTotalSeconds: total,
                staticTickSeconds: nil,
                stopwatchStartDate: nil
            )
        case .stopwatch:
            let tintKind: WorkoutLiveActivityChronoTintKind = activeRest ? .restStopwatch : .manual
            let startDate = Date().addingTimeInterval(-chronograph.seconds)
            return WorkoutLiveActivityChronoChip(
                phase: .stopwatchRunning,
                tintKind: tintKind,
                muscleThemeToken: nil,
                timerEndDate: nil,
                timerTotalSeconds: nil,
                staticTickSeconds: nil,
                stopwatchStartDate: startDate
            )
        }
    }

    private func makeChronoChipPaused() -> WorkoutLiveActivityChronoChip? {
        let activeRest = workoutRecorder.activeRestTimerSet != nil
        let roundedSeconds = max(0, Int(chronograph.seconds.rounded(.down)))

        switch chronograph.mode {
        case .timer:
            let tintKind: WorkoutLiveActivityChronoTintKind = activeRest ? .restTimer : .manual
            let muscle = activeRest ? muscleThemeToken(for: workoutRecorder.activeRestTimerSet) : nil
            return WorkoutLiveActivityChronoChip(
                phase: .timerPaused,
                tintKind: tintKind,
                muscleThemeToken: muscle,
                timerEndDate: nil,
                timerTotalSeconds: nil,
                staticTickSeconds: roundedSeconds,
                stopwatchStartDate: nil
            )
        case .stopwatch:
            let tintKind: WorkoutLiveActivityChronoTintKind = activeRest ? .restStopwatch : .manual
            return WorkoutLiveActivityChronoChip(
                phase: .stopwatchPaused,
                tintKind: tintKind,
                muscleThemeToken: nil,
                timerEndDate: nil,
                timerTotalSeconds: nil,
                staticTickSeconds: roundedSeconds,
                stopwatchStartDate: nil
            )
        }
    }

    private func muscleThemeToken(for workoutSet: WorkoutSet?) -> WorkoutLiveActivityThemeToken {
        themeToken(for: workoutSet?.exercise?.muscleGroup)
    }

    private func themeToken(for muscleGroup: MuscleGroup?) -> WorkoutLiveActivityThemeToken {
        guard let rawValue = muscleGroup?.rawValue else {
            return .neutral
        }
        return WorkoutLiveActivityThemeToken(rawValue: rawValue) ?? .neutral
    }

    private func upsertActivity(using snapshot: WorkoutLiveActivitySnapshot) async {
        let matchingActivities = activities(for: snapshot.workoutID)
        let duplicateActivities = Activity<WorkoutLiveActivityAttributes>.activities.filter {
            $0.attributes.workoutID != snapshot.workoutID
        }

        for activity in duplicateActivities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        if let activity = matchingActivities.first {
            if latestSnapshot != snapshot {
                await activity.update(
                    ActivityContent(
                        state: snapshot.contentState,
                        staleDate: nil
                    )
                )
            }

            for duplicate in matchingActivities.dropFirst() {
                await duplicate.end(nil, dismissalPolicy: .immediate)
            }

            latestSnapshot = snapshot
            return
        }

        do {
            _ = try Activity<WorkoutLiveActivityAttributes>.request(
                attributes: snapshot.attributes,
                content: ActivityContent(
                    state: snapshot.contentState,
                    staleDate: nil
                ),
                pushType: nil
            )
            latestSnapshot = snapshot
        } catch {
            Self.logger.error("Failed to request live activity: \(error.localizedDescription)")
        }
    }

    private func endAllActivities() async {
        for activity in Activity<WorkoutLiveActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func activities(for workoutID: UUID) -> [Activity<WorkoutLiveActivityAttributes>] {
        Activity<WorkoutLiveActivityAttributes>.activities.filter {
            $0.attributes.workoutID == workoutID
        }
    }
}
