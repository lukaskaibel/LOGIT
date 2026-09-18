//
//  MuscleBalanceCalculator.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import Foundation

/// Where a muscle group sits against its target: it counts as soon as it is **at least** its target.
/// Deliberately not symmetric — every surface draws a track filling toward a target, and a bar that is
/// visibly full while the verdict says "not there yet" is a tile arguing with itself. Overshoot still
/// counts; it just says so.
///
/// The one verdict in the app, read by the Summary tile and the Muscle Groups screen alike.
enum MuscleBalanceGoalState {
    /// Short of target — the track is partly filled and the remainder shows.
    case under
    /// Exactly at target.
    case met
    /// Past target, by even one set: met, but worth admitting. Targets are whole sets per week, so
    /// "one more than you planned" is already a real difference rather than rounding noise.
    case over
}

/// One muscle group's standing against its weekly set target for a given window: how many sets
/// trained it, what that works out to per week, and the target it is read against. The filling
/// `MuscleBalanceTrack` (Summary tile, overview hero and tiles) renders off these.
struct MuscleBalanceEntry: Identifiable {
    let muscleGroup: MuscleGroup
    /// Set occurrences training this group in the window (a super set counts toward both its groups,
    /// matching `MuscleGroupService`).
    let setCount: Int
    /// `setCount` as a weekly average, rounded to whole sets — the number every surface shows, and
    /// the one the verdict is decided on, so "10/10" can never read "below target".
    let setsPerWeek: Int
    /// The user's weekly set target for this group; 0 when it isn't part of the focus.
    let target: Int

    var id: MuscleGroup { muscleGroup }

    /// How full this group's track is, 1 meaning "at target". Nil when the group has no target: a
    /// track that can never fill isn't a goal, and shouldn't be drawn or counted.
    var goalFraction: Double? {
        guard target > 0 else { return nil }
        return Double(setsPerWeek) / Double(target)
    }

    /// The goal reading — see `MuscleBalanceGoalState`.
    var goalState: MuscleBalanceGoalState {
        guard target > 0 else { return .met }
        if setsPerWeek < target { return .under }
        return setsPerWeek > target ? .over : .met
    }
}

/// Turns a window's workouts + the user's focus into per-group balance entries. Window-agnostic: the
/// caller supplies the workouts already narrowed to the window and how many weeks it covers (see
/// `TrendWindow.weeksCovered`).
struct MuscleBalanceCalculator {
    /// One entry per muscle group, in `MuscleGroup.allCases` order (zero-filled for untrained groups).
    let entries: [MuscleBalanceEntry]
    /// Total set occurrences across all groups in the window.
    let totalSets: Int

    init(
        workouts: [Workout],
        focus: MuscleFocus,
        weeks: Double,
        muscleGroupService: MuscleGroupService = MuscleGroupService()
    ) {
        let counts: [MuscleGroup: Int] = muscleGroupService
            .getMuscleGroupOccurances(in: workouts)
            .reduce(into: [:]) { $0[$1.0] = $1.1 }
        let divisor = max(weeks, 1)
        entries = MuscleGroup.allCases.map { group in
            let count = counts[group] ?? 0
            return MuscleBalanceEntry(
                muscleGroup: group,
                setCount: count,
                setsPerWeek: Int((Double(count) / divisor).rounded()),
                target: focus.target(for: group)
            )
        }
        totalSets = counts.values.reduce(0, +)
    }

    // MARK: - Aggregates

    /// The groups the goal reading applies to: those with a target. A group set to 0 is an explicit
    /// "I don't train this", so it leaves the chart and the denominator rather than sitting as a track
    /// that can never fill.
    var goalEntries: [MuscleBalanceEntry] {
        entries.filter { $0.target > 0 }
    }

    /// Numerator for the Balance tile: groups at least at their target.
    func atLeastTargetCount() -> Int {
        goalEntries.filter { $0.goalState != .under }.count
    }
}
