//
//  Database+DuplicateMerge.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 23.09.26.
//

import CoreData
import OSLog

/// How the duplicate merge ranks the copies of one object. The ranking decides which copy
/// survives, so it must come out the same on every device.
enum DuplicateMergeIdentity {
    /// The store syncs through CloudKit: copies rank by their CloudKit record names — the one
    /// identity every device shares. A group with a copy that has no record name yet (it hasn't
    /// been exported) is left for a later sweep.
    case cloudKit(recordNames: ([NSManagedObjectID]) -> [NSManagedObjectID: String])
    /// The store never syncs, so no other device can rank differently; any stable order will do.
    case localOnly
}

/// Folds the copies that CloudKit sync leaves of one exercise or template back into one object.
///
/// Built-in exercises and starter templates carry fixed ids (`DeterministicUUID`) so seeding can
/// recognize them — but seeding only looks in the local store. A fresh install (a reinstall, a
/// second device) that seeds before its first CloudKit import has arrived adds a second copy of
/// everything the account already has: two `Exercise` rows with one `id`, two CloudKit records,
/// each collecting whatever gets logged against it. First-launch seeding now waits for that
/// import (`waitForInitialCloudKitImport`), but it can't always — an offline first launch, two
/// devices both adding a library update's new exercises — and older installs already hold such
/// copies. This merge is what guarantees one object per id.
///
/// It never loses data, by four rules:
/// - **Move, then delete.** Every set group, template set group and set entry of a copy moves to
///   the survivor before the copy is deleted, and a copy that still holds anything is kept.
/// - **Nothing changes underneath it.** It runs on the view context only while that holds no
///   unsaved edits, and saves with `NSErrorMergePolicy`: if anything it read was saved from
///   elsewhere in the meantime, it rolls back and a later sweep starts over.
/// - **Every device keeps the same copy.** Two devices that each kept "their own" copy would
///   delete each other's and leave none, with the history bound to it cut loose. The survivor is
///   the copy whose CloudKit record name sorts first, and copies without a record name wait: a
///   copy that hasn't been exported yet could still turn out to be the one that sorts first.
/// - **The id re-links what a race cuts loose.** Something logged against a copy on one device
///   while another device merges that copy away loses its exercise when the deletion arrives —
///   but its set group's `exerciseOrder` still names the id every copy shares, and the
///   relationship repair re-links it (see `Database+RelationshipRepair`).
///
/// Templates are the user's to edit, so template copies merge only while identical, and only
/// once the newest has existed for `templateSettlingInterval` — long enough for edits made on
/// the device that created it to have synced (see `mergeDuplicateTemplates`).
extension Database {
    /// How long a template copy must have existed before an identical twin may absorb it.
    static let templateSettlingInterval: TimeInterval = 60 * 60

    /// Looks for copies and, when there are some, queues a merge on the view context.
    ///
    /// Two steps on two queues. The record names come from the CloudKit mirroring delegate,
    /// which answers on its own queue — busy for as long as an import runs, and at times waiting
    /// for the main queue itself — so they are fetched in the background: asking from the main
    /// thread froze the app, and could deadlock it. The merge then runs on the view context,
    /// because only on its queue are "nobody is editing" and the merge one step: it runs only
    /// while the view context holds no unsaved changes, and nothing can start editing before it
    /// has saved. A background merge could delete a copy a moment after the recorder started
    /// logging a set against it. The next sweep (every save triggers one) retries a skipped merge.
    func mergeDuplicates() {
        guard isCloudKitMirrored else {
            mergeDuplicatesOnViewContext(identity: .localOnly)
            return
        }
        let backgroundContext = setEntryBackfillContext
        backgroundContext.perform { [weak self] in
            guard let self else { return }
            // Id-only fetches: a store without copies costs next to nothing.
            let copies = Self.objectIDsOfCopies(in: backgroundContext)
            guard !copies.isEmpty else { return }
            let names = self.cloudKitRecordNames(for: copies)
            DispatchQueue.main.async { [weak self] in
                // Copies that turned up since have no name here, and wait for the next sweep.
                self?.mergeDuplicatesOnViewContext(identity: .cloudKit { objectIDs in
                    let requested = Set(objectIDs)
                    return names.filter { requested.contains($0.key) }
                })
            }
        }
    }

