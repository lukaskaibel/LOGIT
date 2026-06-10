//
//  Exercise+.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.21.
//

import CoreData
import Foundation
import Ifrit

// MARK: - Searchable Conformance

extension Exercise: Searchable {
    public var properties: [FuseProp] {
        [FuseProp(displayName, weight: 1.0)]
    }
}

// MARK: - Exercise Extension

extension Exercise {
    var displayName: String {
        guard let name = name, !name.isEmpty else { 
            return NSLocalizedString("noName", comment: "")
        }
        if name.hasPrefix("_default.") {
            return NSLocalizedString(name, comment: "")
        }
        return name
    }
    
    var isDefaultExercise: Bool {
        name?.hasPrefix("_default.") ?? false
    }
    
    var displayNameFirstLetter: String {
        let display = displayName
        return display.isEmpty ? " " : String(display.prefix(1).uppercased())
    }
    
    var muscleGroup: MuscleGroup? {
        get { MuscleGroup(rawValue: muscleGroupString ?? "") }
        set { muscleGroupString = newValue?.rawValue }
    }

    var setGroups: [WorkoutSetGroup] {
        return (setGroupOrder ?? .emptyList)
            .compactMap { id in
                (setGroups_?.allObjects as? [WorkoutSetGroup])?
                    .first { setGroup in
                        setGroup.id == id
                    }
            }
    }

    @objc var firstLetterOfName: String {
        return displayNameFirstLetter
    }

    var templateSetGroups: [TemplateSetGroup] {
        return (templateSetGroupOrder ?? .emptyList)
            .compactMap { id in
                (templateSetGroups_?.allObjects as? [TemplateSetGroup])?
                    .first {
                        templateSetGroup in
                        templateSetGroup.id == id
                    }
            }
    }

    var sets: [WorkoutSet] {
        var result = [WorkoutSet]()
        for setGroup in setGroups {
            result.append(contentsOf: setGroup.sets)
        }
        return result
    }

}

// MARK: - Current Best

extension Exercise {
    /// Start of the "current best" window: one month back from now.
    ///
    /// "Current best" is the app-wide term for the best value of a metric within the last month,
    /// *including* the workout currently being recorded — a measure of present capability, unlike
    /// the all-time "personal best". Shown on the in-workout metric badge, its info popover, and
    /// the exercise tiles; whenever a value is labeled "current best" it must come from this window.
    static var currentBestWindowStart: Date {
        Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    }

    /// The set holding this exercise's current best (see `currentBestWindowStart`) for `metric`,
    /// or nil if no set in the window has a usable value. Returning the set (not just the number)
    /// lets callers show the paired entry — e.g. the reps that accompanied the heaviest weight.
    /// `sets` narrows the candidates (e.g. a tile's pre-filtered sets); defaults to all sets.
    func currentBestSet(for metric: ExercisePrimaryMetric, in sets: [WorkoutSet]? = nil) -> WorkoutSet? {
        let windowStart = Self.currentBestWindowStart
        let candidates = (sets ?? self.sets).filter { ($0.workout?.date ?? .distantPast) >= windowStart }

        func value(_ workoutSet: WorkoutSet) -> Int {
            switch metric {
            case .estimatedOneRepMax: return workoutSet.estimatedOneRepMax(for: self)
            case .weight: return workoutSet.maximum(.weight, for: self)
            case .repetitions: return workoutSet.maximum(.repetitions, for: self)
            }
        }

        guard let best = candidates.max(by: { value($0) < value($1) }), value(best) > 0 else { return nil }
        return best
    }
}

extension Array: Identifiable where Element: Exercise {
    public var id: NSManagedObjectID {
        first?.objectID ?? NSManagedObjectID()
    }
}

// MARK: - Primary Progress Metric

/// The progress metric a user chooses to see on an exercise's in-workout badge. Tapping the badge
/// cycles through the cases in `next` order; the same choice is settable from the exercise editor.
enum ExercisePrimaryMetric: String, CaseIterable {
    case estimatedOneRepMax
    case weight
    case repetitions

    /// Order the badge cycles through on tap: e1RM → Weight → Reps → e1RM.
    var next: ExercisePrimaryMetric {
        switch self {
        case .estimatedOneRepMax: return .weight
        case .weight: return .repetitions
        case .repetitions: return .estimatedOneRepMax
        }
    }

    /// Short, localized label for the picker and the badge.
    var title: String {
        switch self {
        case .estimatedOneRepMax: return NSLocalizedString("e1RM", comment: "")
        case .weight: return NSLocalizedString("weight", comment: "")
        case .repetitions: return NSLocalizedString("repetitions", comment: "")
        }
    }
}

extension Exercise {
    private var primaryMetricDefaultsKey: String? {
        guard let id = id?.uuidString else { return nil }
        return "exercisePrimaryMetric.\(id)"
    }

    /// The progress metric shown on this exercise's in-workout badge, defaulting to estimated 1RM.
    ///
    /// Persisted per exercise in `UserDefaults`, keyed by the exercise id — the same lightweight
    /// approach used for pinned exercise tiles — so it needs no Core Data model change. Reading is a
    /// single `string(forKey:)` lookup, cheap enough for the badge to read while rendering.
    var primaryMetric: ExercisePrimaryMetric {
        get {
            guard let key = primaryMetricDefaultsKey,
                  let raw = UserDefaults.standard.string(forKey: key),
                  let metric = ExercisePrimaryMetric(rawValue: raw)
            else { return .estimatedOneRepMax }
            return metric
        }
        set {
            guard let key = primaryMetricDefaultsKey else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }
}
