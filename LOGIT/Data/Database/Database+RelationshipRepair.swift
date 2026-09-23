//
//  Database+RelationshipRepair.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 12.08.26.
//

import CoreData
import OSLog

/// Keeps the hand-maintained ordered-relationship mirrors honest.
///
/// Every ordered to-many in the model is stored twice: as the Core Data relationship, and as a
/// Transformable `[UUID]` list naming its members (`Exercise.setGroupOrder`,
/// `Workout.setGroupOrder`, `WorkoutSetGroup.setOrder`, …). `resolvedOrder` reads the *list*, so a
/// member missing from it is invisible to the whole app even though the relationship still holds
/// it — and invisibility is not cosmetic: `WorkoutSetGroup.numberOfSets` reads the list too, and a
/// group that reports zero sets used to be deleted outright.
///
/// The lists are maintained by hand at every mutation site, which is exactly the kind of
/// bookkeeping that drifts: a missed append, or — under CloudKit — a property-level merge that
/// takes one device's whole array and discards the other's additions. This sweep re-derives them
/// from the relationships, which are the truth.
///
/// Two rules make it safe to run on every launch and on every remote change:
/// - **Append-only.** Ids naming a member that isn't in the relationship are left alone, never
///   pruned. On a device that hasn't imported that member yet, pruning would export a shorter
///   array, delete the member from its peers' lists, and flap forever. Dangling ids are harmless —
///   `resolvedOrder` ignores them.
/// - **Write only on a real change.** An unchanged list is never reassigned, so a quiet sweep
///   produces no save, no export, and no remote-change notification to wake the next sweep.
///
/// One direction runs the other way: a set group's `exerciseOrder` re-links an exercise the
/// relationship lost (see `relinkListedExercises`).
extension Database {
    /// Runs a repair sweep asynchronously on the shared background context.
    func repairOrderedRelationships() {
        let context = setEntryBackfillContext
        context.perform {
            Self.performRelationshipRepair(in: context)
        }
    }

    /// Runs a repair sweep synchronously — for tests and call sites that need completion.
    func repairOrderedRelationshipsAndWait() {
        let context = setEntryBackfillContext
        context.performAndWait {
            Self.performRelationshipRepair(in: context)
        }
    }

    /// The sweep itself. Must run on `context`'s queue.
    static func performRelationshipRepair(in context: NSManagedObjectContext) {
        // The shared context doesn't merge other contexts' saves; anything still registered from
        // an earlier sweep would be read — and, under the object-trump policy, written back — as
        // it was then. Start from what the store holds now.
        context.refreshAllObjects()
        do {
            var adopted = 0
            var relisted = 0

            // First, so the adoption below only sees groups whose own list couldn't help.
            let relinked = try relinkListedExercises(in: context)
            adopted = try adoptOrphanedSetGroups(in: context)

            for exercise in try all(Exercise.self, in: context) {
                if let repaired = reconciled(
                    current: exercise.setGroupOrder,
                    members: members(
                        of: exercise.setGroups_,
                        as: WorkoutSetGroup.self,
                        sortedBy: \.workout?.date
                    )
                ) {
                    exercise.setGroupOrder = repaired
                    relisted += 1
                }
                if let repaired = reconciled(
                    current: exercise.templateSetGroupOrder,
                    members: members(of: exercise.templateSetGroups_, as: TemplateSetGroup.self)
                ) {
                    exercise.templateSetGroupOrder = repaired
                    relisted += 1
                }
            }

            for workout in try all(Workout.self, in: context) {
                if let repaired = reconciled(
                    current: workout.setGroupOrder,
                    members: members(of: workout.setGroups_, as: WorkoutSetGroup.self)
                ) {
                    workout.setGroupOrder = repaired
                    relisted += 1
                }
            }

            for setGroup in try all(WorkoutSetGroup.self, in: context) {
                if let repaired = reconciled(
                    current: setGroup.setOrder,
                    members: members(of: setGroup.sets_, as: WorkoutSet.self)
                ) {
                    setGroup.setOrder = repaired
                    relisted += 1
                }
            }

            for setGroup in try all(TemplateSetGroup.self, in: context) {
                if let repaired = reconciled(
                    current: setGroup.setOrder,
                    members: members(of: setGroup.sets_, as: TemplateSet.self)
                ) {
                    setGroup.setOrder = repaired
                    relisted += 1
                }
            }

            guard context.hasChanges else { return }
            try context.save()
            os_log(
                "Database: Relationship repair re-linked %d exercises, adopted %d orphaned set groups and relisted %d ordered relationships",
                type: .info, relinked, adopted, relisted
            )
        } catch {
            context.rollback()
            os_log(
                "Database: Relationship repair failed, will retry on next sweep: %{public}@",
                type: .error, String(describing: error)
            )
        }
    }

