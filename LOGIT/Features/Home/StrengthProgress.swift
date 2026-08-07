//
//  StrengthProgress.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 27.07.26.
//

import CoreData
import SwiftUI

// MARK: - Model

/// The whole-training strength trend: every trained exercise's percent change in estimated 1RM over
/// the recent `TrendWindow` vs the equally long window before it, weighted by how many sets it took
/// to get there. Cardio and bodyweight sets carry no e1RM and drop out; an exercise needs a usable
/// best in BOTH windows to count — with nothing to compare against there is no trend.
///
/// The tile always reports `TrendWindow.default`; the detail screen lets you widen it, which is a
/// real change to what's measured rather than a chart range.
///
/// The per-exercise changes are kept rather than averaged away, because they are what the headline
/// number *is*: the detail screen shows the weighted mean pulled back apart.
struct StrengthProgress {

    /// One exercise's contribution to the average.
    struct ExerciseChange: Identifiable {
        let exercise: Exercise
        let muscleGroup: MuscleGroup
        /// Percent change of the recent best over the prior best, clamped (see `maxAbsPercentChange`).
        let percentChange: Double
        /// Sets recorded in the recent window — this change's weight in the mean.
        let setCount: Int
        var id: NSManagedObjectID { exercise.objectID }
    }

    /// One exercise's heaviest estimated 1RM in the recent window — the "strongest lifts" list, which
    /// answers a different question from the rest of this type: not *how much did it move* but *what
    /// can you actually lift*. Kept here because it falls out of the same pass over the sets.
    struct ExerciseBest: Identifiable {
        let exercise: Exercise
        let muscleGroup: MuscleGroup
        /// Best estimated 1RM in the recent window, in grams.
        let oneRepMax: Int
        var id: NSManagedObjectID { exercise.objectID }
    }

    struct GroupProgress: Identifiable {
        let muscleGroup: MuscleGroup
        let percentChange: Double
        /// Exercises behind this group's figure — drives the grid's "no data" state.
        let exerciseCount: Int
        var id: String { muscleGroup.rawValue }
    }

    /// Every qualifying exercise, unordered.
    let changes: [ExerciseChange]
    /// Every exercise with a usable e1RM in the recent window, heaviest first. Unlike `changes` this
    /// does *not* require a prior-window best: a lift you only started this month still has a weight,
    /// and leaving it out of a "strongest" list would be plainly wrong.
    var bests: [ExerciseBest] = []
    let window: TrendWindow
    /// How much of the comparison span (two windows) the logged history covers, 0…1. Only used by
    /// the empty state's ring, so it reads as "still filling up" rather than as nothing at all.
    var historyFraction: Double = 0

    static let empty = StrengthProgress(changes: [], window: .default)

    var hasData: Bool { !changes.isEmpty }

    /// Outlier guard so one freak set can't swing the headline.
    private static let maxAbsPercentChange = 50.0

    // MARK: Derived

    /// Set-weighted mean percent change over a scope — the whole training when `group` is nil.
    /// Nil when the scope holds nothing to compare.
    func percentChange(in group: MuscleGroup? = nil) -> Double? {
        let scoped = group.map { g in changes.filter { $0.muscleGroup == g } } ?? changes
        guard !scoped.isEmpty else { return nil }
        let totalWeight = scoped.reduce(0.0) { $0 + Double(max($1.setCount, 1)) }
        guard totalWeight > 0 else { return nil }
        return scoped.reduce(0.0) { $0 + $1.percentChange * Double(max($1.setCount, 1)) } / totalWeight
    }

    var overallPercentChange: Double? { percentChange() }

    /// Every muscle group that has data, strongest gain first.
    var groups: [GroupProgress] {
        Dictionary(grouping: changes, by: \.muscleGroup)
            .compactMap { group, scoped -> GroupProgress? in
                guard let percent = percentChange(in: group) else { return nil }
                return GroupProgress(muscleGroup: group, percentChange: percent, exerciseCount: scoped.count)
            }
            .sorted { $0.percentChange > $1.percentChange }
    }

