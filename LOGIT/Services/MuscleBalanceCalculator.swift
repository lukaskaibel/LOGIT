//
//  MuscleBalanceCalculator.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import Foundation

/// One muscle group's standing against its target, for a given period: how many sets trained it, what
/// share of the period that is, and how far that share sits from the user's target. The diverging
/// `MuscleBalanceBar` and the Summary tile render off these.
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

    /// Signed gap from target in percentage points — negative means under-trained.
    var deviation: Int { actualPercent - targetPercent }

    /// Under target by more than the threshold — the only state the bars and insight ever call out
    /// (over is never flagged; muscle hues are identity, not warning).
    var isBehind: Bool { deviation < -MuscleTargetSplit.behindThreshold }

    /// Within the threshold band either side of target.
    var isOnTarget: Bool { abs(deviation) <= MuscleTargetSplit.behindThreshold }
}

/// A period-aware, one-line read of a balance — what the Summary Muscle Balance tile leads with. Kept
/// as data (not a localized string) so the calculator stays pure and testable; the view turns it into
/// period-aware copy ("Legs 3 sets to go" for a week, "Legs light this month" for a month).
enum MuscleBalanceInsight: Equatable {
    /// No sets logged in the period.
    case empty
    /// A major/compound group (legs, back) is meaningfully under target. `setsToGo` is how many more
    /// sets would reach the target share — the concrete week framing.
    case behind(MuscleGroup, setsToGo: Int)
    /// One group dominates the spread, but nothing's under target — a neutral "most trained" read.
    case mostTrained(MuscleGroup)
    /// Everything sits close to target.
    case balanced
}

/// Turns a period's workouts + the user's target split into per-group balance entries and a single
/// non-nagging insight. Period-agnostic: the caller supplies the date window (filtering the top-level
/// `[Workout]` in memory, or via `WorkoutPredicateFactory.getWorkouts(from:to:)`).
struct MuscleBalanceCalculator {
    /// One entry per muscle group, in `MuscleGroup.allCases` order (zero-filled for untrained groups).
    let entries: [MuscleBalanceEntry]
    /// Total set occurrences across all groups in the period.
    let totalSets: Int

    /// Major/compound groups — the only ones whose under-training the insight will flag, per the
    /// non-nagging rule (never nag a deliberately-light abs/cardio, never flag "over").
    private static let majorGroups: [MuscleGroup] = [.legs, .back]

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

    /// Entries sorted most-under-target first — the Overview list and the Summary tile show the
    /// largest gaps at the top.
    func worstGapSorted() -> [MuscleBalanceEntry] {
        entries.sorted { $0.deviation < $1.deviation }
    }

    // MARK: - Insight

    func insight(for period: StatPeriod) -> MuscleBalanceInsight {
        guard totalSets > 0 else { return .empty }

        // Weekly set counts are noisy, so a week needs a wider gap before it flags anything.
        let tolerance = period == .week
            ? MuscleTargetSplit.behindThreshold + 3
            : MuscleTargetSplit.behindThreshold

        let behindMajor = entries
            .filter { Self.majorGroups.contains($0.muscleGroup) && $0.deviation <= -tolerance }
            .min { $0.deviation < $1.deviation }
        if let entry = behindMajor {
            return .behind(entry.muscleGroup, setsToGo: setsToGo(for: entry))
        }

        // Nothing under target. Call out a clearly-dominant group, else read as balanced.
        if let top = entries.max(by: { $0.deviation < $1.deviation }),
           top.deviation >= MuscleTargetSplit.behindThreshold,
           top.setCount > 0 {
            return .mostTrained(top.muscleGroup)
        }
        return .balanced
    }

    /// How many more sets the group needs to reach its target share of the current total.
    private func setsToGo(for entry: MuscleBalanceEntry) -> Int {
        let targetSets = Int((Double(entry.targetPercent) / 100.0 * Double(totalSets)).rounded())
        return max(0, targetSets - entry.setCount)
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
