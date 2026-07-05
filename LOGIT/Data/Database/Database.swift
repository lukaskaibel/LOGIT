//
//  Database.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 23.01.22.
//

import Combine
import CoreData
import OSLog

public class Database: ObservableObject {
    // MARK: - Constants

    private let container: NSPersistentContainer
    private let TEMPORARY_OBJECT_IDS_KEY = "temporaryObjectIds"
    private var cancellables = Set<AnyCancellable>()

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
    ///   - inMemory: backs the store with `/dev/null` instead of the on-disk SQLite file.
    ///     Defaults to `isPreview`; pass `true` on its own for an unseeded throwaway store
    ///     (launch scenarios, see `TestScenario`).
    init(isPreview: Bool = false, inMemory: Bool? = nil) {
        self.isPreview = isPreview
        let usesInMemoryStore = inMemory ?? isPreview
        container = NSPersistentCloudKitContainer(name: "LOGIT")
        let description = container.persistentStoreDescriptions.first
        description?.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        description?.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)

        if usesInMemoryStore {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        loadStores()
        if isPreview {
            setupPreviewDatabase()
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
        context.performAndWait {
            guard self.context.hasChanges else { return }
            self.context.rollback()
            self.context.refreshAllObjects()
        }
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
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
                if setGroup.numberOfSets == 0 {
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