    /// A scope's exercises sorted by how far they moved — by *magnitude*, so a big decline ranks
    /// high instead of hiding at the bottom. Ties break on the heavier (more sets) exercise.
    func exerciseChanges(in group: MuscleGroup? = nil) -> [ExerciseChange] {
        let scoped = group.map { g in changes.filter { $0.muscleGroup == g } } ?? changes
        return scoped.sorted {
            abs($0.percentChange) == abs($1.percentChange)
                ? $0.setCount > $1.setCount
                : abs($0.percentChange) > abs($1.percentChange)
        }
    }

    // MARK: Computation

    static func compute(
        workouts: [Workout],
        window: TrendWindow = .default,
        reference: Date = .now
    ) -> StrengthProgress {
        let recentStart = window.range(windowsAgo: 0, from: reference).lowerBound
        let priorStart = window.range(windowsAgo: 1, from: reference).lowerBound

        // Unique exercises trained across the fetched workouts.
        var exercises: [Exercise] = []
        var seen = Set<NSManagedObjectID>()
        for workout in workouts where !workout.isEmpty {
            for exercise in workout.exercises where !seen.contains(exercise.objectID) {
                seen.insert(exercise.objectID)
                exercises.append(exercise)
            }
        }

        // How far the history reaches into the span being compared — the empty state's progress.
        let earliest = workouts.filter { !$0.isEmpty }.compactMap(\.date).min()
        let historyFraction = window.historyFraction(firstDataDate: earliest, from: reference)

        var changes: [ExerciseChange] = []
        var bests: [ExerciseBest] = []
        for exercise in exercises {
            guard let group = exercise.muscleGroup else { continue }
            var recentBest = 0
            var priorBest = 0
            var recentSetCount = 0
            for set in exercise.sets {
                guard let date = set.workout?.date else { continue }
                let e1rm = set.estimatedOneRepMax(for: exercise)
                guard e1rm > 0 else { continue }
                if date >= recentStart, date <= reference {
                    recentBest = max(recentBest, e1rm)
                    recentSetCount += 1
                } else if date >= priorStart, date < recentStart {
                    priorBest = max(priorBest, e1rm)
                }
            }
            if recentBest > 0 {
                bests.append(ExerciseBest(exercise: exercise, muscleGroup: group, oneRepMax: recentBest))
            }
            guard recentBest > 0, priorBest > 0 else { continue }
            let raw = (Double(recentBest) - Double(priorBest)) / Double(priorBest) * 100
            changes.append(
                ExerciseChange(
                    exercise: exercise,
                    muscleGroup: group,
                    percentChange: min(max(raw, -maxAbsPercentChange), maxAbsPercentChange),
                    setCount: recentSetCount
                )
            )
        }
        return StrengthProgress(
            changes: changes,
            bests: bests.sorted { $0.oneRepMax > $1.oneRepMax },
            window: window,
            historyFraction: historyFraction
        )
    }
}

// MARK: - Trend direction

/// Below this magnitude (in %) a trend reads as flat — a deadband so the arrow doesn't twitch.
let STRENGTH_TREND_DEADBAND = 1.0

func strengthTrendIsUp(_ percent: Double) -> Bool { percent >= STRENGTH_TREND_DEADBAND }
func strengthTrendIsDown(_ percent: Double) -> Bool { percent <= -STRENGTH_TREND_DEADBAND }

/// Accent for a gain; neutral grey for flat or a decline — progress green is the only colour that
/// ever means "good", and a dip is never coloured as a warning.
func strengthTrendColor(_ percent: Double) -> Color {
    strengthTrendIsUp(percent) ? .accentColor : .secondaryLabel
}

/// The arrow for a trend. Unlike `TrendIndicatorView`, a flat result keeps an arrow here
/// (`arrow.right`) rather than dropping it: on the one surface whose entire subject is the trend,
/// an empty icon slot reads as missing rather than as "steady", and a horizontal arrow can't be
/// mistaken for a decline.
func strengthTrendSymbol(_ percent: Double) -> String {
    if strengthTrendIsUp(percent) { return "arrow.up" }
    if strengthTrendIsDown(percent) { return "arrow.down" }
    return "arrow.right"
}
