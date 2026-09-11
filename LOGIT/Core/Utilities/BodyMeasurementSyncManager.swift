//
//  BodyMeasurementSyncManager.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 27.07.26.
//

import CoreData
import Foundation
import HealthKit
import OSLog

/// Keeps body measurements in step with Apple Health in **both** directions: what is logged in
/// LOGIT is written to Health, and what is logged anywhere else (the Health app, a smart scale,
/// another fitness app) is imported as a LOGIT measurement.
///
/// Body weight and body fat percentage are synced this way. Height is imported only — see
/// `importHeight()`.
///
/// Two-way sync only stays sane with strict provenance, so every entry knows where it came
/// from and nothing ever round-trips:
/// - **Imported** entries carry the Health sample's UUID in `MeasurementEntry.healthKitUUID`
///   and are never exported again — that closes the echo loop.
/// - **LOGIT-native** entries export with the measurement's own UUID as the HealthKit sync
///   identifier, so re-exporting replaces rather than duplicates, and the import query filters
///   out this app's own samples at the source.
/// - Imports additionally skip anything that already exists (same Health UUID, or a same-day
///   entry of the same value) — the belt-and-braces guard for values that can legitimately
///   arrive twice, once through CloudKit and once through Health's own iCloud sync.
///
/// Like the workout sync, every hook is fire-and-forget: logging a measurement must never fail
/// or stall because Health is unavailable.
final class BodyMeasurementSyncManager: ObservableObject {
    /// UserDefaults key for the user-facing opt-in (Settings › Apple Health).
    ///
    /// Deliberately still the body-weight key from when this synced only weight: the toggle means
    /// the same thing to the user, and changing it would silently switch the sync off for everyone
    /// who had already turned it on.
    static let syncEnabledKey = "appleHealthBodyWeightSyncEnabled"

    private static let logger = Logger(
        subsystem: ".com.lukaskbl.LOGIT", category: "BodyMeasurementSyncManager"
    )

    // MARK: - Synced Quantities

    /// One measurement LOGIT mirrors, and everything that differs between them: which Health type
    /// carries it, how its value converts to and from `MeasurementEntry.value_`, how close two
    /// values have to be to count as the same reading, and where its own sync identifiers and
    /// anchor live.
    ///
    /// Identifiers and anchors are namespaced per quantity so weight and body fat can never
    /// collide on an identifier or consume each other's import position.
    struct SyncedQuantity {
        let measurementType: MeasurementEntryType
        let quantityType: HKQuantityType
        let unit: HKUnit
        /// Health's value in `unit` → `MeasurementEntry.value_`.
        let toStored: (Double) -> Int64
        /// `MeasurementEntry.value_` → Health's value in `unit`.
        let fromStored: (Int64) -> Double
        /// Two readings this close on the same day are the same measurement, in stored units.
        let duplicateTolerance: Int64
        let syncIdentifierSuffix: String
        let anchorKey: String

        func syncIdentifier(for id: UUID) -> String { id.uuidString + syncIdentifierSuffix }

        /// Body weight: stored as grams, carried by Health as kilograms.
        static let bodyWeight = SyncedQuantity(
            measurementType: .bodyweight,
            quantityType: HKQuantityType(.bodyMass),
            unit: .gramUnit(with: .kilo),
            toStored: { Int64(($0 * 1000).rounded()) },
            fromStored: { Double($0) / 1000 },
            // Covers unit round-tripping (kg ↔ lbs ↔ grams).
            duplicateTolerance: 50,
            syncIdentifierSuffix: "-bodymass",
            anchorKey: "appleHealthBodyWeightAnchor"
        )

        /// Body fat: stored as percent × 1000 (22.4 % is 22_400), carried by Health as a
        /// **fraction** (0.224). Getting that factor of 100 wrong is the easy mistake here, so the
        /// conversion lives in one place and is covered by tests.
        static let bodyFat = SyncedQuantity(
            measurementType: .bodyFatPercentage,
            quantityType: HKQuantityType(.bodyFatPercentage),
            unit: .percent(),
            toStored: { Int64(($0 * 100_000).rounded()) },
            fromStored: { Double($0) / 100_000 },
            // 0.05 of a percentage point — the same "same reading, rounded differently" allowance
            // the weight tolerance makes.
            duplicateTolerance: 50,
            syncIdentifierSuffix: "-bodyfat",
            anchorKey: "appleHealthBodyFatAnchor"
        )