    private func mergeDuplicatesOnViewContext(identity: DuplicateMergeIdentity) {
        let context = self.context
        context.perform { [weak self] in
            // The merge saves this context, which must only ever commit the merge's own changes.
            guard !context.hasChanges else { return }
            let undoManager = context.undoManager
            undoManager?.disableUndoRegistration()
            let merged = Self.performDuplicateMerge(in: context, identity: identity)
            context.processPendingChanges()
            undoManager?.enableUndoRegistration()
            if merged.exercises + merged.templates > 0 {
                // An undo step recorded against a merged-away copy would reach for a deleted
                // object. Losing the undo history once is the safe trade.
                undoManager?.removeAllActions()
            }
            // A failed merge's rollback clears the undo stack too.
            self?.canUndo = undoManager?.canUndo ?? false
            self?.canRedo = undoManager?.canRedo ?? false
        }
    }

    /// Every exercise and template that shares its `id` with another.
    private static func objectIDsOfCopies(in context: NSManagedObjectContext) -> [NSManagedObjectID] {
        var objectIDs = [NSManagedObjectID]()
        for entityName in ["Exercise", "Template"] {
            guard let ids = try? duplicatedIDs(of: entityName, in: context), !ids.isEmpty else { continue }
            let request = NSFetchRequest<NSManagedObjectID>(entityName: entityName)
            request.resultType = .managedObjectIDResultType
            request.predicate = NSPredicate(format: "id IN %@", ids)
            objectIDs += (try? context.fetch(request)) ?? []
        }
        return objectIDs
    }

    /// The merge itself. Must run on `context`'s queue, with no other unsaved changes in it.
    /// Saves only when something merged.
    @discardableResult
    static func performDuplicateMerge(
        in context: NSManagedObjectContext,
        identity: DuplicateMergeIdentity,
        now: Date = .now
    ) -> (exercises: Int, templates: Int) {
        // A copy may only be deleted in the state it was read in. If anything the merge touches
        // was saved from elsewhere in between — a CloudKit import, a background sweep — the save
        // fails instead of overwriting it, the merge rolls back, and the next sweep starts over.
        let mergePolicy = context.mergePolicy
        context.mergePolicy = NSMergePolicy.error
        defer { context.mergePolicy = mergePolicy }
        do {
            let exercises = try mergeDuplicateExercises(in: context, identity: identity)
            let templates = try mergeDuplicateTemplates(in: context, identity: identity, now: now)
            guard context.hasChanges else { return (0, 0) }
            try context.save()
            os_log(
                "Database: Duplicate merge folded %d exercise and %d template copies",
                type: .info, exercises, templates
            )
            return (exercises, templates)
        } catch {
            context.rollback()
            os_log(
                "Database: Duplicate merge failed, will retry on next sweep: %{public}@",
                type: .error, String(describing: error)
            )
            return (0, 0)
        }
    }

    // MARK: - Exercises

