//
//  BodyWeightSyncManager.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 27.07.26.
//

import CoreData
import Foundation
import HealthKit
import OSLog

/// Keeps body-weight measurements in step with Apple Health in **both** directions: weight
/// logged in LOGIT is written to Health, and weight logged anywhere else (the Health app, a
/// smart scale, another fitness app) is imported as a LOGIT measurement.
///
/// Two-way sync only stays sane with strict provenance, so every entry knows where it came
/// from and nothing ever round-trips:
/// - **Imported** entries carry the Health sample's UUID in `MeasurementEntry.healthKitUUID`
///   and are never exported again — that closes the echo loop.
/// - **LOGIT-native** entries export with the measurement's own UUID as the HealthKit sync
///   identifier, so re-exporting replaces rather than duplicates, and the import query filters
///   out this app's own samples at the source.
/// - Imports additionally skip anything that already exists (same Health UUID, or a same-day
///   entry of the same weight) — the belt-and-braces guard for values that can legitimately
///   arrive twice, once through CloudKit and once through Health's own iCloud sync.
///
/// Like the workout sync, every hook is fire-and-forget: logging a measurement must never fail
/// or stall because Health is unavailable.
final class BodyWeightSyncManager: ObservableObject {
    /// UserDefaults key for the user-facing opt-in (Settings › Apple Health).
    static let syncEnabledKey = "appleHealthBodyWeightSyncEnabled"
    /// Where the anchored query's position is persisted, so each import only sees what
    /// changed since the last one.
    private static let anchorKey = "appleHealthBodyWeightAnchor"

    /// Two entries of the same weight on the same day are the same measurement, whichever
    /// door they came through. Tolerance covers unit round-tripping (kg ↔ lbs ↔ grams).
    private static let duplicateToleranceGrams: Int64 = 50

    private static let logger = Logger(subsystem: ".com.lukaskbl.LOGIT", category: "BodyWeightSyncManager")

    enum SyncState: Equatable {
        case idle
        case running
        case finished(imported: Int, exported: Int)
    }

    // MARK: - Published

    /// Drives the settings row's progress and result label.
    @Published var syncState: SyncState = .idle

    // MARK: - Private

    private let database: Database
    private let healthStore = HKHealthStore()
    private var bodyMassType: HKQuantityType { HKQuantityType(.bodyMass) }

    // MARK: - Init

    init(database: Database) {
        self.database = database
    }

