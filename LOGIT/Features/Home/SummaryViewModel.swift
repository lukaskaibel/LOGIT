//
//  SummaryViewModel.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import Combine
import Foundation

/// Backs the redesigned Summary screen's period-scoped block. Holds the selected Week/Month/Year
/// period and the one-time auto-fallback state, and filters the already-fetched top-level `[Workout]`
/// **in memory** by date range (no new Core Data fetches). The period selector, the 2×2 core-stats
/// grid, the Muscle Balance tile and the Records tile all read their window off this.
@MainActor
final class SummaryViewModel: ObservableObject {
    /// The user-facing scope governing the whole scoped block. Defaults to the current week; the
    /// auto-fallback may bump it to month/year on a blank Monday until the user picks a segment.
    @Published var selectedPeriod: StatPeriod = .week
    /// Whether `selectedPeriod` was bumped past an empty week by the auto-fallback — drives the
    /// "showing this month" hint row on the empty-state screen.
    @Published private(set) var didAutoFallback = false

    /// Once the user taps a segment the auto-fallback stops second-guessing them.
    private var userHasSelected = false

    /// The number of history buckets the core-stat mini bar charts show (current + 4 prior periods).
    /// Buckets in a stat tile's mini bar chart — the fixed five-slot preview idiom shared with the
    /// workout tiles' run bars. Deliberately shorter than `StatPeriod.historyBucketCount`, which
    /// every labeled detail history follows; the tile is a glanceable teaser, the screen the reading
    /// surface.
    static let statBucketCount = 5

    // MARK: - Stat Data

    /// Everything a core-stat tile renders. The tile reads a *per-workout average* — a typical
    /// session, frequency divided out — so a light week and a heavy week compare on session quality
    /// rather than on how many times the user showed up (that lives in the weekly-goal hero above).
    /// The current period's average, the change versus the prior period's average, and the last five
    /// periods as display-unit buckets (oldest → newest, last = current).
    struct StatData {
        /// The current period's per-workout average in raw units (grams / minutes / counts); 0 when
        /// the period had no workout.
        let rawAverage: Double
        /// Whether the current period had any workout to average — false renders the "––" no-data
        /// tile instead of a misleading "0", since there is no session to average.
        let hasData: Bool
        let percentChange: Double?
        let buckets: [Double]
    }

    // MARK: - Period resolution

    /// On appear: keep the week if it has any workouts, else fall back to the first larger period that
    /// does (month, then year), once. Ref `summary-empty-state.html`.
    func resolveInitialPeriod(workouts: [Workout]) {
        guard !userHasSelected else { return }
        if !filtered(workouts, to: .week).isEmpty {
            set(.week, autoFallback: false)
            return
        }
        for period in [StatPeriod.month, .year] where !filtered(workouts, to: period).isEmpty {
            set(period, autoFallback: true)
            return
        }
        set(.week, autoFallback: false)
    }

    /// The PeriodPicker's setter routes through here so a manual pick disables further auto-fallback.
    func userSelected(_ period: StatPeriod) {
        userHasSelected = true
        set(period, autoFallback: false)
    }

    private func set(_ period: StatPeriod, autoFallback: Bool) {
        selectedPeriod = period
        didAutoFallback = autoFallback
    }

    // MARK: - Mode

    enum SummaryMode { case firstOpen, normal }

    /// `firstOpen` until at least one non-empty workout has ever been logged — drives the welcome
    /// preview grid vs the full dashboard.
    func mode(workouts: [Workout]) -> SummaryMode {
        workouts.contains { !$0.isEmpty } ? .normal : .firstOpen
    }

    // MARK: - Filtering

    /// Non-empty workouts whose date falls inside the period's current range.
    func filtered(_ workouts: [Workout], to period: StatPeriod) -> [Workout] {
        let range = period.currentRange()
        return workouts.filter { workout in
            guard !workout.isEmpty, let date = workout.date else { return false }
            return range.contains(date)
        }
    }

    // MARK: - Core stats

    func statData(for metric: WorkoutStatMetric, period: StatPeriod, workouts: [Workout]) -> StatData {
        // Per bucket: the per-workout average (sum ÷ non-empty workout count), the divisor matching
        // the "3 workouts" the weekly-goal hero counts so the tile reads as "per one of those". Empty
        // workouts are excluded — they'd only drag an average down while inflating the count; a blank
        // workout contributed nothing to the old sum either.
        var averages: [Double] = []
        var counts: [Int] = []
        for n in stride(from: Self.statBucketCount - 1, through: 0, by: -1) {
            let range = period.range(periodsAgo: n)
            let periodWorkouts = workouts.filter { workout in
                guard !workout.isEmpty, let date = workout.date else { return false }
                return range.contains(date)
            }
            let sum = periodWorkouts.reduce(0) { $0 + metric.rawValue(of: $1) }
            averages.append(StatBasis.perWorkout.aggregate(sum: sum, count: periodWorkouts.count))
            counts.append(periodWorkouts.count)
        }
        let currentAverage = averages.last ?? 0
        let currentCount = counts.last ?? 0
        let previousAverage = averages.count >= 2 ? averages[averages.count - 2] : 0
        let previousCount = counts.count >= 2 ? counts[counts.count - 2] : 0
        // Both periods need a session to compare — a fresh, still-empty week never reads as a collapse.
        let percentChange: Double? = (currentCount > 0 && previousCount > 0 && previousAverage > 0)
            ? (currentAverage - previousAverage) / previousAverage * 100
            : nil
        return StatData(
            rawAverage: currentAverage,
            hasData: currentCount > 0,
            percentChange: percentChange,
            buckets: averages.map { metric.displayValue(fromRaw: Int($0.rounded())) }
        )
    }

