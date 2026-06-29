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
/// **in memory** by date range (no new Core Data fetches) — the way `OverallSetsTile`/`VolumeTile`
/// already do. The period selector, the 2×2 core-stats grid, the Muscle Balance tile and the Records
/// tile all read their window off this.
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
    static let statBucketCount = 5

    // MARK: - Stat Data

    /// Everything a core-stat tile renders: the current period's value, the change versus the prior
    /// period, and the last five periods as display-unit buckets (oldest → newest, last = current).
    struct StatData {
        let rawValue: Int
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
        var rawBuckets: [Int] = []
        for n in stride(from: Self.statBucketCount - 1, through: 0, by: -1) {
            let range = period.range(periodsAgo: n)
            let sum = workouts
                .filter { ($0.date).map { range.contains($0) } ?? false }
                .reduce(0) { $0 + metric.rawValue(of: $1) }
            rawBuckets.append(sum)
        }
        let current = rawBuckets.last ?? 0
        let previous = rawBuckets.count >= 2 ? rawBuckets[rawBuckets.count - 2] : 0
        let percentChange: Double? = previous > 0
            ? (Double(current) - Double(previous)) / Double(previous) * 100
            : nil
        return StatData(
            rawValue: current,
            percentChange: percentChange,
            buckets: rawBuckets.map { metric.displayValue(fromRaw: $0) }
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
}
