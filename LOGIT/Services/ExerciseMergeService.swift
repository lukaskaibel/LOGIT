//
//  ExerciseMergeService.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 16.04.26.
//

import CoreData
import Foundation

enum ExerciseMergeError: LocalizedError {
    case bothAreDefaultExercises
    case sameExercise

    var errorDescription: String? {
        switch self {
        case .bothAreDefaultExercises:
            return NSLocalizedString("cannotMergeDefaultExercises", comment: "")
        case .sameExercise:
            return NSLocalizedString("cannotMergeSameExercise", comment: "")
        }
    }
}

final class ExerciseMergeService {

    let database: Database

    init(database: Database) {
        self.database = database
    }

    /// Merges `source` exercise into `target` exercise.
    /// All WorkoutSetGroups, TemplateSetGroups, and PinnedExerciseTiles referencing `source`
    /// are reassigned to `target`, then `source` is deleted.
    ///
    /// Reassignment walks `source`'s own relationships rather than fetching by id and asking each
    /// group which exercise it thinks it trains. Both of those detours have bitten: a nil `source.id`
    /// made the fetch match nothing, and `setGroup.exercise` resolves through the group's
    /// `exerciseOrder` id list, so a group whose list had drifted answered "no exercise" and was
    /// skipped — leaving it attached to an exercise about to be deleted. The relationship is the one
    /// thing that cannot lie about who holds what.
    func merge(source: Exercise, into target: Exercise) throws {
        guard source != target else {
            throw ExerciseMergeError.sameExercise
        }
        guard !(source.isDefaultExercise && target.isDefaultExercise) else {
            throw ExerciseMergeError.bothAreDefaultExercises
        }

        reassignWorkoutSetGroups(from: source, to: target)
        reassignTemplateSetGroups(from: source, to: target)
        updatePinnedExerciseTiles(from: source, to: target)

        database.context.delete(source)
        database.save()
    }

    // MARK: - Private

    private func reassignWorkoutSetGroups(from source: Exercise, to target: Exercise) {
        let allSetGroups = (source.setGroups_?.allObjects as? [WorkoutSetGroup]) ?? []

        for setGroup in allSetGroups {
            // Rebuild the group's exercise list from the relationship, substituting target for
            // source at whichever positions source occupies. Going through `exercise` /
            // `secondaryExercise` would read the drifted order list back in.
            let current = (setGroup.exercises_?.allObjects as? [Exercise]) ?? []
            let ordered = Database.reconciled(
                current: setGroup.exerciseOrder, members: current.compactMap { $0.id }
            ) ?? setGroup.exerciseOrder ?? []
            let byId = Dictionary(current.compactMap { ex in ex.id.map { ($0, ex) } }) { first, _ in first }

            var replacement = ordered.compactMap { byId[$0] }.map { $0 == source ? target : $0 }
            if replacement.isEmpty { replacement = [target] }
            // A super set whose two exercises were merged together collapses to one lane rather
            // than listing the target twice.
            if replacement.count == 2, replacement[0] == replacement[1] {
                replacement.removeLast()
            }

            removeFromSourceSetGroupOrder(setGroup: setGroup, source: source)
            setGroup.exercises_ = NSSet(array: replacement)
            setGroup.exerciseOrder = replacement.compactMap { $0.id }
            appendToTargetSetGroupOrder(setGroup: setGroup, target: target)
            setGroup.reattributeEntries()
        }
    }

    private func reassignTemplateSetGroups(from source: Exercise, to target: Exercise) {
        let allTemplateSetGroups = (source.templateSetGroups_?.allObjects as? [TemplateSetGroup]) ?? []

        for setGroup in allTemplateSetGroups {
            let current = (setGroup.exercises_?.allObjects as? [Exercise]) ?? []
            let ordered = Database.reconciled(
                current: setGroup.exerciseOrder, members: current.compactMap { $0.id }
            ) ?? setGroup.exerciseOrder ?? []
            let byId = Dictionary(current.compactMap { ex in ex.id.map { ($0, ex) } }) { first, _ in first }

            var replacement = ordered.compactMap { byId[$0] }.map { $0 == source ? target : $0 }
            if replacement.isEmpty { replacement = [target] }
            if replacement.count == 2, replacement[0] == replacement[1] {
                replacement.removeLast()
            }

            removeFromSourceTemplateSetGroupOrder(setGroup: setGroup, source: source)
            setGroup.exercises_ = NSSet(array: replacement)
            setGroup.exerciseOrder = replacement.compactMap { $0.id }
            appendToTargetTemplateSetGroupOrder(setGroup: setGroup, target: target)
            setGroup.reattributeEntries()
        }
    }

    private func appendToTargetSetGroupOrder(setGroup: WorkoutSetGroup, target: Exercise) {
        guard let groupID = setGroup.id else { return }
        var order = target.setGroupOrder ?? []
        guard !order.contains(groupID) else { return }
        order.append(groupID)
        target.setGroupOrder = order
    }

    private func appendToTargetTemplateSetGroupOrder(setGroup: TemplateSetGroup, target: Exercise) {
        guard let groupID = setGroup.id else { return }
        var order = target.templateSetGroupOrder ?? []
        guard !order.contains(groupID) else { return }
        order.append(groupID)
        target.templateSetGroupOrder = order
    }

    private func removeFromSourceSetGroupOrder(setGroup: WorkoutSetGroup, source: Exercise) {
        guard let groupID = setGroup.id else { return }
        var order = source.setGroupOrder ?? []
        order.removeAll { $0 == groupID }
        source.setGroupOrder = order
        let existing = (source.setGroups_?.allObjects as? [WorkoutSetGroup]) ?? []
        source.setGroups_ = NSSet(array: existing.filter { $0 != setGroup })
    }

    private func removeFromSourceTemplateSetGroupOrder(setGroup: TemplateSetGroup, source: Exercise) {
        guard let groupID = setGroup.id else { return }
        var order = source.templateSetGroupOrder ?? []
        order.removeAll { $0 == groupID }
        source.templateSetGroupOrder = order
        let existing = (source.templateSetGroups_?.allObjects as? [TemplateSetGroup]) ?? []
        source.templateSetGroups_ = NSSet(array: existing.filter { $0 != setGroup })
    }

    private func updatePinnedExerciseTiles(from source: Exercise, to target: Exercise) {
        guard let sourceID = source.id, let targetID = target.id else { return }
        let key = "pinnedExercises"
        guard let data = UserDefaults.standard.data(forKey: key),
              var tiles = try? JSONDecoder().decode([PinnedExerciseTile].self, from: data)
        else { return }

        var changed = false
        tiles = tiles.map { tile in
            if tile.exerciseID == sourceID {
                changed = true
                return PinnedExerciseTile(exerciseID: targetID, tileType: tile.tileType)
            }
            return tile
        }

        if changed, let encoded = try? JSONEncoder().encode(tiles) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
}
