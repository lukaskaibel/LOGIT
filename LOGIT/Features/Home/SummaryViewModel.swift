//
//  SummaryViewModel.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import Combine
import Foundation

/// Backs the Summary's scoped block: filters the already-fetched top-level `[Workout]` **in memory**
/// by date range (no new Core Data fetches) and reduces it to what a stat tile draws. The 2×2
/// core-stats grid reads its window off this.
///
/// The window is a rolling `TrendWindow`, not a calendar period, and it comes from the screen's own
/// picker rather than living here — the whole Summary reads one timeframe now, so no single view
/// model owns it. The move off calendar months is what makes the four tiles comparable with the
/// Strength and Balance pair above them: a month-scoped tile on the 3rd reported four days of
/// training beside a pair reporting four weeks, and nothing on screen said so.
@MainActor
final class SummaryViewModel: ObservableObject {
    // MARK: - Stat Data

    /// Everything a core-stat tile renders. The tile reads a *per-workout average* — a typical
    /// session, frequency divided out — so a light window and a heavy one compare on session quality
    /// rather than on how many times the user showed up (that lives in the weekly-goal pill above).
    ///
    /// A per-workout average is also what lets the tile survive the window switch at all: it is the
    /// same magnitude over four weeks as over a year, so the reader can widen the scope and still
    /// read the number against the one they just saw. A running total would have ballooned by an
    /// order of magnitude and broken the tile's own five-bar history with it.
    struct StatData {
        /// The current window's per-workout average in raw units (grams / minutes / counts); 0 when
        /// the window had no workout.
        let rawAverage: Double
        /// Whether the current window had any workout to average — false renders the "––" no-data
        /// tile instead of a misleading "0", since there is no session to average.
        let hasData: Bool
        let percentChange: Double?
        /// The selected window's bins in display units, oldest → newest — one per day, week or month
        /// of it (see `TrendWindow.bin`). Every one is in scope, so the tile draws them all in the
        /// accent; a zero is an untrained bin and draws no bar at all.
        let bins: [Double]
        /// How much of the current-plus-previous window span the logged history covers, 0…1 — the
        /// fill of the "building your trend" ring while the window holds too little to draw.
        let historyFraction: Double
    }

    // MARK: - Mode

    enum SummaryMode { case firstOpen, normal }

    /// `firstOpen` until at least one non-empty workout has ever been logged — drives the welcome
    /// preview grid vs the full dashboard.
    func mode(workouts: [Workout]) -> SummaryMode {
        workouts.contains { !$0.isEmpty } ? .normal : .firstOpen
    }

    // MARK: - Filtering

    /// Non-empty workouts falling inside the current window — what the Balance tile is handed.
    func filtered(_ workouts: [Workout], to window: TrendWindow) -> [Workout] {
        workouts.filter { workout in
            guard !workout.isEmpty, let date = workout.date else { return false }
            return window.contains(date)
        }
    }

    // MARK: - Core stats

    func statData(for metric: WorkoutStatMetric, window: TrendWindow, workouts: [Workout]) -> StatData {
        // Two windows of bins in one strip: the newer half is what the tile draws and reports, the
        // older half is the baseline its trend pill compares against. Binning both together — rather
        // than filtering the workouts twice — keeps the two spans defined by exactly the same
        // boundaries, which is what makes "up 8%" mean "this window against the one before it".
        let perWindow = window.binsPerWindow
        let ranges = window.binRanges(count: perWindow * 2)
        // Per bin: the metric summed and the non-empty workouts counted. The count is the per-workout
        // divisor — matching the "3 workouts" the weekly-goal pill counts, so the tile reads as "per
        // one of those". Empty workouts are excluded: they'd inflate the divisor while contributing
        // nothing to the sum, dragging the average down for no reason.
        var sums = [Int](repeating: 0, count: ranges.count)
        var counts = [Int](repeating: 0, count: ranges.count)
        for workout in workouts where !workout.isEmpty {
            guard let date = workout.date,
                  let index = TrendWindow.binIndex(of: date, in: ranges) else { continue }
            sums[index] += metric.rawValue(of: workout)
            counts[index] += 1
        }
        let split = ranges.count - perWindow
        let current = Self.aggregate(sums: sums, counts: counts, in: split ..< ranges.count)
        let previous = Self.aggregate(sums: sums, counts: counts, in: 0 ..< split)
        // Both windows need a session to compare — a window that has only just opened never reads as
        // a collapse.
        let percentChange: Double? = (current.count > 0 && previous.count > 0 && previous.average > 0)
            ? (current.average - previous.average) / previous.average * 100
            : nil
        return StatData(
            rawAverage: current.average,
            hasData: current.count > 0,
            percentChange: percentChange,
            // Only the current window's bins are drawn — the older half exists purely as the pill's
            // baseline, and drawing it would put bars outside the timeframe back on the tile.
            bins: (split ..< ranges.count).map { index in
                metric.displayValue(
                    fromRaw: Int(StatBasis.perWorkout.aggregate(sum: sums[index], count: counts[index]).rounded())
                )
            },
            historyFraction: window.historyFraction(
                firstDataDate: workouts.lazy.filter { !$0.isEmpty }.compactMap(\.date).min()
            )
        )
    }

    /// A run of bins collapsed to one window's per-workout average: the metric summed over the
    /// sessions that produced it. Never the mean of the bins' own averages — that would weight a day
    /// holding one workout the same as a day holding two.
    private static func aggregate(
        sums: [Int], counts: [Int], in indices: Range<Int>
    ) -> (average: Double, count: Int) {
        var sum = 0
        var count = 0
        for index in indices where index >= 0 && index < sums.count {
            sum += sums[index]
            count += counts[index]
        }
        return (StatBasis.perWorkout.aggregate(sum: sum, count: count), count)
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
