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
    var isPreview: Bool

    // MARK: - Init

    init(isPreview: Bool = false) {
        self.isPreview = isPreview
        container = NSPersistentCloudKitContainer(name: "LOGIT")
        let description = container.persistentStoreDescriptions.first
        description?.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        description?.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)

        if isPreview {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores(completionHandler: { _, error in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        if isPreview {
            setupPreviewDatabase()
        }

        container.viewContext.undoManager = UndoManager()
        observeUndoManager()
    }

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
                os_log("Database: Failed to save context: %@", type: .error, error.localizedDescription)
            }
        }
    }

    func discardUnsavedChanges() {
        // Perform the hasChanges check on the context's queue to ensure thread safety
        context.perform {
            guard self.context.hasChanges else { return }
            self.context.rollback()
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
        if let workoutSet = object as? WorkoutSet,
           let setGroup = workoutSet.setGroup
        {
            context.perform {
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
            }
        } else {
            context.perform {
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
