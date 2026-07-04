//
//  MuscleBalanceHistory.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 01.07.26.
//

import Foundation

/// One period instance (a specific week / month / year) in the Muscle Groups overview's history strip:
/// its start date, the short label under its bar, the fuller title the selected-period header shows, and
/// the balance calculator for the sets trained in it. The overview builds `bucketCount(for:)` of these
/// back from now, renders them as the normalized segmented bar chart, and drives the value columns off
/// whichever bucket is selected.
struct MuscleBalanceBucket: Identifiable {
    /// Stable, unique key — the period start's epoch seconds. Used as the chart's x-category and the
    /// selection value, since the human labels aren't guaranteed unique across a window.
    let id: String
    let start: Date
    /// Short label under the bar (e.g. "16", "Jun", "2026").
    let axisLabel: String
    /// Full title for the selected-period header (e.g. "This Week", "Jun 9", "June", "2026").
    let title: String
    let calculator: MuscleBalanceCalculator

    var totalSets: Int { calculator.totalSets }
}

/// Builds the Muscle Groups overview's history strip: a run of `MuscleBalanceBucket`s, oldest first, one
/// per period back from now — reusing `StatPeriod.range(periodsAgo:)` (the same windowing every trend
/// pill uses) so the week boundary respects the user's locale.
enum MuscleBalanceHistory {
    /// How many periods back the chart shows — the app-wide history depth rule.
    static func bucketCount(for period: StatPeriod) -> Int {
        period.historyBucketCount
    }

    /// The history strip, oldest bucket first → newest last (index `count - 1` is the current period).
    static func buckets(
        from workouts: [Workout],
        period: StatPeriod,
        target: MuscleTargetSplit,
        muscleGroupService: MuscleGroupService,
        now: Date = .now
    ) -> [MuscleBalanceBucket] {
        let count = bucketCount(for: period)
        return (0 ..< count).reversed().map { periodsAgo in
            let range = period.range(periodsAgo: periodsAgo, from: now)
            let start = range.lowerBound
            let periodWorkouts = workouts.filter { ($0.date).map { range.contains($0) } ?? false }
            return MuscleBalanceBucket(
                id: String(Int(start.timeIntervalSince1970)),
                start: start,
                axisLabel: axisLabel(for: start, period: period),
                title: title(for: start, period: period, isCurrent: periodsAgo == 0),
                calculator: MuscleBalanceCalculator(
                    workouts: periodWorkouts,
                    target: target,
                    muscleGroupService: muscleGroupService
                )
            )
        }
    }

    // MARK: - Labels

    private static func axisLabel(for date: Date, period: StatPeriod) -> String {
        switch period {
        case .week: return date.formatted(.dateTime.day())
        // Single-letter months — twelve slim candles leave no room for "Jun"-style labels.
        case .month: return date.formatted(.dateTime.month(.narrow))
        case .year: return date.formatted(.dateTime.year())
        }
    }

    private static func title(for date: Date, period: StatPeriod, isCurrent: Bool) -> String {
        if isCurrent {
            switch period {
            case .week: return NSLocalizedString("thisWeek", comment: "")
            case .month: return NSLocalizedString("thisMonth", comment: "")
            case .year: return NSLocalizedString("thisYear", comment: "")
            }
        }
        switch period {
        case .week:
            return date.formatted(.dateTime.month(.abbreviated).day())
        case .month:
            let sameYear = Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
            return sameYear
                ? date.formatted(.dateTime.month(.wide))
                : date.formatted(.dateTime.month(.abbreviated).year())
        case .year:
            return date.formatted(.dateTime.year())
        }
    }
}
