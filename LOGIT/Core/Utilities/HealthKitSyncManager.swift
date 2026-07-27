//
//  HealthKitSyncManager.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 21.07.26.
//

import Foundation
import HealthKit
import OSLog

/// Mirrors finished LOGIT workouts into Apple Health.
///
/// Sync is write-only and one-directional: a workout finished, edited or deleted in LOGIT is
/// pushed to HealthKit, nothing is ever read back. Every exported workout carries the LOGIT
/// workout's UUID as its HealthKit sync identifier, which makes exports idempotent upserts —
/// re-exporting (an edit, or a second backfill run) replaces the Health entry instead of
/// duplicating it, and deletion can target exactly the one exported object.
///
/// All hooks are fire-and-forget and best-effort: recording and saving a workout must never
/// fail or stall because Health access is missing, so failures are only logged.
final class HealthKitSyncManager: ObservableObject {
    /// The data HealthKit needs from a workout. Captured on the Core Data context's queue
    /// (see `Workout.healthKitPayload`) so the export itself is free to run anywhere.
    struct WorkoutPayload: Sendable {
        let id: UUID
        let name: String?
        let start: Date
        let end: Date
        /// The workout's estimated active energy (see `CalorieEstimator`), or `nil` when
        /// estimates are disabled or impossible — the Health entry then has no energy sample.
        var activeKilocalories: Int? = nil
    }

    enum BackfillState: Equatable {
        case idle
        case running(completed: Int, total: Int)
        case finished(exported: Int, skipped: Int)
    }

    // MARK: - Constants

    /// UserDefaults key for the user-facing sync opt-in (see `SettingsScreen`).
    static let syncEnabledKey = "appleHealthSyncEnabled"

    private static let logger = Logger(subsystem: ".com.lukaskbl.LOGIT", category: "HealthKitSyncManager")

    // MARK: - Published

    /// Drives the settings screen's "Export Past Workouts" progress and result label.
    @Published var backfillState: BackfillState = .idle

    // MARK: - Private

    private let healthStore = HKHealthStore()

    // MARK: - Availability & Authorization

