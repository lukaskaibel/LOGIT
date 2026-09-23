//
//  Database.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 23.01.22.
//

import CloudKit
import Combine
import CoreData
import OSLog

public class Database: ObservableObject {
    // MARK: - Constants

    /// Loaded exactly once and shared by every container. Each additional
    /// `NSManagedObjectModel(contentsOf:)` copy — which `NSPersistentContainer(name:)` performs
    /// per instance — registers a competing entity claim for every `NSManagedObject` subclass,
    /// making `+entity`, and with it `Entity(context:)`, ambiguous as soon as a second `Database`
    /// exists (tests, previews). An object bound to one copy but saved through a coordinator
    /// holding another fails with Core Data error 134020.
    static let model: NSManagedObjectModel = {
        guard
            let modelURL = Bundle(for: Database.self).url(forResource: "LOGIT", withExtension: "momd"),
            let model = NSManagedObjectModel(contentsOf: modelURL)
        else {
            fatalError("Database: Failed to load the LOGIT Core Data model from the app bundle")
        }
        return model
    }()

    private let container: NSPersistentContainer
    private let TEMPORARY_OBJECT_IDS_KEY = "temporaryObjectIds"
    private var cancellables = Set<AnyCancellable>()

    /// The single home for every set-entry backfill sweep (see `Database+SetEntryBackfill`).
    /// All sweeps run through this one context so its serial queue is the lock — a launch
    /// sweep and a remote-change sweep can never process the same legacy set twice.
    lazy var setEntryBackfillContext: NSManagedObjectContext = {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }()

    /// Debounce for remote-change-triggered backfill sweeps. Remote change notifications fire
    /// for every store write (including our own saves), so sweeps coalesce behind a short delay
    /// and start with a cheap count check.
    private var setEntryReconciliationDebounce: DispatchWorkItem?

    /// Debounce for the duplicate merge that finished CloudKit exports and imports trigger (see
    /// `observeCloudKitEvents`). Separate from the remote-change sweep so a burst of sync events
    /// doesn't re-run the full relationship repair each time.
    private var duplicateMergeDebounce: DispatchWorkItem?

    /// Whether the store mirrors to CloudKit. False for every throwaway store (previews, tests,
    /// launch scenarios) — nothing there can reach another device.
    let isCloudKitMirrored: Bool

    /// Set on the main queue once this launch's first CloudKit import has finished (or failed to
    /// set up) — see `waitForInitialCloudKitImport(timeout:)`. Starts true for unmirrored stores.
    private var initialCloudKitImportSettled: Bool

    // MARK: - Properties

    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false
    /// Set when persisting to disk failed even after retrying. The app shows an alert for it:
    /// a failed save means everything still on screen is memory-only and would vanish with the
    /// next relaunch, so the user must know — silently swallowing it loses their training data.
    @Published var lastSaveFailed = false
    var isPreview: Bool

    // MARK: - Init