    // MARK: - Re-linking Listed Exercises

    /// Re-links set groups to the exercises their own `exerciseOrder` names, and entries that
    /// lost their exercise to the one at their position.
    ///
    /// Every edit writes a group's exercises to both the relationship and the list, so a listed
    /// exercise the relationship is missing was never removed on purpose — its link was nullified
    /// by the deletion of an object with the same `id`. Only sync copies share an id (see
    /// `Database+DuplicateMerge`): a device merging a copy away deletes it, and whatever another
    /// device had logged against that copy loses its link on import. The id outlives the copy,
    /// so the group (and its entries) go back to the copy that survived. A listed id that no
    /// exercise carries — the exercise was deleted — stays orphaned, as before.
    private static func relinkListedExercises(in context: NSManagedObjectContext) throws -> Int {
        // Candidates only: groups holding no exercise, plus the groups of entries holding none.
        // A group missing just one of its two exercises still has entries without one.
        var workoutGroups = Set(try context.fetch(orphanedGroupsRequest(WorkoutSetGroup.self)))
        for entry in try context.fetch(unattributedEntriesRequest(SetEntry.self)) {
            if let setGroup = entry.workoutSet?.setGroup { workoutGroups.insert(setGroup) }
        }
        var templateGroups = Set(try context.fetch(orphanedGroupsRequest(TemplateSetGroup.self)))
        for entry in try context.fetch(unattributedEntriesRequest(TemplateSetEntry.self)) {
            if let setGroup = entry.templateSet?.setGroup { templateGroups.insert(setGroup) }
        }
        guard !workoutGroups.isEmpty || !templateGroups.isEmpty else { return 0 }

        let listedIDs = Set(
            workoutGroups.flatMap { $0.exerciseOrder ?? [] } + templateGroups.flatMap { $0.exerciseOrder ?? [] }
        )
        let exerciseRequest = NSFetchRequest<Exercise>(entityName: "Exercise")
        exerciseRequest.predicate = NSPredicate(format: "id IN %@", Array(listedIDs))
        var exercisesByID = [UUID: Exercise]()
        // Copies the duplicate merge hasn't folded yet: any one will do (the merge moves the
        // group along with the rest), but the same one every sweep.
        let exercises = try context.fetch(exerciseRequest).sorted {
            $0.objectID.uriRepresentation().absoluteString < $1.objectID.uriRepresentation().absoluteString
        }
        for exercise in exercises {
            if let id = exercise.id, exercisesByID[id] == nil { exercisesByID[id] = exercise }
        }

        var relinked = 0
        func relink(_ setGroup: NSManagedObject, listing order: [UUID]?, linked: NSSet?) {
            let linkedIDs = Set(((linked?.allObjects as? [Exercise]) ?? []).compactMap(\.id))
            var added = Set<UUID>()
            for id in order ?? [] where !linkedIDs.contains(id) && added.insert(id).inserted {
                guard let exercise = exercisesByID[id] else { continue }
                setGroup.mutableSetValue(forKey: "exercises_").add(exercise)
                relinked += 1
            }
        }

        for setGroup in workoutGroups {
            relink(setGroup, listing: setGroup.exerciseOrder, linked: setGroup.exercises_)
            for set in (setGroup.sets_?.allObjects as? [WorkoutSet]) ?? [] {
                for entry in (set.entries_?.allObjects as? [SetEntry]) ?? [] where entry.exercise == nil {
                    if let owner = set.positionalExercise(forOrder: entry.order) { entry.exercise = owner }
                }
            }
        }
        for setGroup in templateGroups {
            relink(setGroup, listing: setGroup.exerciseOrder, linked: setGroup.exercises_)
            for set in (setGroup.sets_?.allObjects as? [TemplateSet]) ?? [] {
                for entry in (set.entries_?.allObjects as? [TemplateSetEntry]) ?? [] where entry.exercise == nil {
                    if let owner = set.positionalExercise(forOrder: entry.order) { entry.exercise = owner }
                }
            }
        }
        return relinked
    }

