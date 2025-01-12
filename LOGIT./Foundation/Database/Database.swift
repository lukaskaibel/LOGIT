//
//  Database.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 23.01.22.
//

import Combine
import CoreData
import OSLog

class Database: ObservableObject {

    // MARK: - Constants

    private let container: NSPersistentContainer
    private let TEMPORARY_OBJECT_IDS_KEY = "temporaryObjectIds"
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Properties
    
    @Published private(set) var hasUnsavedChanges: Bool = false
    
    var isPreview: Bool
    
    // MARK: - Init

    init(isPreview: Bool = false) {
        self.isPreview = isPreview
        container = NSPersistentCloudKitContainer(name: "LOGIT")

        if isPreview {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        if isPreview {
            setupPreviewDatabase()
        }
        setupObservers()
    }

    // MARK: - Computed Properties

    var context: NSManagedObjectContext {
        container.viewContext
    }

    // MARK: - Context Methods / Properties

    func save() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard self.context.hasChanges else { return }
            do {
                try self.context.save()
                self.hasUnsavedChanges = self.context.hasChanges
                self.objectWillChange.send()
            } catch {
                os_log("Database: Failed to save context: %@", type: .error, error.localizedDescription)
            }
        }
    }
    
    func discardUnsavedChanges() {
        context.rollback()
        DispatchQueue.main.async {
            self.hasUnsavedChanges = self.context.hasChanges
        }
        objectWillChange.send()
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
        if let workoutSet = object as? WorkoutSet, let setGroup = workoutSet.setGroup,
            setGroup.numberOfSets <= 1
        {
            delete(setGroup)
        }
        context.delete(object)
        DispatchQueue.main.async {
            object.objectWillChange.send()
        }
        if saveContext {
            save()
        }
    }
    
    func managedObjectID(forURIRepresentation url: URL) -> NSManagedObjectID? {
        container.persistentStoreCoordinator.managedObjectID(forURIRepresentation: url)
    }
    
    // MARK: - Private Methods
    
    private func setupObservers() {
        NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: context)
            .sink { [weak self] _ in
                guard let self = self else { return }
                print("Database.hasChanges: ", self.context.hasChanges)
                DispatchQueue.main.async {
                    self.hasUnsavedChanges = self.context.hasChanges
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Temporary Objects

    func flagAsTemporary(_ object: NSManagedObject) {
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