    /// - Parameters:
    ///   - isPreview: seeds the curated preview dataset (SwiftUI previews, fastlane fixtures).
    ///   - inMemory: backs the store with a per-instance throwaway temporary file instead
    ///     of the app's SQLite store. Defaults to `isPreview`; pass `true` on its own for
    ///     an unseeded throwaway store (launch scenarios, see `TestScenario`).
    init(isPreview: Bool = false, inMemory: Bool? = nil) {
        self.isPreview = isPreview
        let usesInMemoryStore = inMemory ?? isPreview
        container = NSPersistentCloudKitContainer(name: "LOGIT", managedObjectModel: Self.model)
        let description = container.persistentStoreDescriptions.first
        description?.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        description?.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        // Devices still on pre-v8 app versions keep syncing legacy-shaped sets (no SetEntry
        // rows) through CloudKit indefinitely. Remote change notifications are the trigger for
        // re-running the set-entry backfill whenever such data arrives.
        description?.setOption(
            true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey
        )

        if usesInMemoryStore {
            // The URL must be unique per instance: throwaway stores sharing one URL (the
            // old /dev/null trick) collide — when a later container re-initializes the
            // shared store, saves still queued on an earlier instance (finished tests,
            // discarded previews) fail with Core Data 134020 "model configuration is
            // incompatible".
            container.persistentStoreDescriptions.first!.url = FileManager.default
                .temporaryDirectory
                .appendingPathComponent("LOGIT-ephemeral-\(UUID().uuidString).sqlite")
            // Unlike /dev/null, this is a real SQLite file the CloudKit mirror could
            // sync; throwaway stores must stay strictly local.
            description?.cloudKitContainerOptions = nil
        }
        isCloudKitMirrored = description?.cloudKitContainerOptions != nil
        initialCloudKitImportSettled = !isCloudKitMirrored
        if isCloudKitMirrored {
            // Before loading: the mirroring delegate starts its setup and first import as soon as
            // the store is up, and the end of that import is what first-launch seeding waits for.
            observeCloudKitEvents()
        }
        loadStores()
        if isPreview {
            // The in-progress workout (and its floating mini bar) is only wanted
            // for the recorder marketing screenshot; every other fastlane capture
            // reads cleaner without it. SwiftUI previews (fixtures disabled) keep
            // the default so their mid-session state is unchanged.
            let includeCurrentWorkout = !ScreenshotFixtures.isEnabled
                || ScreenshotFixtures.shouldAutoPresentRecorder
            setupPreviewDatabase(includeCurrentWorkout: includeCurrentWorkout)
        }

        // The CloudKit mirroring delegate writes to the store through its own background
        // contexts. Without merging those changes into the view context, its row snapshots go
        // stale, and the next save fails optimistic locking with an NSMergeConflict (the default
        // NSErrorMergePolicy refuses to resolve it). Since that only happens with live iCloud
        // sync, it surfaces on real devices: a saved workout survives in memory for the session,
        // then is gone after a relaunch. Merge remote changes automatically, and on conflict keep
        // the user's local edits property by property — on this device, what the user just
        // entered is the truth.
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        container.viewContext.undoManager = UndoManager()
        observeUndoManager()

        // Materialize SetEntry rows for legacy-shaped sets (pre-v8 store data now, old-version
        // devices' sync arrivals forever after). Throwaway stores start empty and previews seed
        // through the factories, which create entries natively — nothing legacy to sweep there.
        if !usesInMemoryStore {
            startSetEntryReconciliation()
            backfillSetEntries()
            // Sync copies of built-in exercises and templates (see `Database+DuplicateMerge`).
            // Runs on the view context while the others run in the background; they don't
            // depend on each other's order — the merge rebuilds the survivor's lists itself.
            mergeDuplicates()
            repairOrderedRelationships()
        }
    }

    // MARK: - CloudKit Development Schema

    #if DEBUG
    /// Pushes the **entire** model into the container's development CloudKit schema — every
    /// entity, attribute and relationship, including the ones no record on this device happens
    /// to fill in — then deletes the dummy records it used to do it. Data is untouched.
    ///
    /// This exists because the alternative is hoping: the schema otherwise grows only as real
    /// records sync, so a field nobody has exercised yet simply never appears in the console,
    /// and it is missing from the production deploy that follows. Apple intends this call for
    /// exactly this moment — a debug build, run once, before deploying a model change.
    ///
    /// Requires an iCloud account signed in on the device; without one it throws
    /// `CKAccountStatusNoAccount` and changes nothing. Never runs outside DEBUG, and never on
    /// an in-memory store (those have no CloudKit mirror at all).
    ///
    /// - Returns: `true` when the schema was initialized.
    @discardableResult
    func initializeCloudKitDevelopmentSchema() -> Bool {
        guard let cloudKitContainer = container as? NSPersistentCloudKitContainer else {
            os_log("Database: not a CloudKit container, schema initialization skipped", type: .error)
            return false
        }
        do {
            // .printSchema dumps the resulting CKRecord types to stdout, which is the artifact
            // to diff against the CloudKit console before hitting Deploy.
            try cloudKitContainer.initializeCloudKitSchema(options: [.printSchema])
            os_log("Database: CloudKit development schema initialized", type: .info)
            return true
        } catch {
            os_log(
                "Database: CloudKit schema initialization failed: %{public}@",
                type: .error, String(describing: error)
            )
            return false
        }
    }
    #endif

    // MARK: - Set Entry Reconciliation Trigger