    private static func orphanedGroupsRequest<Group: NSManagedObject>(_ type: Group.Type) -> NSFetchRequest<Group> {
        let request = NSFetchRequest<Group>(entityName: String(describing: type))
        request.predicate = NSPredicate(format: "exercises_.@count == 0")
        return request
    }

    private static func unattributedEntriesRequest<Entry: NSManagedObject>(_ type: Entry.Type) -> NSFetchRequest<Entry> {
        let request = NSFetchRequest<Entry>(entityName: String(describing: type))
        request.predicate = NSPredicate(format: "exercise == nil")
        return request
    }

    // MARK: - Orphan Adoption

    /// Re-attaches set groups that lost their exercise link but whose entries still name one.
    ///
    /// Entries denormalize the exercise they train (`SetEntry.exercise`), and that link lives on a
    /// different record than the group's. When a deletion nullifies one side — a peer deleting an
    /// exercise this device had already re-pointed elsewhere, say — the other side survives and can
    /// say what the group trained. A group nothing names stays orphaned rather than being guessed
    /// at: its sets and values are still on screen under the workout, and the user can reassign it.
    private static func adoptOrphanedSetGroups(in context: NSManagedObjectContext) throws -> Int {
        let request = NSFetchRequest<WorkoutSetGroup>(entityName: "WorkoutSetGroup")
        request.predicate = NSPredicate(format: "exercises_.@count == 0")
        var adopted = 0

        for setGroup in try context.fetch(request) {
            // Read through the relationship, not `sets` / `entries`: their order lists are exactly
            // what may be broken, and this runs before the reconcile below.
            let sets = (setGroup.sets_?.allObjects as? [WorkoutSet]) ?? []
            let entries = sets.flatMap { ($0.entries_?.allObjects as? [SetEntry]) ?? [] }

            func exercise(atOrder order: Int64) -> Exercise? {
                entries.first { $0.order == order && $0.exercise != nil }?.exercise
            }
            guard let primary = exercise(atOrder: 0) else { continue }

            var exercises = [primary]
            if let secondary = exercise(atOrder: 1), secondary != primary {
                exercises.append(secondary)
            }
            setGroup.exercises_ = NSSet(array: exercises)
            setGroup.exerciseOrder = exercises.compactMap { $0.id }
            adopted += 1
        }
        return adopted
    }

    // MARK: - Order List Reconciliation

    private static func all<T: NSManagedObject>(
        _ type: T.Type, in context: NSManagedObjectContext
    ) throws -> [T] {
        try context.fetch(NSFetchRequest<T>(entityName: String(describing: type)))
    }

    /// The relationship's members as ids, in `NSSet` order — used where the list's order carries
    /// no meaning the sweep could reconstruct, so newcomers simply go last.
    private static func members<Member: UUIDOrderable>(
        of relationship: NSSet?, as type: Member.Type
    ) -> [UUID] {
        ((relationship?.allObjects as? [Member]) ?? []).compactMap { $0.id }
    }

    /// The relationship's members as ids, oldest first, so appended newcomers land in a stable,
    /// chronological order rather than an arbitrary one.
    private static func members<Member: UUIDOrderable>(
        of relationship: NSSet?, as type: Member.Type, sortedBy dateKeyPath: KeyPath<Member, Date?>
    ) -> [UUID] {
        ((relationship?.allObjects as? [Member]) ?? [])
            .sorted {
                ($0[keyPath: dateKeyPath] ?? .distantPast) < ($1[keyPath: dateKeyPath] ?? .distantPast)
            }
            .compactMap { $0.id }
    }

    /// The repaired list, or nil when `current` already names every member exactly once.
    ///
    /// Duplicates are collapsed — `resolvedOrder` maps each id back to the same object, so a
    /// repeated id shows one set group as two and double-counts its volume. Ids naming a
    /// non-member are kept (see the append-only rule above).
    static func reconciled(current: [UUID]?, members: [UUID]) -> [UUID]? {
        let existing = current ?? []
        var seen = Set<UUID>()
        var repaired = existing.filter { seen.insert($0).inserted }
        for id in members where seen.insert(id).inserted {
            repaired.append(id)
        }
        return repaired == existing ? nil : repaired
    }
}
