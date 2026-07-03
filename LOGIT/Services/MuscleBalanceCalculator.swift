//
//  MuscleBalanceCalculator.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import Foundation

/// Where a muscle group sits against its target — under (too little), on target, or over (too much).
enum MuscleBalanceState {
    case under, onTarget, over
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

    /// Under target by more than the threshold ("build up").
    var isBehind: Bool { state == .under }

    /// Within the threshold band either side of target.
    var isOnTarget: Bool { state == .onTarget }
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

    /// How many of the 8 groups sit within the threshold band of their target — the tile footer's
    /// "N of 8 on target".
    func onTargetCount() -> Int {
        entries.filter(\.isOnTarget).count
    }

    /// Under-target groups, most points under first (longest bar first) — the "Below target" list;
    /// the Summary tile leads with these.
    func underTargets() -> [MuscleBalanceEntry] {
        entries.filter { $0.state == .under }.sorted { $0.deviation < $1.deviation }
    }

    /// Over-target groups, most over first — the "Above target" list, shown after the under ones.
    func overTargets() -> [MuscleBalanceEntry] {
        entries.filter { $0.state == .over }.sorted { $0.deviation > $1.deviation }
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