    private static func mergeDuplicateExercises(
        in context: NSManagedObjectContext, identity: DuplicateMergeIdentity
    ) throws -> Int {
        var merged = 0
        for copies in try duplicateGroups(of: Exercise.self, id: \.id, in: context) {
            guard let ranked = ranked(copies, by: identity), let survivor = ranked.first else { continue }
            let losers = ranked.dropFirst()
            let setGroupLists = ranked.map { $0.setGroupOrder ?? [] }
            let templateSetGroupLists = ranked.map { $0.templateSetGroupOrder ?? [] }
            let losersHeldSetGroups = losers.contains { ($0.setGroups_?.count ?? 0) > 0 }
            let losersHeldTemplateSetGroups = losers.contains { ($0.templateSetGroups_?.count ?? 0) > 0 }

            adoptSettings(from: ranked, into: survivor)
            for loser in losers {
                move(loser, into: survivor)
                guard holdsNothing(loser) else {
                    os_log(
                        "Database: Duplicate merge kept an exercise copy that still holds data",
                        type: .fault
                    )
                    continue
                }
                context.delete(loser)
                merged += 1
            }

            if losersHeldSetGroups || setGroupLists.dropFirst().contains(where: { !$0.isEmpty }) {
                let members = (survivor.setGroups_?.allObjects as? [WorkoutSetGroup]) ?? []
                let order = chronologicalOrder(of: members, listedIn: setGroupLists)
                if order != survivor.setGroupOrder { survivor.setGroupOrder = order }
            }
            if losersHeldTemplateSetGroups
                || templateSetGroupLists.dropFirst().contains(where: { !$0.isEmpty })
            {
                let members = ((survivor.templateSetGroups_?.allObjects as? [TemplateSetGroup]) ?? [])
                    .compactMap(\.id)
                let order = union(templateSetGroupLists + [members])
                if order != survivor.templateSetGroupOrder { survivor.templateSetGroupOrder = order }
            }
        }
        return merged
    }

    /// Hands everything `loser` holds to `survivor`. Copies share their `id`, so no order list
    /// naming the exercise changes — only the relationships do.
    private static func move(_ loser: Exercise, into survivor: Exercise) {
        for setGroup in (loser.setGroups_?.allObjects as? [WorkoutSetGroup]) ?? [] {
            // A super set pairing both copies collapses to one link; its `exerciseOrder` keeps
            // naming the id twice, which is how a super set of one exercise is stored anyway.
            let links = setGroup.mutableSetValue(forKey: "exercises_")
            links.remove(loser)
            links.add(survivor)
        }
        for setGroup in (loser.templateSetGroups_?.allObjects as? [TemplateSetGroup]) ?? [] {
            let links = setGroup.mutableSetValue(forKey: "exercises_")
            links.remove(loser)
            links.add(survivor)
        }
        for entry in (loser.setEntries_?.allObjects as? [SetEntry]) ?? [] {
            entry.exercise = survivor
        }
        for entry in (loser.templateSetEntries_?.allObjects as? [TemplateSetEntry]) ?? [] {
            entry.exercise = survivor
        }
    }

    private static func holdsNothing(_ exercise: Exercise) -> Bool {
        (exercise.setGroups_?.count ?? 0) == 0
            && (exercise.templateSetGroups_?.count ?? 0) == 0
            && (exercise.setEntries_?.count ?? 0) == 0
            && (exercise.templateSetEntries_?.count ?? 0) == 0
    }

    /// Gives the survivor the settings of the copy that has been used most — its measurement
    /// type and time/distance formats are the ones the user's logging habit was built on — and
    /// fills whatever that copy leaves unset from the others.
    private static func adoptSettings(from ranked: [Exercise], into survivor: Exercise) {
        var donor = survivor
        var donorUse = -1
        for copy in ranked {
            let use = (copy.setGroups_?.count ?? 0) + (copy.templateSetGroups_?.count ?? 0)
            if use > donorUse {
                donor = copy
                donorUse = use
            }
        }
        let sources = [donor] + ranked.filter { $0 != donor }
        let skipped: Set<String> = ["id", "setGroupOrder", "templateSetGroupOrder"]
        for name in survivor.entity.attributesByName.keys.sorted() where !skipped.contains(name) {
            guard let value = sources.lazy.compactMap({ $0.value(forKey: name) }).first else { continue }
            if !isEqual(survivor.value(forKey: name), value) {
                survivor.setValue(value, forKey: name)
            }
        }
    }

