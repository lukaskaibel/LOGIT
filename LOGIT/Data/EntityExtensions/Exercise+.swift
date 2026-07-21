//
//  Exercise+.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.21.
//

import CoreData
import Foundation
import Ifrit

// MARK: - Fuzzy Search Properties

extension Exercise {
    var searchProperties: [FuseProp] {
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

    /// How this exercise is tracked by default; new sets record these fields, and individual
    /// sets may override. The nil-backed default is reps and weight — the only measurement
    /// that existed before model v8, hence correct for every pre-existing exercise.
    var measurementType: SetMeasurementType {
        get { SetMeasurementType(rawValue: measurementTypeString ?? "") ?? .repsAndWeight }
        set { measurementTypeString = newValue.rawValue }
    }

    var setGroups: [WorkoutSetGroup] {
        resolvedOrder(of: setGroups_, by: setGroupOrder)
    }

    @objc var firstLetterOfName: String {
        return displayNameFirstLetter
    }

    var templateSetGroups: [TemplateSetGroup] {
        resolvedOrder(of: templateSetGroups_, by: templateSetGroupOrder)
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
    /// Start of the "current best" window: four weeks (28 days) back from now — exactly the
    /// "last 4 weeks" the UI copy promises wherever a current best is explained.
    ///
    /// "Current best" is the app-wide term for the best value of a metric within the last four
    /// weeks — a measure of present capability, unlike the all-time "personal best". Whenever a
    /// value is labeled "current best" it must come from this window. Whether the workout currently
    /// being recorded counts is the caller's choice: the home tiles include it, while the
    /// in-workout badge and the exercise-detail tiles exclude it — they compare against the current
    /// best, and a baseline that moved with every entered set couldn't be one.
    static var currentBestWindowStart: Date {
        currentBestWindowStart(endingAt: .now)
    }

    /// The window start anchored at an arbitrary moment — used when a finished workout's detail
    /// tells the story of *that day*: its badges compare against the four weeks before the workout,
    /// not the four weeks before now, so a later, better session can't rewrite an old trend.
    static func currentBestWindowStart(endingAt anchor: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: -28, to: anchor) ?? anchor
    }

    /// The set holding this exercise's current best (see `currentBestWindowStart`) for `metric`,
    /// or nil if no set in the window has a usable value. Returning the set (not just the number)
    /// lets callers show the paired entry — e.g. the reps that accompanied the heaviest weight.
    /// `sets` narrows the candidates (e.g. a tile's pre-filtered sets); defaults to all sets.
    /// `endingAt` closes the window at that moment instead of leaving it open-ended at now.
    func currentBestSet(for metric: ExercisePrimaryMetric, in sets: [WorkoutSet]? = nil, endingAt anchor: Date? = nil) -> WorkoutSet? {
        let windowStart = Self.currentBestWindowStart(endingAt: anchor ?? .now)
        let candidates = (sets ?? self.sets).filter {
            let date = $0.workout?.date ?? .distantPast
            guard date >= windowStart else { return false }
            guard let anchor else { return true }
            return date < anchor
        }

        func value(_ workoutSet: WorkoutSet) -> Int {
            switch metric {
            case .estimatedOneRepMax: return workoutSet.estimatedOneRepMax(for: self)
            case .weight: return workoutSet.maximum(.weight, for: self)
            case .repetitions: return workoutSet.maximum(.repetitions, for: self)
            case .duration: return workoutSet.maximum(.duration, for: self)
            }
        }

        guard let best = candidates.max(by: { value($0) < value($1) }), value(best) > 0 else { return nil }
        return best
    }

    /// The set holding this exercise's current best single-set volume (see
    /// `currentBestWindowStart`), or nil if no set in the window has any volume. Kept separate
    /// from `currentBestSet(for:)` because set volume is not an `ExercisePrimaryMetric` — it
    /// isn't offered on the in-workout badge.
    func currentBestSetVolumeSet(in sets: [WorkoutSet]? = nil) -> WorkoutSet? {
        let windowStart = Self.currentBestWindowStart
        let candidates = (sets ?? self.sets).filter { ($0.workout?.date ?? .distantPast) >= windowStart }
        guard let best = candidates.max(by: { $0.volume(for: self) < $1.volume(for: self) }),
              best.volume(for: self) > 0 else { return nil }
        return best
    }

    /// The set holding this exercise's best `metric` on the most recent day it was trained — its
    /// "last best". Shown in place of the current best on the metric tiles and chart headers when the
    /// current-best window is empty (untrained for over a month), so a lapsed metric reads as the real
    /// value it last reached, dated, instead of a "––". Nil when no set has a usable value.
    func lastBestSet(for metric: ExercisePrimaryMetric, in sets: [WorkoutSet]? = nil) -> WorkoutSet? {
        Self.bestOnMostRecentDay(in: sets ?? self.sets) { workoutSet in
            switch metric {
            case .estimatedOneRepMax: return workoutSet.estimatedOneRepMax(for: self)
            case .weight: return workoutSet.maximum(.weight, for: self)
            case .repetitions: return workoutSet.maximum(.repetitions, for: self)
            case .duration: return workoutSet.maximum(.duration, for: self)
            }
        }
    }

    /// The set holding this exercise's best single-set volume on the most recent day it was trained —
    /// the set-volume sibling of `lastBestSet(for:)` (set volume isn't an `ExercisePrimaryMetric`).
    func lastBestSetVolumeSet(in sets: [WorkoutSet]? = nil) -> WorkoutSet? {
        Self.bestOnMostRecentDay(in: sets ?? self.sets) { $0.volume(for: self) }
    }

    /// The set with the highest `value` on the most recent day any set has a positive value — the
    /// shared core of the "last best" lookups. Nil when no set has a positive value for the metric.
    private static func bestOnMostRecentDay(in sets: [WorkoutSet], value: (WorkoutSet) -> Int) -> WorkoutSet? {
        let withValue = sets.filter { value($0) > 0 }
        guard let lastDate = withValue.compactMap({ $0.workout?.date }).max() else { return nil }
        let calendar = Calendar.current
        let lastDay = calendar.startOfDay(for: lastDate)
        return withValue
            .filter { calendar.isDate($0.workout?.date ?? .distantPast, inSameDayAs: lastDay) }
            .max(by: { value($0) < value($1) })
    }
}

extension Array: @retroactive Identifiable where Element: Exercise {
    public var id: NSManagedObjectID {
        first?.objectID ?? NSManagedObjectID()
    }
}

// MARK: - Primary Progress Metric

/// The progress metric a user chooses to see on an exercise's in-workout badge, switched from the
/// badge's info panel or the exercise editor.
enum ExercisePrimaryMetric: String, CaseIterable {
    case estimatedOneRepMax
    case weight
    case repetitions
    case duration

