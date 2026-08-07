//
//  MuscleBalanceHistory.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 01.07.26.
//

import Foundation

/// One window instance in the Muscle Groups overview's history strip: its start date, the short label
/// under its bar, the fuller title the selected-window header shows, and the balance calculator for the
/// sets trained in it. The overview builds `historyBucketCount` of these back from now, renders them as
/// the normalized segmented bar chart, and drives the value columns off whichever bucket is selected.
struct MuscleBalanceBucket: Identifiable {
    /// Stable, unique key — the window start's epoch seconds. Used as the chart's x-category and the
    /// selection value, since the human labels aren't guaranteed unique across a strip.
    let id: String
    let start: Date
    /// Short label under the bar, naming where the window *ends* (e.g. "6 Aug", "Aug", "2026").
    let axisLabel: String
    /// Full title for the selected-window header (e.g. "Last 4 weeks", "9 Jun - 6 Jul").
    let title: String
    let calculator: MuscleBalanceCalculator

    var totalSets: Int { calculator.totalSets }
}

/// Builds the Muscle Groups overview's history strip: a run of `MuscleBalanceBucket`s, oldest first, one
/// per `TrendWindow` back from now.
///
/// The newest bucket ends *now* rather than on a calendar boundary, which is the whole point — it makes
/// the strip's last bar the same window the Summary's Balance tile reports, so opening the detail can't
/// contradict the tile you tapped.
enum MuscleBalanceHistory {
    /// The history strip, oldest bucket first → newest last (index `count - 1` is the current window).
    static func buckets(
        from workouts: [Workout],
        window: TrendWindow,
        target: MuscleTargetSplit,
        muscleGroupService: MuscleGroupService,
        now: Date = .now
    ) -> [MuscleBalanceBucket] {
        (0 ..< window.historyBucketCount).reversed().map { windowsAgo in
            let range = window.range(windowsAgo: windowsAgo, from: now)
            let start = range.lowerBound
            // Half-open on the lower edge: consecutive windows share a boundary instant, so a
            // workout landing exactly on one counts once — in the newer window — not in both.
            let windowWorkouts = workouts.filter {
                guard let date = $0.date else { return false }
                return date > start && date <= range.upperBound
            }
            return MuscleBalanceBucket(
                id: String(Int(start.timeIntervalSince1970)),
                start: start,
                axisLabel: window.axisLabel(forWindowEnding: range.upperBound),
                title: window.windowTitle(windowsAgo: windowsAgo, from: now),
                calculator: MuscleBalanceCalculator(
                    workouts: windowWorkouts,
                    target: target,
                    muscleGroupService: muscleGroupService
                )
            )
        }
    }
}