    /// The survivor's set-group order: every member oldest first, then — per the repair's
    /// append-only rule — every listed id that names no member yet.
    private static func chronologicalOrder(
        of members: [WorkoutSetGroup], listedIn lists: [[UUID]]
    ) -> [UUID] {
        var position = [UUID: Int]()
        for id in lists.joined() where position[id] == nil {
            position[id] = position.count
        }
        let memberIDs = members
            .compactMap { group -> (id: UUID, date: Date, position: Int)? in
                guard let id = group.id else { return nil }
                return (id, group.workout?.date ?? .distantPast, position[id] ?? .max)
            }
            .sorted { ($0.date, $0.position, $0.id.uuidString) < ($1.date, $1.position, $1.id.uuidString) }
            .map(\.id)
        return union([memberIDs] + lists)
    }

    /// The lists concatenated, each id kept at its first appearance.
    private static func union(_ lists: [[UUID]]) -> [UUID] {
        var seen = Set<UUID>()
        return lists.joined().filter { seen.insert($0).inserted }
    }

    // MARK: - Templates

    /// Merges template copies whose content is identical, keeping every workout that was started
    /// from one of them.
    ///
    /// Copies that differ are left alone: someone edited one, and neither edit may be thrown
    /// away. Identical copies can still hide an edit that hasn't synced yet, so a copy is only
    /// merged once the newest copy is `templateSettlingInterval` old — the likely edit is the
    /// one made right after a fresh install seeded its copy, and by then it has synced and made
    /// the copies differ.
    private static func mergeDuplicateTemplates(
        in context: NSManagedObjectContext, identity: DuplicateMergeIdentity, now: Date
    ) throws -> Int {
        var merged = 0
        for copies in try duplicateGroups(of: Template.self, id: \.id, in: context) {
            let newest = copies.map { $0.creationDate ?? .distantPast }.max() ?? .distantPast
            guard now.timeIntervalSince(newest) >= templateSettlingInterval else { continue }
            guard let ranked = ranked(copies, by: identity) else { continue }

            let byContent = Dictionary(grouping: ranked, by: contentFingerprint(of:))
            for identical in byContent.values where identical.count > 1 {
                // `Dictionary(grouping:)` keeps each group in `ranked` order.
                let survivor = identical[0]
                for loser in identical.dropFirst() {
                    for workout in (loser.workouts_?.allObjects as? [Workout]) ?? [] {
                        workout.template = survivor
                    }
                    if let created = loser.creationDate,
                       created < survivor.creationDate ?? .distantFuture
                    {
                        survivor.creationDate = created
                    }
                    // Cascades to its set groups, sets and entries — identical to the survivor's.
                    context.delete(loser)
                    merged += 1
                }
            }
        }
        return merged
    }

    /// Everything the user can see or edit in a template, and nothing that differs between two
    /// copies of the same content (ids, order lists as such, the creation date). Attributes are
    /// read off the model generically, so a field added later can't be silently left out.
    static func contentFingerprint(of template: Template) -> String {
        let groups = (template.setGroups_?.allObjects as? [TemplateSetGroup]) ?? []
        return fields(of: template, excluding: ["id", "creationDate", "templateSetGroupOrder"])
            + ordered(groups, by: template.templateSetGroupOrder, fingerprint: contentFingerprint(of:))
    }

    private static func contentFingerprint(of setGroup: TemplateSetGroup) -> String {
        let linked = ((setGroup.exercises_?.allObjects as? [Exercise]) ?? [])
            .compactMap { $0.id?.uuidString }
            .sorted()
        let sets = (setGroup.sets_?.allObjects as? [TemplateSet]) ?? []
        return fields(of: setGroup, excluding: ["id", "exerciseOrder", "setOrder"])
            + "exercises=\((setGroup.exerciseOrder ?? []).map(\.uuidString))\(linked);"
            + ordered(sets, by: setGroup.setOrder, fingerprint: contentFingerprint(of:))
    }

    private static func contentFingerprint(of set: TemplateSet) -> String {
        let entries = ((set.entries_?.allObjects as? [TemplateSetEntry]) ?? [])
            .map { entry in
                fields(of: entry, excluding: ["id"]) + "exercise=\(entry.exercise?.id?.uuidString ?? "∅");"
            }
            .sorted()
        // The entity name tells a standard, drop and super set apart.
        let kind = set.entity.name ?? ""
        return "\(kind):" + fields(of: set, excluding: ["id"]) + "entries=[\(entries.joined(separator: ","))];"
    }