        static let all: [SyncedQuantity] = [.bodyWeight, .bodyFat]

        static func forEntryType(_ type: MeasurementEntryType?) -> SyncedQuantity? {
            all.first { $0.measurementType == type }
        }
    }

    /// Read-only: height is a setting, not a series, so it is pulled in but never pushed out.
    private var heightType: HKQuantityType { HKQuantityType(.height) }

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

    /// Whether body measurements may be written. HealthKit deliberately never reveals *read*
    /// permission (denied reads are indistinguishable from "no data"), so this only covers the
    /// write half — the settings copy explains the rest instead of pretending.
    ///
    /// Written as "every synced quantity is granted": a half-authorised state would otherwise
    /// report as authorised and then silently drop one series.
    var isAuthorizedToWrite: Bool {
        SyncedQuantity.all.allSatisfy {
            healthStore.authorizationStatus(for: $0.quantityType) == .sharingAuthorized
        }
    }

    /// Presents the system Health access sheet for every synced quantity (read **and** write) plus
    /// height (read only), and reports whether writing ended up granted.
    func requestAuthorization() async -> Bool {
        guard isHealthDataAvailable else { return false }
        let share = Set(SyncedQuantity.all.map(\.quantityType))
        let read = share.union([heightType])
        do {
            try await healthStore.requestAuthorization(toShare: share, read: read)
        } catch {
            Self.logger.error(
                "Requesting body-measurement Health authorization failed: \(String(describing: error), privacy: .public)"
            )
            return false
        }
        return isAuthorizedToWrite
    }

    // MARK: - Export Hooks (LOGIT → Health)