    /// Short, localized label for the picker and accessibility.
    var title: String {
        switch self {
        case .estimatedOneRepMax: return NSLocalizedString("e1RM", comment: "")
        case .weight: return NSLocalizedString("weight", comment: "")
        case .repetitions: return NSLocalizedString("repetitions", comment: "")
        case .duration: return NSLocalizedString("measurementType.duration", comment: "")
        }
    }

    /// The metrics that make sense for how an exercise is measured — pickers and the badge's
    /// cycling order offer only these, so a plank never advertises an e1RM.
    static func allowed(for measurementType: SetMeasurementType) -> [ExercisePrimaryMetric] {
        switch measurementType {
        case .repsAndWeight: return [.estimatedOneRepMax, .weight, .repetitions]
        case .repsOnly: return [.repetitions]
        case .duration: return [.duration]
        case .weightAndDuration: return [.weight, .duration]
        }
    }

    /// Compact label for tight spots (the badge's fine print) — "Reps" instead of "Repetitions".
    var shortTitle: String {
        switch self {
        case .repetitions: return NSLocalizedString("repsShort", comment: "")
        default: return title
        }
    }

    /// The metric shown when the user hasn't chosen one for an exercise: e1RM for Pro users (the
    /// flagship metric), repetitions for free users — the one metric whose info panel is fully
    /// visible without Pro, so a default badge tap always lands on usable content. Upgrading flips
    /// exercises without an explicit choice to e1RM automatically.
    static var defaultMetric: ExercisePrimaryMetric {
        PurchaseManager.isProUnlocked ? .estimatedOneRepMax : .repetitions
    }
}

extension Exercise {
    private var primaryMetricDefaultsKey: String? {
        guard let id = id?.uuidString else { return nil }
        return "exercisePrimaryMetric.\(id)"
    }

    /// The progress metric shown on this exercise's in-workout badge, defaulting to
    /// `ExercisePrimaryMetric.defaultMetric` (e1RM with Pro, repetitions without).
    ///
    /// Persisted per exercise in `UserDefaults`, keyed by the exercise id — the same lightweight
    /// approach used for pinned exercise tiles — so it needs no Core Data model change. Reading is a
    /// single `string(forKey:)` lookup, cheap enough for the badge to read while rendering.
    var primaryMetric: ExercisePrimaryMetric {
        get {
            // A stored choice only counts while it fits how the exercise is measured — after a
            // measurement-type change, an incompatible leftover falls back to a fitting metric.
            let allowed = ExercisePrimaryMetric.allowed(for: measurementType)
            if let key = primaryMetricDefaultsKey,
               let raw = UserDefaults.standard.string(forKey: key),
               let metric = ExercisePrimaryMetric(rawValue: raw),
               allowed.contains(metric) {
                return metric
            }
            return allowed.contains(.defaultMetric) ? .defaultMetric : allowed[0]
        }
        set {
            guard let key = primaryMetricDefaultsKey else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }
}