    /// Members in their list's order, then any member the list misses (sorted by content, so two
    /// copies with the same drift still compare equal) — a member hidden by a drifted list is
    /// still part of the template and must not be deleted as if it weren't there.
    private static func ordered<Member: NSManagedObject & UUIDOrderable>(
        _ members: [Member], by order: [UUID]?, fingerprint: (Member) -> String
    ) -> String {
        var byID = [UUID: Member]()
        for member in members {
            if let id = member.id { byID[id] = member }
        }
        var listed = [String]()
        var seen = Set<NSManagedObjectID>()
        for id in order ?? [] {
            guard let member = byID[id], seen.insert(member.objectID).inserted else { continue }
            listed.append(fingerprint(member))
        }
        let unlisted = members.filter { !seen.contains($0.objectID) }.map(fingerprint).sorted()
        return "[" + (listed + unlisted).map { "{\($0)}" }.joined() + "]"
    }

    private static func fields(of object: NSManagedObject, excluding excluded: Set<String>) -> String {
        object.entity.attributesByName.keys.sorted()
            .filter { !excluded.contains($0) }
            .map { "\($0)=\(describe(object.value(forKey: $0)));" }
            .joined()
    }

    private static func describe(_ value: Any?) -> String {
        switch value {
        case nil: return "∅"
        case let date as Date: return String(date.timeIntervalSinceReferenceDate)
        case let uuid as UUID: return uuid.uuidString
        case let data as Data: return data.base64EncodedString()
        case let value?: return String(describing: value)
        }
    }

    // MARK: - Shared

    /// Every set of two or more objects sharing one `id`. Starts with a cheap id-only fetch, so
    /// a sweep over a store without duplicates materializes nothing.
    private static func duplicateGroups<Object: NSManagedObject>(
        of type: Object.Type, id: KeyPath<Object, UUID?>, in context: NSManagedObjectContext
    ) throws -> [[Object]] {
        let entityName = String(describing: type)
        let duplicatedIDs = try duplicatedIDs(of: entityName, in: context)
        guard !duplicatedIDs.isEmpty else { return [] }

        let request = NSFetchRequest<Object>(entityName: entityName)
        request.predicate = NSPredicate(format: "id IN %@", duplicatedIDs)
        let objects = try context.fetch(request)
        return Dictionary(grouping: objects) { $0[keyPath: id] }
            .values
            .filter { $0.count > 1 }
            .map { Array($0) }
    }

    /// The ids that more than one object of the entity carries, from a fetch of the ids alone.
    private static func duplicatedIDs(of entityName: String, in context: NSManagedObjectContext) throws -> [UUID] {
        let request = NSFetchRequest<NSDictionary>(entityName: entityName)
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["id"]
        request.predicate = NSPredicate(format: "id != nil")
        var counts = [UUID: Int]()
        for row in try context.fetch(request) {
            if let id = row["id"] as? UUID { counts[id, default: 0] += 1 }
        }
        return counts.filter { $0.value > 1 }.map(\.key)
    }

    /// The copies, survivor first — or nil when they can't be ranked the same way everywhere yet.
    private static func ranked<Object: NSManagedObject>(
        _ copies: [Object], by identity: DuplicateMergeIdentity
    ) -> [Object]? {
        switch identity {
        case .localOnly:
            return copies.sorted {
                $0.objectID.uriRepresentation().absoluteString < $1.objectID.uriRepresentation().absoluteString
            }
        case .cloudKit(let recordNames):
            let names = recordNames(copies.map(\.objectID))
            guard copies.allSatisfy({ names[$0.objectID] != nil }) else { return nil }
            return copies.sorted { names[$0.objectID]! < names[$1.objectID]! }
        }
    }

    private static func isEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (lhs as NSObject, rhs as NSObject): return lhs.isEqual(rhs)
        default: return false
        }
    }
}