    // MARK: - Availability & Authorization

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    var isSyncEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.syncEnabledKey)
    }

    /// Whether body-weight samples may be written. HealthKit deliberately never reveals
    /// *read* permission (denied reads are indistinguishable from "no data"), so this only
    /// covers the write half — the settings copy explains the rest instead of pretending.
    var isAuthorizedToWrite: Bool {
        healthStore.authorizationStatus(for: bodyMassType) == .sharingAuthorized
    }

    /// Presents the system Health access sheet for body weight (read **and** write) and
    /// reports whether writing ended up granted.
    func requestAuthorization() async -> Bool {
        guard isHealthDataAvailable else { return false }
        do {
            try await healthStore.requestAuthorization(toShare: [bodyMassType], read: [bodyMassType])
        } catch {
            Self.logger.error(
                "Requesting body-weight Health authorization failed: \(String(describing: error), privacy: .public)"
            )
            return false
        }
        return isAuthorizedToWrite
    }

    // MARK: - Export Hooks (LOGIT → Health)

    /// Exports a body-weight measurement logged in LOGIT. Entries that came *from* Health are
    /// skipped — re-exporting them would duplicate the sample and start an echo.
    func syncEntry(_ entry: MeasurementEntry) {
        guard isSyncEnabled, isAuthorizedToWrite,
              entry.type == .bodyweight, entry.healthKitUUID == nil,
              let id = entry.id, let date = entry.date, entry.value_ > 0
        else { return }
        let grams = entry.value_
        Task {
            do {
                try await export(id: id, grams: grams, date: date)
            } catch {
                Self.logger.error(
                    "Exporting body weight \(id, privacy: .public) failed: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    /// Removes the exported counterpart of a measurement deleted in LOGIT. For imported
    /// entries this deletes the *original* Health sample, so a delete in LOGIT also clears it
    /// from Health — which is what "kept in sync" has to mean in both directions.
    func removeEntry(id: UUID?, healthKitUUID: String?) {
        guard isSyncEnabled, isAuthorizedToWrite else { return }
        Task {
            do {
                if let healthKitUUID, let uuid = UUID(uuidString: healthKitUUID) {
                    try await deleteHealthSample(uuid: uuid)
                } else if let id {
                    try await deleteObjects(syncIdentifier: Self.syncIdentifier(for: id))
                }
            } catch {
                Self.logger.info(
                    "Removing body weight from Apple Health failed: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    // MARK: - Full Sync (both directions)

    /// Brings both sides into agreement: imports everything Health has that LOGIT doesn't,
    /// and exports every LOGIT-native entry. Runs when the user enables the toggle and from
    /// the settings row; safe to repeat (both halves are idempotent).
    @MainActor
    func syncAll() async {
        guard isSyncEnabled else { return }
        syncState = .running
        let imported = await importFromHealth()
        let exported = await exportAll()
        syncState = .finished(imported: imported, exported: exported)
    }

    /// Imports body-weight samples added or deleted in Health since the last run. Returns the
    /// number of new LOGIT entries created.
    @discardableResult
    func importFromHealth() async -> Int {
        guard isSyncEnabled, isHealthDataAvailable else { return 0 }

        // Samples this app wrote are excluded at the source: they are echoes of LOGIT entries
        // that already exist, and importing them would duplicate every logged weight.
        let notFromThisApp = NSCompoundPredicate(
            notPredicateWithSubpredicate: HKQuery.predicateForObjects(from: HKSource.default())
        )
        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [.quantitySample(type: bodyMassType, predicate: notFromThisApp)],
            anchor: storedAnchor
        )

        do {
            let result = try await descriptor.result(for: healthStore)
            let added: [(uuid: String, grams: Int64, date: Date)] = result.addedSamples.map {
                (
                    uuid: $0.uuid.uuidString,
                    grams: Int64(($0.quantity.doubleValue(for: .gramUnit(with: .kilo)) * 1000).rounded()),
                    date: $0.startDate
                )
            }
            let deleted = result.deletedObjects.map(\.uuid.uuidString)
            let importedCount = await apply(added: added, deleted: deleted)
            storedAnchor = result.newAnchor
            return importedCount
        } catch {
            // Also the "read access was never granted" path — indistinguishable by design.
            Self.logger.info(
                "Importing body weight from Apple Health failed: \(String(describing: error), privacy: .public)"
            )
            return 0
        }
    }

    /// Exports every LOGIT-native body-weight entry. Returns how many were written.
    @discardableResult
    func exportAll() async -> Int {
        guard isSyncEnabled, isAuthorizedToWrite else { return 0 }
        let payloads: [(id: UUID, grams: Int64, date: Date)] = await withCheckedContinuation { continuation in
            database.context.perform {
                let entries = (self.database.fetch(MeasurementEntry.self) as? [MeasurementEntry]) ?? []
                continuation.resume(returning: entries.compactMap { entry in
                    guard entry.type == .bodyweight, entry.healthKitUUID == nil,
                          let id = entry.id, let date = entry.date, entry.value_ > 0
                    else { return nil }
                    return (id: id, grams: entry.value_, date: date)
                })
            }
        }
        var exported = 0
        for payload in payloads {
            do {
                try await export(id: payload.id, grams: payload.grams, date: payload.date)
                exported += 1
            } catch {
                Self.logger.error(
                    "Backfill: exporting body weight \(payload.id, privacy: .public) failed: \(String(describing: error), privacy: .public)"
                )
            }
        }
        return exported
    }

    // MARK: - Import Rules

    /// A body-weight entry already in the store, as far as the import rules care.
    struct ExistingEntry: Equatable {
        let grams: Int64
        let date: Date
        let healthKitUUID: String?
    }

    /// Whether a Health sample should become a new LOGIT entry. `false` when LOGIT already
    /// has it — either literally (same Health UUID, already imported) or effectively (an
    /// entry of the same weight on the same day, which is the same measurement having
    /// arrived through the other door: CloudKit on one side, Health's iCloud sync on the
    /// other). Pure so the rules can be tested without a Health store.
    static func shouldImport(
        uuid: String, grams: Int64, date: Date, existing: [ExistingEntry]
    ) -> Bool {
        guard grams > 0 else { return false }
        if existing.contains(where: { $0.healthKitUUID == uuid }) { return false }
        return !existing.contains { candidate in
            abs(candidate.grams - grams) <= duplicateToleranceGrams
                && Calendar.current.isDate(candidate.date, inSameDayAs: date)
        }
    }

    // MARK: - Core Data Application

    /// Applies imported additions and deletions to the store, skipping anything LOGIT already
    /// knows about. Runs on the context's queue — the view context is main-queue-confined.
    private func apply(
        added: [(uuid: String, grams: Int64, date: Date)], deleted: [String]
    ) async -> Int {
        await withCheckedContinuation { continuation in
            database.context.perform {
                let entries = (self.database.fetch(MeasurementEntry.self) as? [MeasurementEntry]) ?? []
                let bodyWeightEntries = entries.filter { $0.type == .bodyweight }

                // Deletions first: a sample removed in Health takes its LOGIT import with it,
                // and clears the way for a same-day re-import of a corrected value.
                let deletedSet = Set(deleted)
                var deletedCount = 0
                var survivingEntries: [MeasurementEntry] = []
                for entry in bodyWeightEntries {
                    if let healthKitUUID = entry.healthKitUUID, deletedSet.contains(healthKitUUID) {
                        self.database.context.delete(entry)
                        deletedCount += 1
                    } else {
                        survivingEntries.append(entry)
                    }
                }

                var existing = survivingEntries.compactMap { entry -> ExistingEntry? in
                    guard let date = entry.date else { return nil }
                    return ExistingEntry(
                        grams: entry.value_, date: date, healthKitUUID: entry.healthKitUUID
                    )
                }

                var importedCount = 0
                for sample in added {
                    guard Self.shouldImport(
                        uuid: sample.uuid, grams: sample.grams, date: sample.date, existing: existing
                    ) else { continue }

                    let entry = MeasurementEntry(context: self.database.context)
                    entry.id = UUID()
                    entry.type = .bodyweight
                    entry.value_ = sample.grams
                    entry.date = sample.date
                    entry.healthKitUUID = sample.uuid
                    existing.append(
                        ExistingEntry(grams: sample.grams, date: sample.date, healthKitUUID: sample.uuid)
                    )
                    importedCount += 1
                }

                if importedCount > 0 || deletedCount > 0 {
                    self.database.save()
                    DispatchQueue.main.async { self.objectWillChange.send() }
                }
                continuation.resume(returning: importedCount)
            }
        }
    }

    // MARK: - HealthKit Plumbing

    /// Sync identifiers are namespaced per record kind so a measurement and a workout can
    /// never collide on the same identifier.
    private static func syncIdentifier(for id: UUID) -> String {
        id.uuidString + "-bodymass"
    }

    private func export(id: UUID, grams: Int64, date: Date) async throws {
        let sample = HKQuantitySample(
            type: bodyMassType,
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: Double(grams) / 1000),
            start: date,
            end: date,
            metadata: [
                HKMetadataKeySyncIdentifier: Self.syncIdentifier(for: id),
                HKMetadataKeySyncVersion: Int(Date.now.timeIntervalSince1970 * 1000),
            ]
        )
        try await healthStore.save(sample)
    }

    private func deleteHealthSample(uuid: UUID) async throws {
        let predicate = HKQuery.predicateForObject(with: uuid)
        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
            healthStore.deleteObjects(of: bodyMassType, predicate: predicate) { _, count, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: count)
                }
            }
        }
    }

    private func deleteObjects(syncIdentifier: String) async throws {
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: [syncIdentifier]
        )
        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
            healthStore.deleteObjects(of: bodyMassType, predicate: predicate) { _, count, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: count)
                }
            }
        }
    }

    // MARK: - Anchor Persistence

    private var storedAnchor: HKQueryAnchor? {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.anchorKey) else { return nil }
            return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
        }
        set {
            guard let newValue,
                  let data = try? NSKeyedArchiver.archivedData(
                      withRootObject: newValue, requiringSecureCoding: true
                  )
            else { return }
            UserDefaults.standard.set(data, forKey: Self.anchorKey)
        }
    }
}