    // MARK: - Weekly streak

    /// Consecutive weeks meeting the weekly target, counting back from the most recent completed week.
    /// The in-progress current week adds to the streak only once it's met (so a 3/4 week still shows
    /// the run of completed weeks behind it); any week under target breaks the chain. No deload
    /// "freeze" in v1 — easy to add later.
    nonisolated static func currentWeeklyStreak(workouts: [Workout], target: Int, reference: Date = .now) -> Int {
        var countsByWeek: [Date: Int] = [:]
        for workout in workouts where !workout.isEmpty {
            guard let date = workout.date else { continue }
            countsByWeek[date.startOfWeek, default: 0] += 1
        }
        return weeklyStreak(countsByWeek: countsByWeek, target: target, reference: reference)
    }

    /// The pure core of the streak calc, keyed by week-start → workout count, so it can be unit-tested
    /// without a Core Data store.
    nonisolated static func weeklyStreak(countsByWeek: [Date: Int], target: Int, reference: Date = .now) -> Int {
        guard target > 0 else { return 0 }
        let calendar = Calendar.current
        var streak = 0
        var weekStart = reference.startOfWeek
        // The current week only counts once already met; an unmet current week neither adds nor breaks.
        if (countsByWeek[weekStart] ?? 0) >= target { streak += 1 }
        weekStart = (calendar.date(byAdding: .weekOfYear, value: -1, to: weekStart) ?? weekStart).startOfWeek
        while (countsByWeek[weekStart] ?? 0) >= target {
            streak += 1
            weekStart = (calendar.date(byAdding: .weekOfYear, value: -1, to: weekStart) ?? weekStart).startOfWeek
        }
        return streak
    }

    /// The all-time longest run of consecutive weeks meeting the target — the record the current
    /// streak is chasing. Walks every week from the first workout to now so empty weeks break the run.
    nonisolated static func longestWeeklyStreak(workouts: [Workout], target: Int) -> Int {
        var countsByWeek: [Date: Int] = [:]
        for workout in workouts where !workout.isEmpty {
            guard let date = workout.date else { continue }
            countsByWeek[date.startOfWeek, default: 0] += 1
        }
        return longestWeeklyStreak(countsByWeek: countsByWeek, target: target)
    }

    /// The pure core of the longest-streak calc, keyed by week-start → workout count, so it can be
    /// unit-tested without a Core Data store. Iterates week-by-week (not just weeks with workouts) so
    /// an empty week correctly resets the run.
    nonisolated static func longestWeeklyStreak(countsByWeek: [Date: Int], target: Int, reference: Date = .now) -> Int {
        guard target > 0, let earliest = countsByWeek.keys.min() else { return 0 }
        let calendar = Calendar.current
        var best = 0
        var run = 0
        var weekStart = earliest
        let lastWeek = reference.startOfWeek
        while weekStart <= lastWeek {
            if (countsByWeek[weekStart] ?? 0) >= target {
                run += 1
                best = max(best, run)
            } else {
                run = 0
            }
            weekStart = (calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? weekStart).startOfWeek
        }
        return best
    }

    /// The longest COMPLETED weekly streak that is not the current ongoing run — i.e. the record the
    /// current streak is chasing, or the one it just surpassed. Excludes the run ending at `reference`.
    nonisolated static func previousBestWeeklyStreak(workouts: [Workout], target: Int) -> Int {
        var countsByWeek: [Date: Int] = [:]
        for workout in workouts where !workout.isEmpty {
            guard let date = workout.date else { continue }
            countsByWeek[date.startOfWeek, default: 0] += 1
        }
        return previousBestWeeklyStreak(countsByWeek: countsByWeek, target: target)
    }

    nonisolated static func previousBestWeeklyStreak(countsByWeek: [Date: Int], target: Int, reference: Date = .now) -> Int {
        guard target > 0, let earliest = countsByWeek.keys.min() else { return 0 }
        let calendar = Calendar.current
        var runs: [Int] = []
        var run = 0
        var weekStart = earliest
        let referenceWeekStart = reference.startOfWeek
        while weekStart <= referenceWeekStart {
            if (countsByWeek[weekStart] ?? 0) >= target {
                run += 1
            } else {
                if run > 0 { runs.append(run) }
                run = 0
            }
            weekStart = (calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? weekStart).startOfWeek
        }
        if run > 0 { runs.append(run) }
        // The most recent run (last element) is the current ongoing streak; the record being chased is
        // the longest of the rest. With no current run, every run counts.
        let current = weeklyStreak(countsByWeek: countsByWeek, target: target, reference: reference)
        if current > 0 {
            return runs.dropLast().max() ?? 0
        }
        return runs.max() ?? 0
    }
}
