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
    private var cancellables = Set<AnyCancellable>()
    private var latestSnapshot: WorkoutLiveActivitySnapshot?

    init(workoutRecorder: WorkoutRecorder, database: Database) {
        self.workoutRecorder = workoutRecorder
        self.database = database

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

        guard let snapshot = WorkoutLiveActivitySnapshotBuilder.build(for: workout) else {
            latestSnapshot = nil
            await endAllActivities()
            return
        }

        await upsertActivity(using: snapshot)
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