    /// Exports a measurement logged in LOGIT. Entries that came *from* Health are skipped —
    /// re-exporting them would duplicate the sample and start an echo. Types LOGIT doesn't mirror
    /// (muscle mass, the length measurements) fall straight through.
    func syncEntry(_ entry: MeasurementEntry) {
        guard isSyncEnabled, isAuthorizedToWrite,
              let quantity = SyncedQuantity.forEntryType(entry.type),
              entry.healthKitUUID == nil,
              let id = entry.id, let date = entry.date, entry.value_ > 0
        else { return }
        let stored = entry.value_
        Task {
            do {
                try await export(quantity, id: id, stored: stored, date: date)
            } catch {
                Self.logger.error(
                    "Exporting \(quantity.syncIdentifierSuffix, privacy: .public) \(id, privacy: .public) failed: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    /// Removes the exported counterpart of a measurement deleted in LOGIT. For imported entries
    /// this deletes the *original* Health sample, so a delete in LOGIT also clears it from Health —
    /// which is what "kept in sync" has to mean in both directions.
    func removeEntry(ofType type: MeasurementEntryType?, id: UUID?, healthKitUUID: String?) {
        guard isSyncEnabled, isAuthorizedToWrite,
              let quantity = SyncedQuantity.forEntryType(type)
        else { return }
        Task {
            do {
                if let healthKitUUID, let uuid = UUID(uuidString: healthKitUUID) {
                    try await deleteHealthSample(quantity, uuid: uuid)
                } else if let id {
                    try await deleteObjects(quantity, syncIdentifier: quantity.syncIdentifier(for: id))
                }
            } catch {
                Self.logger.info(
                    "Removing measurement from Apple Health failed: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    // MARK: - Full Sync (both directions)

    /// Brings both sides into agreement: imports everything Health has that LOGIT doesn't, exports
    /// every LOGIT-native entry, and refreshes the height in Settings. Runs when the user enables
    /// the toggle and from the settings row; safe to repeat (every part is idempotent).
    @MainActor
    func syncAll() async {
        guard isSyncEnabled else { return }
        syncState = .running
        var imported = 0
        var exported = 0
        for quantity in SyncedQuantity.all {
            imported += await importFromHealth(quantity)
            exported += await exportAll(quantity)
        }
        await importHeight()
        syncState = .finished(imported: imported, exported: exported)
    }

    /// Imports samples added or deleted in Health since the last run, for every synced quantity.
    @discardableResult
    func importFromHealth() async -> Int {
        var total = 0
        for quantity in SyncedQuantity.all {
            total += await importFromHealth(quantity)
        }
        return total
    }

    /// Imports samples added or deleted in Health since the last run. Returns the number of new
    /// LOGIT entries created.
    @discardableResult
    func importFromHealth(_ quantity: SyncedQuantity) async -> Int {
        guard isSyncEnabled, isHealthDataAvailable else { return 0 }

        // Samples this app wrote are excluded at the source: they are echoes of LOGIT entries
        // that already exist, and importing them would duplicate every logged value.
        let notFromThisApp = NSCompoundPredicate(
            notPredicateWithSubpredicate: HKQuery.predicateForObjects(from: HKSource.default())
        )
        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [.quantitySample(type: quantity.quantityType, predicate: notFromThisApp)],
            anchor: storedAnchor(for: quantity)
        )

        do {
            let result = try await descriptor.result(for: healthStore)
            let added: [(uuid: String, stored: Int64, date: Date)] = result.addedSamples.map {
                (
                    uuid: $0.uuid.uuidString,
                    stored: quantity.toStored($0.quantity.doubleValue(for: quantity.unit)),
                    date: $0.startDate
                )
            }
            let deleted = result.deletedObjects.map(\.uuid.uuidString)
            let importedCount = await apply(quantity, added: added, deleted: deleted)
            setStoredAnchor(result.newAnchor, for: quantity)
            return importedCount
        } catch {
            // Also the "read access was never granted" path — indistinguishable by design.
            Self.logger.info(
                "Importing \(quantity.syncIdentifierSuffix, privacy: .public) from Apple Health failed: \(String(describing: error), privacy: .public)"
            )
            return 0
        }
    }

    /// Exports every LOGIT-native entry across all synced quantities.
    @discardableResult
    func exportAll() async -> Int {
        var total = 0
        for quantity in SyncedQuantity.all {
            total += await exportAll(quantity)
        }
        return total
    }

    /// Exports every LOGIT-native entry of one quantity. Returns how many were written.
    @discardableResult
    func exportAll(_ quantity: SyncedQuantity) async -> Int {
        guard isSyncEnabled, isAuthorizedToWrite else { return 0 }
        let payloads: [(id: UUID, stored: Int64, date: Date)] = await withCheckedContinuation { continuation in
            database.context.perform {
                let entries = (self.database.fetch(MeasurementEntry.self) as? [MeasurementEntry]) ?? []
                continuation.resume(returning: entries.compactMap { entry in
                    guard entry.type == quantity.measurementType, entry.healthKitUUID == nil,
                          let id = entry.id, let date = entry.date, entry.value_ > 0
                    else { return nil }
                    return (id: id, stored: entry.value_, date: date)
                })
            }
        }
        var exported = 0
        for payload in payloads {
            do {
                try await export(quantity, id: payload.id, stored: payload.stored, date: payload.date)
                exported += 1
            } catch {
                Self.logger.error(
                    "Backfill: exporting \(payload.id, privacy: .public) failed: \(String(describing: error), privacy: .public)"
                )
            }
        }
        return exported
    }

    // MARK: - Height (import only)

    /// Reads the most recent height from Health into the Settings value that BMI is derived from.
    ///
    /// One way on purpose: height is a number the user states once, and Health — where it is
    /// usually set during device setup — is the better authority. Writing a casually typed value
    /// back would let a slip in LOGIT overwrite it everywhere.
    func importHeight() async {
        guard isSyncEnabled, isHealthDataAvailable else { return }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: heightType)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1
        )
        do {
            guard let sample = try await descriptor.result(for: healthStore).first else { return }
            let centimeters = sample.quantity.doubleValue(for: .meterUnit(with: .centi))
            await MainActor.run {
                UserHeight.set(centimeters: centimeters)
                self.objectWillChange.send()
            }
        } catch {
            Self.logger.info(
                "Importing height from Apple Health failed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    // MARK: - Import Rules

    /// A measurement already in the store, as far as the import rules care.
    struct ExistingEntry: Equatable {
        let value: Int64
        let date: Date
        let healthKitUUID: String?
    }

    /// Whether a Health sample should become a new LOGIT entry. `false` when LOGIT already has it —
    /// either literally (same Health UUID, already imported) or effectively (an entry of the same
    /// value on the same day, which is the same measurement having arrived through the other door:
    /// CloudKit on one side, Health's iCloud sync on the other). Pure so the rules can be tested
    /// without a Health store.
    static func shouldImport(
        uuid: String, value: Int64, date: Date, tolerance: Int64, existing: [ExistingEntry]
    ) -> Bool {
        guard value > 0 else { return false }
        if existing.contains(where: { $0.healthKitUUID == uuid }) { return false }
        return !existing.contains { candidate in
            abs(candidate.value - value) <= tolerance
                && Calendar.current.isDate(candidate.date, inSameDayAs: date)
        }
    }

    // MARK: - Core Data Application

    /// Applies imported additions and deletions to the store, skipping anything LOGIT already
    /// knows about. Runs on the context's queue — the view context is main-queue-confined.
    private func apply(
        _ quantity: SyncedQuantity,
        added: [(uuid: String, stored: Int64, date: Date)], deleted: [String]
    ) async -> Int {
        await withCheckedContinuation { continuation in
            database.context.perform {
                let entries = (self.database.fetch(MeasurementEntry.self) as? [MeasurementEntry]) ?? []
                let ofThisType = entries.filter { $0.type == quantity.measurementType }

                // Deletions first: a sample removed in Health takes its LOGIT import with it,
                // and clears the way for a same-day re-import of a corrected value.
                let deletedSet = Set(deleted)
                var deletedCount = 0
                var survivingEntries: [MeasurementEntry] = []
                for entry in ofThisType {
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
                        value: entry.value_, date: date, healthKitUUID: entry.healthKitUUID
                    )
                }

                var importedCount = 0
                for sample in added {
                    guard Self.shouldImport(
                        uuid: sample.uuid, value: sample.stored, date: sample.date,
                        tolerance: quantity.duplicateTolerance, existing: existing
                    ) else { continue }

                    let entry = MeasurementEntry(context: self.database.context)
                    entry.id = UUID()
                    entry.type = quantity.measurementType
                    entry.value_ = sample.stored
                    entry.date = sample.date
                    entry.healthKitUUID = sample.uuid
                    existing.append(
                        ExistingEntry(value: sample.stored, date: sample.date, healthKitUUID: sample.uuid)
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

    private func export(
        _ quantity: SyncedQuantity, id: UUID, stored: Int64, date: Date
    ) async throws {
        let sample = HKQuantitySample(
            type: quantity.quantityType,
            quantity: HKQuantity(unit: quantity.unit, doubleValue: quantity.fromStored(stored)),
            start: date,
            end: date,
            metadata: [
                HKMetadataKeySyncIdentifier: quantity.syncIdentifier(for: id),
                HKMetadataKeySyncVersion: Int(Date.now.timeIntervalSince1970 * 1000),
            ]
        )
        try await healthStore.save(sample)
    }

    private func deleteHealthSample(_ quantity: SyncedQuantity, uuid: UUID) async throws {
        let predicate = HKQuery.predicateForObject(with: uuid)
        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
            healthStore.deleteObjects(of: quantity.quantityType, predicate: predicate) { _, count, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: count)
                }
            }
        }
    }

    private func deleteObjects(_ quantity: SyncedQuantity, syncIdentifier: String) async throws {
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: [syncIdentifier]
        )
        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
            healthStore.deleteObjects(of: quantity.quantityType, predicate: predicate) { _, count, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: count)
                }
            }
        }
    }

    // MARK: - Anchor Persistence

    private func storedAnchor(for quantity: SyncedQuantity) -> HKQueryAnchor? {
        guard let data = UserDefaults.standard.data(forKey: quantity.anchorKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private func setStoredAnchor(_ anchor: HKQueryAnchor?, for quantity: SyncedQuantity) {
        guard let anchor,
              let data = try? NSKeyedArchiver.archivedData(
                  withRootObject: anchor, requiringSecureCoding: true
              )
        else { return }
        UserDefaults.standard.set(data, forKey: quantity.anchorKey)
    }
}