    /// `false` on devices without a Health store — the settings section hides itself there.
    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    var isSyncEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.syncEnabledKey)
    }

    /// Share authorization for workouts. Unlike read access, HealthKit does expose whether
    /// writing was denied, so the settings toggle can react to it.
    var isAuthorized: Bool {
        healthStore.authorizationStatus(for: .workoutType()) == .sharingAuthorized
    }

    /// Whether energy samples may be written. Requested together with workout access; users
    /// who granted workouts before calorie estimates existed simply sync without energy until
    /// they re-run the authorization (any toggle-on in settings does).
    var isAuthorizedForActiveEnergy: Bool {
        healthStore.authorizationStatus(for: HKQuantityType(.activeEnergyBurned)) == .sharingAuthorized
    }

    /// Presents the system Health access sheet (only for so-far-undetermined types; later
    /// calls are no-ops) and reports whether workout write access ended up granted.
    func requestAuthorization() async -> Bool {
        guard isHealthDataAvailable else { return false }
        do {
            try await healthStore.requestAuthorization(
                toShare: [.workoutType(), HKQuantityType(.activeEnergyBurned)], read: []
            )
        } catch {
            Self.logger.error(
                "Requesting Health authorization failed: \(String(describing: error), privacy: .public)"
            )
            return false
        }
        return isAuthorized
    }

    // MARK: - Sync Hooks

    /// Exports a workout that was finished or edited on this device. Fire-and-forget.
    func syncWorkout(_ payload: WorkoutPayload?) {
        guard let payload, isSyncEnabled, isAuthorized else { return }
        Task {
            do {
                try await export(payload)
            } catch {
                Self.logger.error(
                    "Exporting workout \(payload.id, privacy: .public) to Apple Health failed: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    /// Removes the exported counterpart of a workout deleted on this device. Fire-and-forget;
    /// deleting a workout that was never exported is a harmless no-op.
    func removeWorkout(id: UUID) {
        guard isSyncEnabled, isAuthorized else { return }
        Task {
            do {
                try await deleteExportedWorkout(id: id)
            } catch {
                // Also lands here when there was nothing to delete (HKError.errorNoData).
                Self.logger.info(
                    "Removing workout \(id, privacy: .public) from Apple Health failed: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    // MARK: - Backfill

    /// Exports the given payloads sequentially, publishing progress for the settings UI.
    /// Idempotent thanks to the sync identifiers — running it twice never duplicates.
    /// `alreadySkipped` counts workouts dropped before export (no logged duration) so the
    /// result reflects the whole history, not just the exportable part.
    @MainActor
    func exportAll(_ payloads: [WorkoutPayload], alreadySkipped: Int = 0) async {
        var exported = 0
        var skipped = alreadySkipped
        backfillState = .running(completed: 0, total: payloads.count)
        for (index, payload) in payloads.enumerated() {
            do {
                try await export(payload)
                exported += 1
            } catch {
                skipped += 1
                Self.logger.error(
                    "Backfill: exporting workout \(payload.id, privacy: .public) failed: \(String(describing: error), privacy: .public)"
                )
            }
            backfillState = .running(completed: index + 1, total: payloads.count)
        }
        backfillState = .finished(exported: exported, skipped: skipped)
    }

    // MARK: - Export Rules

    /// Whether a workout's dates can be represented as a HealthKit workout: it needs an actual
    /// duration, and HealthKit rejects samples that end in the future (the date editor allows
    /// picking one).
    static func isExportable(start: Date?, end: Date?, now: Date = .now) -> Bool {
        guard let start, let end else { return false }
        return start < end && end <= now
    }

    // MARK: - HealthKit Plumbing

    private func export(_ payload: WorkoutPayload) async throws {
        guard Self.isExportable(start: payload.start, end: payload.end) else {
            throw HKError(.errorInvalidArgument)
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        // Any strictly increasing value works; milliseconds keep two saves of the same
        // workout in quick succession (finish, then an immediate edit) distinguishable.
        let syncVersion = Int(Date.now.timeIntervalSince1970 * 1000)
        var metadata: [String: Any] = [
            HKMetadataKeySyncIdentifier: payload.id.uuidString,
            HKMetadataKeySyncVersion: syncVersion,
        ]
        if let name = payload.name, !name.isEmpty {
            metadata[HKMetadataKeyWorkoutBrandName] = name
        }

        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())
        do {
            try await builder.beginCollection(at: payload.start)
            // The estimated active energy rides along as a sample with its own sync
            // identifier, so a re-export replaces the old sample instead of double-counting
            // toward the Move ring.
            if let kilocalories = payload.activeKilocalories, isAuthorizedForActiveEnergy {
                let energySample = HKQuantitySample(
                    type: HKQuantityType(.activeEnergyBurned),
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: Double(kilocalories)),
                    start: payload.start,
                    end: payload.end,
                    metadata: [
                        HKMetadataKeySyncIdentifier: Self.energySyncIdentifier(for: payload.id),
                        HKMetadataKeySyncVersion: syncVersion,
                    ]
                )
                try await builder.addSamples([energySample])
            }
            try await builder.addMetadata(metadata)
            try await builder.endCollection(at: payload.end)
            _ = try await builder.finishWorkout()
        } catch {
            builder.discardWorkout()
            throw error
        }

        // A re-export without energy (estimates turned off, or the body weight entry was
        // deleted) must also retire the previously exported sample — the replaced workout
        // doesn't take its associated samples with it.
        if payload.activeKilocalories == nil {
            try? await deleteObjects(
                of: HKQuantityType(.activeEnergyBurned),
                syncIdentifier: Self.energySyncIdentifier(for: payload.id)
            )
        }
    }

    private func deleteExportedWorkout(id: UUID) async throws {
        // The energy sample first, and tolerantly — most workouts have one workout object
        // but not necessarily an energy sample, and a missing sample must not keep the
        // workout itself from being deleted.
        try? await deleteObjects(
            of: HKQuantityType(.activeEnergyBurned),
            syncIdentifier: Self.energySyncIdentifier(for: id)
        )
        try await deleteObjects(of: .workoutType(), syncIdentifier: id.uuidString)
    }

    private static func energySyncIdentifier(for id: UUID) -> String {
        id.uuidString + "-energy"
    }

    private func deleteObjects(of type: HKObjectType, syncIdentifier: String) async throws {
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeySyncIdentifier,
            allowedValues: [syncIdentifier]
        )
        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
            healthStore.deleteObjects(of: type, predicate: predicate) { _, deletedCount, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: deletedCount)
                }
            }
        }
    }
}

// MARK: - Workout + Payload

extension Workout {
    /// The workout's HealthKit export payload, or `nil` while it cannot be represented in
    /// Health (no id, or no logged duration). Must be read on the context's queue.
    var healthKitPayload: HealthKitSyncManager.WorkoutPayload? {
        guard let id, let date, let endDate,
              HealthKitSyncManager.isExportable(start: date, end: endDate)
        else { return nil }
        let estimatesEnabled = UserDefaults.standard.bool(forKey: CalorieEstimator.enabledKey)
        return HealthKitSyncManager.WorkoutPayload(
            id: id,
            name: name,
            start: date,
            end: endDate,
            activeKilocalories: estimatesEnabled
                ? CalorieEstimator.estimate(for: self)?.activeKilocalories
                : nil
        )
    }
}
