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
        let allSetGroups = database.fetch(
            WorkoutSetGroup.self,
            predicate: NSPredicate(format: "ANY exercises_.id == %@", (source.id ?? UUID()) as CVarArg)
        ) as? [WorkoutSetGroup] ?? []

        for setGroup in allSetGroups {
            if setGroup.exercise == source {
                removeFromSourceSetGroupOrder(setGroup: setGroup, source: source)
                setGroup.exercise = target
            }
            if setGroup.secondaryExercise == source {
                removeFromSourceSetGroupOrder(setGroup: setGroup, source: source)
                setGroup.secondaryExercise = target
            }
        }
    }

    private func reassignTemplateSetGroups(from source: Exercise, to target: Exercise) {
        let allTemplateSetGroups = database.fetch(
            TemplateSetGroup.self,
            predicate: NSPredicate(format: "ANY exercises_.id == %@", (source.id ?? UUID()) as CVarArg)
        ) as? [TemplateSetGroup] ?? []

        for setGroup in allTemplateSetGroups {
            if setGroup.exercise == source {
                removeFromSourceTemplateSetGroupOrder(setGroup: setGroup, source: source)
                setGroup.exercise = target
            }
            if setGroup.secondaryExercise == source {
                removeFromSourceTemplateSetGroupOrder(setGroup: setGroup, source: source)
                setGroup.secondaryExercise = target
            }
        }
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
