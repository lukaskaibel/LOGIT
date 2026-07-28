//
//  MuscleBalanceCalculator.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import Foundation

/// Where a muscle group sits against its target — under (too little), on target, or over (too much).
/// Symmetric around the target: both directions are "off" by the same tolerance.
enum MuscleBalanceState {
    case under, onTarget, over
}

/// The *goal* reading of the same standing, used by the Summary's Balance tile and the muscle-group
/// overview: a group counts as soon as it is **at least** its target. Deliberately not symmetric —
/// the tile draws a track filling toward a target, and a bar that is visibly full while the verdict
/// says "not there yet" is a tile arguing with itself. Overshoot still counts; it just says so.
enum MuscleBalanceGoalState {
    /// Short of target — the track is partly filled and the remainder shows.
    case under
    /// At target, up to `MuscleTargetSplit.behindThreshold` points past it.
    case met
    /// More than the threshold past target: met, but worth admitting.
    case over
}

/// One muscle group's standing against its target, for a given period: how many sets trained it, what
/// share of the period that is, and how far that share sits from the user's target. The diverging
/// `MuscleBalanceBar` (Summary tile, overview sections, single-muscle detail) renders off these.
struct MuscleBalanceEntry: Identifiable {
    let muscleGroup: MuscleGroup
    /// Set occurrences training this group in the period (a super set counts toward both its groups,
    /// matching `MuscleGroupService`).
    let setCount: Int
    /// This group's share of all set occurrences, as a whole percent. Across the 8 groups these sum
    /// to 100 (largest-remainder reconciled), or are all 0 when the period has no sets.
    let actualPercent: Int
    /// The user's target share for this group, whole percent.
    let targetPercent: Int

    var id: MuscleGroup { muscleGroup }

    /// Signed gap from target in percentage points — negative means under-trained. The diverging
    /// `MuscleBalanceBar` grows out of the target tick by this much, left (under) or right (over).
    var deviation: Int { actualPercent - targetPercent }

    /// Where the group sits relative to target: under / over (more than `behindThreshold` points off)
    /// or on target (within the band). Drives the grouped lists and the state pill.
    var state: MuscleBalanceState {
        if deviation < -MuscleTargetSplit.behindThreshold { return .under }
        if deviation > MuscleTargetSplit.behindThreshold { return .over }
        return .onTarget
    }

    /// How full this group's track is, 1 meaning "at target". Nil when the user has zeroed the
    /// target: a track that can never fill isn't a goal, and shouldn't be drawn or counted.
    var goalFraction: Double? {
        guard targetPercent > 0 else { return nil }
        return Double(actualPercent) / Double(targetPercent)
    }

    /// The goal reading — see `MuscleBalanceGoalState`.
    var goalState: MuscleBalanceGoalState {
        guard targetPercent > 0 else { return .met }
        if actualPercent < targetPercent { return .under }
        return deviation > MuscleTargetSplit.behindThreshold ? .over : .met
    }


}

/// Turns a period's workouts + the user's target split into per-group balance entries. Period-agnostic:
/// the caller supplies the date window (filtering the top-level `[Workout]` in memory, or via
/// `WorkoutPredicateFactory.getWorkouts(from:to:)`).
struct MuscleBalanceCalculator {
    /// One entry per muscle group, in `MuscleGroup.allCases` order (zero-filled for untrained groups).
    let entries: [MuscleBalanceEntry]
    /// Total set occurrences across all groups in the period.
    let totalSets: Int

    init(
        workouts: [Workout],
        target: MuscleTargetSplit,
        muscleGroupService: MuscleGroupService = MuscleGroupService()
    ) {
        let counts: [MuscleGroup: Int] = muscleGroupService
            .getMuscleGroupOccurances(in: workouts)
            .reduce(into: [:]) { $0[$1.0] = $1.1 }
        let total = counts.values.reduce(0, +)
        let actuals = Self.actualPercents(counts: counts, total: total)

        entries = MuscleGroup.allCases.map { group in
            MuscleBalanceEntry(
                muscleGroup: group,
                setCount: counts[group] ?? 0,
                actualPercent: actuals[group] ?? 0,
                targetPercent: target.percentage(for: group)
            )
        }
        totalSets = total
    }

    // MARK: - Aggregates

    /// The groups the goal reading applies to: those the user actually targets. A zeroed target is
    /// an explicit "I don't train this", so it leaves the chart and the denominator rather than
    /// sitting as a track that can never fill.
    var goalEntries: [MuscleBalanceEntry] {
        entries.filter { $0.targetPercent > 0 }
    }

    /// Numerator for the Balance tile: groups at least at their target.
    func atLeastTargetCount() -> Int {
        goalEntries.filter { $0.goalState != .under }.count
    }

    // MARK: - Rounding

    /// Largest-remainder (Hamilton) apportionment so the 8 whole-percent actuals sum to exactly 100
    /// rather than drifting from independent rounding. Returns an empty map when the period is empty.
    private static func actualPercents(counts: [MuscleGroup: Int], total: Int) -> [MuscleGroup: Int] {
        guard total > 0 else { return [:] }
        var floors: [MuscleGroup: Int] = [:]
        var remainders: [(group: MuscleGroup, fraction: Double)] = []
        var assigned = 0
        for group in MuscleGroup.allCases {
            let exact = Double(counts[group] ?? 0) / Double(total) * 100
            let floored = Int(exact.rounded(.down))
            floors[group] = floored
            assigned += floored
            remainders.append((group, exact - Double(floored)))
        }
        // Distribute the leftover points to the largest fractional remainders, ties broken by
        // canonical group order so the result is deterministic.
        let ordered = remainders.sorted {
            if $0.fraction != $1.fraction { return $0.fraction > $1.fraction }
            let lhs = MuscleGroup.allCases.firstIndex(of: $0.group) ?? 0
            let rhs = MuscleGroup.allCases.firstIndex(of: $1.group) ?? 0
            return lhs < rhs
        }
        var remaining = 100 - assigned
        var index = 0
        while remaining > 0, index < ordered.count {
            floors[ordered[index].group, default: 0] += 1
            remaining -= 1
            index += 1
        }
        return floors
    }
}