    /// Re-runs the set-entry backfill (debounced) whenever the store changes remotely — the
    /// arrival path for legacy-shaped sets from devices on pre-v8 app versions. Our own saves
    /// fire the notification too; the debounce plus the sweep's initial count check make those
    /// wake-ups cheap, and a sweep that saves nothing triggers no follow-up sweep.
    private func startSetEntryReconciliation() {
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.setEntryReconciliationDebounce?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.backfillSetEntries()
                // Imports are also how a sync copy of a built-in exercise or template arrives.
                self?.mergeDuplicates()
                // Imported changes are the main way an ordered relationship and its id list drift
                // apart (a property-level merge takes one device's whole array), so the repair
                // sweep rides along with the backfill on the same debounce and context.
                self?.repairOrderedRelationships()
            }
            self.setEntryReconciliationDebounce = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: workItem)
        }
    }

    // MARK: - CloudKit Events

    /// Watches the mirroring delegate's setup, import and export events for two things:
    /// - the end of this launch's first import, which first-launch seeding waits for; and
    /// - finished exports, after which the duplicate merge re-runs. A copy seeded on this device
    ///   is only mergeable once it has a CloudKit record name, which it gets by being exported —
    ///   an event no store write announces, so the remote-change sweep alone could miss it.
    private func observeCloudKitEvents() {
        // No observer queue: with one, the mirroring delegate's queue blocks until the block has
        // run there — and anything on the main queue that waits for that delegate (asking it for
        // record names, say) deadlocks. Hop to main without making the delegate wait.
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container,
            queue: nil
        ) { [weak self] notification in
            guard
                let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event,
                event.endDate != nil
            else { return }
            let type = event.type
            let succeeded = event.succeeded
            DispatchQueue.main.async {
                guard let self else { return }
                switch type {
                case .setup where !succeeded, .import:
                    // A failed setup (no iCloud account, iCloud off for the app) means no import
                    // is coming this launch.
                    self.initialCloudKitImportSettled = true
                default:
                    break
                }
                if succeeded, type == .import || type == .export {
                    self.scheduleDuplicateMerge()
                }
            }
        }
    }

    /// The CloudKit record names of those objects that have one — every object this device has
    /// exported or imported. Record names are the one identity all devices agree on (a
    /// `NSManagedObjectID` is local, and duplicated objects share their `id`), which is what the
    /// duplicate merge ranks copies by. Empty for an unmirrored store.
    func cloudKitRecordNames(for objectIDs: [NSManagedObjectID]) -> [NSManagedObjectID: String] {
        guard isCloudKitMirrored, let cloudKitContainer = container as? NSPersistentCloudKitContainer else {
            return [:]
        }
        return cloudKitContainer.recordIDs(for: objectIDs).mapValues(\.recordName)
    }

    private func scheduleDuplicateMerge() {
        duplicateMergeDebounce?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.mergeDuplicates()
        }
        duplicateMergeDebounce = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: workItem)
    }

    /// Returns once this launch's first CloudKit import has finished, when `timeout` runs out, or
    /// straight away when there's nothing to wait for (an unmirrored store, no iCloud account).
    ///
    /// For first-launch seeding of the bundled library: the store only knows it already holds a
    /// built-in exercise once the import has brought it in, and seeding before that adds a second
    /// copy of everything the account already has (see `Database+DuplicateMerge`, which cleans up
    /// when the wait runs out anyway — the timeout only costs a merge, never data).
    @MainActor
    func waitForInitialCloudKitImport(timeout: Duration) async {
        guard !initialCloudKitImportSettled else { return }
        if let identifier = container.persistentStoreDescriptions.first?
            .cloudKitContainerOptions?.containerIdentifier
        {
            let status = try? await CKContainer(identifier: identifier).accountStatus()
            guard status == .available else { return }
        }
        let deadline = ContinuousClock.now + timeout
        while !initialCloudKitImportSettled, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    // MARK: - Store Loading

    /// Loads the persistent stores, recovering from incompatible-model errors on the **simulator only**.
    ///
    /// The Core Data model is iterated on frequently during development. Because the store is backed
    /// by `NSPersistentCloudKitContainer`, properties cannot be renamed or removed in place — CloudKit
    /// only permits additive schema changes. A store left over from an earlier model revision (e.g. one
    /// that still had `Exercise.name_`) therefore fails to migrate and crashes on every launch with
    /// `NSCocoaErrorDomain` 134110. On the simulator we recreate the offending store once and retry so
    /// stale development stores self-heal. On a real device we keep the hard failure: a user's workout
    /// history must never be silently discarded, so an incompatible store there is handled deliberately
    /// (and is normally recoverable from the CloudKit mirror).
    private func loadStores(recreatingIncompatibleStoreOnFailure recreate: Bool = true) {
        container.loadPersistentStores { [weak self] description, error in
            guard let error = error as NSError? else { return }
            #if targetEnvironment(simulator)
            if recreate, let self, self.isIncompatibleStoreError(error), let url = description.url {
                os_log(
                    "Database: Incompatible store at %{public}@ (Core Data error %d). Recreating it for development.",
                    type: .error, url.absoluteString, error.code
                )
                try? self.container.persistentStoreCoordinator.destroyPersistentStore(
                    at: url, ofType: NSSQLiteStoreType, options: nil
                )
                self.loadStores(recreatingIncompatibleStoreOnFailure: false)
                return
            }
            #endif
            fatalError("Unresolved error \(error), \(error.userInfo)")
        }
    }

    #if targetEnvironment(simulator)
    /// `true` for Core Data migration / incompatible-model-version errors (`NSCocoaErrorDomain` 134100–134170).
    private func isIncompatibleStoreError(_ error: NSError) -> Bool {
        error.domain == NSCocoaErrorDomain && (134100...134170).contains(error.code)
    }
    #endif

    // MARK: - Computed Properties

    var context: NSManagedObjectContext {
        container.viewContext
    }

    var hasUnsavedChanges: Bool {
        context.hasChanges
    }

    // MARK: - Context Methods / Properties

    func save() {
        // Perform the hasChanges check on the context's queue to avoid race conditions
        context.perform {
            guard self.context.hasChanges else {
                return
            }
            do {
                try self.context.save()
                os_log("Database: Context saved successfully", type: .info)
            } catch {
                // Most likely a merge conflict from row snapshots gone stale under CloudKit
                // mirroring. Refreshing re-reads the store rows while keeping the unsaved
                // edits on top, so one retry usually recovers. Log the full error —
                // localizedDescription of an NSMergeConflict is uselessly generic, and
                // non-public log arguments are redacted to "<private>" on device.
                os_log(
                    "Database: Failed to save context, retrying after refresh: %{public}@",
                    type: .error, String(describing: error)
                )
                self.context.refreshAllObjects()
                do {
                    try self.context.save()
                    os_log("Database: Context saved successfully on retry", type: .info)
                } catch {
                    os_log(
                        "Database: Failed to save context after retry: %{public}@",
                        type: .fault, String(describing: error)
                    )
                    DispatchQueue.main.async {
                        self.lastSaveFailed = true
                    }
                }
            }
        }
    }

    func discardUnsavedChanges() {
        // Cancel actions expect an immediate visual revert. If we rollback asynchronously and dismiss
        // right away, the caller can briefly (or persistently) see the edited in-memory values.
        //
        // `performAndWait` is safe for the viewContext (main-queue) when called on the main thread,
        // and ensures rollback completes before we return.
        //
        // A rollback only reaches changes that are still *pending*, so it is never the whole story
        // for a Cancel — see `survivedRollback(_:)`.
        context.performAndWait {
            guard self.context.hasChanges else { return }
            self.context.rollback()
            self.context.refreshAllObjects()
        }
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    /// Cancel, completed: rolls the context back, then removes what the rollback could not.
    ///
    /// A rollback only reaches changes that are still *pending*, and every editor shares one
    /// `viewContext` whose `save()` commits all of its pending changes, not just the caller's. So
    /// anything that saves while an editor sheet is open — creating an exercise from its tray
    /// (`ExerciseEditScreen` saves so the new exercise outlives the sheet), a body measurement
    /// arriving from Health, the recorder autosaving a set — writes the half-built workout to disk
    /// as a side effect. Cancel's rollback is then a no-op, and the workout the user explicitly
    /// discarded stays in their history, unnamed, holding whatever exercise they had just picked.
    ///
    /// So: a workout added in the editor is deleted outright. Cascade takes its set groups and sets
    /// with it; exercises are only nullified, so one created along the way stays in the library where
    /// the user put it. An existing workout keeps its rows and only gives back the set groups added
    /// in this session — `setGroupOrderOnOpen` is the composition the editor opened with.
    func discardEditorChanges(
        to workout: Workout,
        wasAddedInEditor: Bool,
        setGroupOrderOnOpen: [UUID]
    ) {
        discardUnsavedChanges()
        guard survivedRollback(workout) else { return }
        if wasAddedInEditor {
            // Synchronously, unlike `delete(_:)`: the editor dismisses the moment this returns, and
            // an enqueued delete landed a frame into the dismissal — History behind the sheet
            // showed the discarded workout's card, and its count one higher, before both went.
            context.performAndWait {
                self.context.delete(workout)
                // Publishes the delete now, so the list's fetch drops the row before the
                // dismissal's first frame rather than at the end of this run loop.
                self.context.processPendingChanges()
            }
            save()
            return
        }
        let idsOnOpen = Set(setGroupOrderOnOpen)
        let addedHere = workout.setGroups.filter { setGroup in
            guard let id = setGroup.id else { return false }
            return !idsOnOpen.contains(id)
        }
        guard !addedHere.isEmpty else { return }
        // Order first: it is a plain attribute, written synchronously, while the deletes below go
        // through the context's queue. `resolvedOrder` ignores ids it cannot resolve, so the list
        // never reads as broken in between.
        workout.setGroupOrder = setGroupOrderOnOpen
        addedHere.forEach { delete($0) }
        save()
    }

    /// The template editor's Cancel — see `discardEditorChanges(to:wasAddedInEditor:setGroupOrderOnOpen:)`,
    /// which this mirrors exactly; the same hazard applies, and a cancelled new template would
    /// otherwise sit untitled in the template list.
    func discardEditorChanges(
        to template: Template,
        wasAddedInEditor: Bool,
        setGroupOrderOnOpen: [UUID]
    ) {
        discardUnsavedChanges()
        if wasAddedInEditor {
            // A template built here is flagged temporary from the moment it is created, and an
            // imported or scanned one flags its exercises alongside it — so this is the cleanup
            // that reaches all of them, and it is the same one the import sheets run on dismiss.
            // Rows the rollback already took back simply aren't found and are skipped; either way
            // the flag list is cleared, which matters because it lives in UserDefaults and would
            // otherwise keep the ids for the life of the install.
            deleteAllTemporaryObjects()
            save()
            return
        }
        guard survivedRollback(template) else { return }
        let idsOnOpen = Set(setGroupOrderOnOpen)
        let addedHere = template.setGroups.filter { setGroup in
            guard let id = setGroup.id else { return false }
            return !idsOnOpen.contains(id)
        }
        guard !addedHere.isEmpty else { return }
        template.templateSetGroupOrder = setGroupOrderOnOpen
        addedHere.forEach { delete($0) }
        save()
    }

    /// Whether `object` is still a live row after a rollback — i.e. something saved the context
    /// while it was being built, so the rollback could not take it back. An object the rollback
    /// *did* take back is detached from the context, which is what this checks.
    func survivedRollback(_ object: NSManagedObject) -> Bool {
        object.managedObjectContext != nil && !object.isDeleted
    }

    // MARK: - Object Access / Manipulation

    func fetch(
        _ type: NSManagedObject.Type,
        sortingKey: String? = nil,
        ascending: Bool = true,
        predicate: NSPredicate? = nil
    ) -> [NSFetchRequestResult] {
        do {
            let request = type.fetchRequest()
            if let sortingKey = sortingKey {
                request.sortDescriptors = [NSSortDescriptor(key: sortingKey, ascending: ascending)]
            }
            request.predicate = predicate
            return try context.fetch(request)
        } catch {
            fatalError("Database - Failed fetching \(type) with error: \(error)")
        }
    }

    func delete(_ object: NSManagedObject?, saveContext: Bool = false) {
        guard let object = object else { return }
        // Even reading workoutSet.setGroup can fire a fault, so the entire branch belongs on
        // the context's queue.
        context.perform {
            if let workoutSet = object as? WorkoutSet,
               let setGroup = workoutSet.setGroup
            {
                var updatedSets = setGroup.sets
                if let index = updatedSets.firstIndex(of: workoutSet) {
                    updatedSets.remove(at: index)
                    setGroup.sets = updatedSets
                }
                // Count the relationship, not `numberOfSets`: that reads `setOrder`, and a set
                // group whose id list has drifted reports zero sets while still holding them —
                // which would take the whole group, and every set in it, down with this one.
                let remainingSets = (setGroup.sets_?.allObjects as? [WorkoutSet] ?? [])
                    .filter { $0 != workoutSet }
                if remainingSets.isEmpty {
                    self.context.delete(setGroup)
                } else {
                    self.context.delete(workoutSet)
                }
                self.objectWillChange.send()
            } else {
                self.context.delete(object)
            }
        }
        if saveContext {
            save()
        }
    }

    func managedObjectID(forURIRepresentation url: URL) -> NSManagedObjectID? {
        container.persistentStoreCoordinator.managedObjectID(forURIRepresentation: url)
    }

    // MARK: - UndoManager

    func undo() {
        guard let undoManager = context.undoManager, undoManager.canUndo else { return }
        context.perform {
            undoManager.undo()
        }
    }

    func redo() {
        guard let undoManager = context.undoManager, undoManager.canRedo else { return }
        context.perform {
            undoManager.redo()
        }
    }

    private func observeUndoManager() {
        guard let undoManager = context.undoManager else { return }

        NotificationCenter.default.addObserver(forName: .NSUndoManagerCheckpoint, object: undoManager, queue: .main) { _ in
            if self.canUndo != undoManager.canUndo {
                DispatchQueue.main.async {
                    self.canUndo = undoManager.canUndo
                }
            }
            if self.canRedo != undoManager.canRedo {
                DispatchQueue.main.async {
                    self.canRedo = undoManager.canRedo
                }
            }
        }
    }

    // MARK: - Temporary Objects

    func flagAsTemporary(_ object: NSManagedObject) {
        // Obtain a permanent ID if the object has a temporary ID
        // This is necessary because uriRepresentation() crashes on temporary object IDs
        if object.objectID.isTemporaryID {
            do {
                try context.obtainPermanentIDs(for: [object])
            } catch {
                os_log("Database: Failed to obtain permanent ID: %@", type: .error, error.localizedDescription)
                return
            }
        }
        
        var temporaryObjectIds: [String]
        if let previousTemporaryObjectIds = UserDefaults.standard.array(
            forKey: TEMPORARY_OBJECT_IDS_KEY
        ) as? [String] {
            temporaryObjectIds = previousTemporaryObjectIds
        } else {
            temporaryObjectIds = [String]()
        }
        temporaryObjectIds.append(object.objectID.uriRepresentation().absoluteString)
        UserDefaults.standard.setValue(temporaryObjectIds, forKey: TEMPORARY_OBJECT_IDS_KEY)
    }

    func unflagAsTemporary(_ object: NSManagedObject) {
        // If the object still has a temporary ID, it was never properly saved,
        // so we can't unflag it properly
        if object.objectID.isTemporaryID {
            return
        }
        
        guard
            var temporaryObjectIds = UserDefaults.standard.array(forKey: TEMPORARY_OBJECT_IDS_KEY)
            as? [String]
        else { return }
        temporaryObjectIds = temporaryObjectIds.filter {
            $0 != object.objectID.uriRepresentation().absoluteString
        }
        UserDefaults.standard.setValue(temporaryObjectIds, forKey: TEMPORARY_OBJECT_IDS_KEY)
    }

    func isTemporaryObject(_ object: NSManagedObject) -> Bool {
        // If the object has a temporary ID, it can't be in our stored list
        if object.objectID.isTemporaryID {
            return false
        }
        
        guard
            let temporaryObjectIds = UserDefaults.standard.array(forKey: TEMPORARY_OBJECT_IDS_KEY)
            as? [String]
        else { return false }
        let objectIDString = object.objectID.uriRepresentation().absoluteString
        return temporaryObjectIds.contains { $0 == objectIDString }
    }

    func deleteAllTemporaryObjects() {
        guard
            let temporaryObjectIds = UserDefaults.standard.array(forKey: TEMPORARY_OBJECT_IDS_KEY)
            as? [String]
        else { return }

        let coordinator = container.persistentStoreCoordinator

        for uriString in temporaryObjectIds {
            if let url = URL(string: uriString),
               let objectID = coordinator.managedObjectID(forURIRepresentation: url)
            {
                if let object = try? context.existingObject(with: objectID) {
                    delete(object)
                }
            }
        }

        UserDefaults.standard.setValue([String](), forKey: TEMPORARY_OBJECT_IDS_KEY)
    }
}
