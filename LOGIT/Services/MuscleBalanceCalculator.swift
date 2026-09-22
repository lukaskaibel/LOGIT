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
/// `MuscleBalanceTrack` (Summary tile, Muscle Groups chart) and the Muscle Groups rows render off these.
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

    /// Weekly sets still missing to reach the target — the "+6" a short group's row shows, and what
    /// the recommendation ranks by. 0 once reached.
    var setsShort: Int { max(target - setsPerWeek, 0) }

    /// Weekly sets past the target. 0 until passed.
    var setsOver: Int { max(setsPerWeek - target, 0) }
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

    /// Entries decided elsewhere — tests and previews that need a particular reading without building
    /// the workouts behind it.
    init(entries: [MuscleBalanceEntry]) {
        self.entries = entries
        totalSets = entries.reduce(0) { $0 + $1.setCount }
    }

    // MARK: - Aggregates

    /// The groups the goal reading applies to: those with a target. A group set to 0 is an explicit
    /// "I don't train this", so it leaves the chart and the recommendation rather than sitting as a
    /// track that can never fill.
    var goalEntries: [MuscleBalanceEntry] {
        entries.filter { $0.target > 0 }
    }

    /// The groups a target was turned off for, in `MuscleFocus.displayOrder`.
    var excludedEntries: [MuscleBalanceEntry] {
        MuscleFocus.displayOrder.compactMap { group in entries.first { $0.muscleGroup == group && $0.target == 0 } }
    }

    /// The goal entries in reading order, one order for every surface: groups short of their target
    /// first, the furthest behind leading, then the groups at target, then the ones past it. The chart
    /// draws in this order and Muscle Groups lists its rows in it, so a bar and its row are always in
    /// the same place, and the recommendation is always the leftmost bars.
    var rankedEntries: [MuscleBalanceEntry] {
        goalEntries.sorted(by: Self.readsBefore)
    }

    /// Every group short of its target, furthest behind first — what the balance recommends training.
    var focusEntries: [MuscleBalanceEntry] {
        rankedEntries.filter { $0.goalState == .under }
    }

    /// How many groups the recommendation names and outlines. More than two outlined bars would stop
    /// meaning "these", and two names are what a half-width tile can say.
    static let namedFocusLimit = 2

    /// The groups the recommendation names, at most `namedFocusLimit`.
    var namedFocusEntries: [MuscleBalanceEntry] {
        Array(focusEntries.prefix(Self.namedFocusLimit))
    }

    /// Short groups past the named ones — the tile's "+2 more".
    var unnamedFocusCount: Int {
        max(focusEntries.count - Self.namedFocusLimit, 0)
    }

    /// Short groups by sets short (a group six sets behind matters more than one 60% full once targets
    /// differ), ties by how full they are, then display order. At-target groups keep display order;
    /// groups past target run from nearest to furthest, so the fullest bar stands last.
    private static func readsBefore(_ lhs: MuscleBalanceEntry, _ rhs: MuscleBalanceEntry) -> Bool {
        func rank(_ state: MuscleBalanceGoalState) -> Int {
            switch state {
            case .under: return 0
            case .met: return 1
            case .over: return 2
            }
        }
        let (lhsRank, rhsRank) = (rank(lhs.goalState), rank(rhs.goalState))
        if lhsRank != rhsRank { return lhsRank < rhsRank }
        switch lhs.goalState {
        case .under:
            if lhs.setsShort != rhs.setsShort { return lhs.setsShort > rhs.setsShort }
            let (lhsFill, rhsFill) = (lhs.goalFraction ?? 0, rhs.goalFraction ?? 0)
            if lhsFill != rhsFill { return lhsFill < rhsFill }
        case .over:
            if lhs.setsOver != rhs.setsOver { return lhs.setsOver < rhs.setsOver }
        case .met:
            break
        }
        return displayIndex(lhs.muscleGroup) < displayIndex(rhs.muscleGroup)
    }

    private static func displayIndex(_ group: MuscleGroup) -> Int {
        MuscleFocus.displayOrder.firstIndex(of: group) ?? MuscleFocus.displayOrder.count
    }
}

// MARK: - Exercises behind a group

/// One exercise's share of a muscle group's sets in a window — the popover's "trained by" lines.
struct MuscleGroupExerciseSets: Identifiable {
    let name: String
    let sets: Int

    var id: String { name }

    /// The exercises that trained `group` in `workouts`, most sets first, counted the way
    /// `MuscleGroupService` counts the group itself: every set credits its exercise, and a super set
    /// credits its partner exercise too. So the lines add up to the group's own set count.
    static func top(
        _ limit: Int,
        for group: MuscleGroup,
        in workouts: [Workout]
    ) -> [MuscleGroupExerciseSets] {
        var counts: [String: Int] = [:]
        for workout in workouts {
            for set in workout.sets {
                for exercise in [set.setGroup?.exercise, set.setGroup?.secondaryExercise] {
                    guard let exercise, exercise.muscleGroup == group else { continue }
                    counts[exercise.displayName, default: 0] += 1
                }
            }
        }
        return counts
            .map { MuscleGroupExerciseSets(name: $0.key, sets: $0.value) }
            .sorted { $0.sets == $1.sets ? $0.name < $1.name : $0.sets > $1.sets }
            .prefix(limit)
            .map { $0 }
    }
}
