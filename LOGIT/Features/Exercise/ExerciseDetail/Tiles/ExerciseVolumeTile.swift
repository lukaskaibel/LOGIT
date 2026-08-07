//
//  ExerciseVolumeTile.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 03.12.24.
//

import Charts
import SwiftUI

/// The full-width volume tile. Unlike the four "best value" tiles it answers "how much did I do",
/// so its pill compares the current period against the one before it and its bar chart gets the
/// whole row (bars need the horizontal room). Sets of the workout currently being recorded are
/// excluded like everywhere on the tiles: the standings update when the session is logged.
///
/// Its period comes from `window`. On the exercise detail screen that's nil and the tile is weekly —
/// "Volume · This Week", the reading it has always had, and the one the screen around it is built
/// for. Pinned on the Summary it gets that screen's selected `TrendWindow` instead, so a pinned
/// volume tile covers the same span as every other tile beside it rather than being the one square
/// on the grid still reporting a calendar week.
struct ExerciseVolumeTile: View {
    let exercise: Exercise
    let workoutSets: [WorkoutSet]
    /// Leads the tile with the exercise name and moves the metric name into the subtitle (the pinned
    /// Summary grid); see `ExerciseBestMetricTile`. Off by default (the detail screen).
    var showsExerciseName: Bool = false
    /// The period one bar covers: nil for calendar weeks, otherwise the Summary's rolling window.
    var window: TrendWindow? = nil

    /// Bars in the footer chart — the current period plus the four before it.
    private static let bucketCount = 5

    /// One period's volume. `start` is the period's first instant, which is what the bars are keyed
    /// and sorted by whether the periods are calendar weeks or rolling windows.
    private struct PeriodVolume: Identifiable {
        let start: Date
        let end: Date
        let volume: Int
        var id: Date { start }
    }

    var body: some View {
        let sets = workoutSets.filter { $0.workout?.isCurrentWorkout != true }
        let shown = shownVolumes(in: sets)
        let currentVolume = shown.last?.volume ?? 0
        let previousVolume = shown.dropLast().last?.volume ?? 0
        // Baseline for the trend pill: the period before, or — when that one was a rest period — the
        // best earlier period shown, so the pill stays present whenever there's a prior period to
        // compare to.
        let bestPriorVolume = shown.dropLast().map(\.volume).max() ?? 0
        let baseline = previousVolume > 0 ? previousVolume : bestPriorVolume
        let hasAnyVolume = sets.contains { $0.volume(for: exercise) > 0 }
        // No volume anywhere in the five shown periods but some further back: untrained for longer
        // than the chart reaches. Fall back to the "last best" — the most recent trained period's
        // volume, dated — to match the four best-value tiles, instead of a "0" over an empty chart.
        let isLapsed = hasAnyVolume && !shown.contains { $0.volume > 0 }
        let lastBest = isLapsed ? lastTrainedPeriod(in: sets) : nil
        let muscleColor = exercise.muscleGroup?.color ?? .accentColor
        MetricTile(
            title: showsExerciseName ? exercise.displayName : NSLocalizedString("volume", comment: ""),
            // Pinned: the exercise name is the title, so the subtitle names the metric ("Volume") —
            // and the screen's picker already names the span, so the tile must not name it again.
            // Detail: the metric name is already the title, so the subtitle qualifies the value's
            // span ("This Week", or "Last Best" once the exercise has lapsed).
            label: .plain(NSLocalizedString(
                showsExerciseName ? "volume" : (isLapsed ? "lastBest" : "thisWeek"),
                comment: ""
            )),
            value: !hasAnyVolume
                ? nil
                : formatWeightForDisplay(isLapsed ? (lastBest?.volume ?? 0) : currentVolume),
            unit: WeightUnit.used.rawValue,
            accent: AnyShapeStyle(muscleColor),
            accentColor: muscleColor,
            // The current period against the baseline. With a real baseline but nothing logged in
            // this period yet, that's a genuine "down 100%" — zero work, not missing data — so the
            // pill says so rather than disappearing. A fully lapsed exercise drops the pill for the
            // last-best date instead.
            percentChange: baseline > 0 && !isLapsed
                ? (Double(currentVolume) - Double(baseline)) / Double(baseline) * 100
                : nil,
            isRecord: isRecordPeriod(volume: currentVolume, in: sets),
            requiresPro: true,
            lastBestDate: lastBest?.date,
            showsEmptyPlaceholder: !hasAnyVolume,
            chartBleeds: false
        ) {
            // Lapsed → no chart, matching the four best-value tiles (the date carries the story); the
            // empty slot keeps the row height. Otherwise the regular five bars.
            if isLapsed {
                Color.clear
            } else {
                barChart(shown)
            }
        }
    }

    // MARK: - Chart

    /// The five periods as bars, the current one highlighted. Bars are keyed by their period's start
    /// as a plain category rather than binned by a calendar unit: a rolling window has no unit to
    /// bin by, and binning weeks by `.weekOfYear` only ever restated what the keys already say.
    private func barChart(_ shown: [PeriodVolume]) -> some View {
        Chart {
            ForEach(shown) { period in
                BarMark(
                    x: .value("Period", period.start),
                    y: .value("Volume", convertWeightForDisplayingDecimal(period.volume)),
                    width: TileBarChartStyle.footerBarWidth
                )
                .foregroundStyle(
                    period.id == shown.last?.id
                        ? (exercise.muscleGroup?.color ?? .accentColor) : Color.fill
                )
                .tileBarStyle()
            }
        }
        .chartXScale(domain: chartDomain(shown))
        .chartXAxis {}
        .chartYAxis {}
    }

    /// The plot's span: the oldest shown period's start through the newest one's end, so the five
    /// bars sit evenly however long a period is.
    private func chartDomain(_ shown: [PeriodVolume]) -> ClosedRange<Date> {
        guard let first = shown.first, let last = shown.last, first.start < last.end else {
            return Date.now.startOfWeek ... Date.now.endOfWeek
        }
        return first.start ... last.end
    }

    // MARK: - Periods

    /// The five periods the tile reports on, oldest → newest, the last one current. Rolling windows
    /// come straight off `TrendWindow`; weeks are counted back from this week's start.
    private func shownVolumes(in sets: [WorkoutSet]) -> [PeriodVolume] {
        (0 ..< Self.bucketCount).reversed().map { periodsAgo in
            let range = periodRange(periodsAgo: periodsAgo)
            // Half-open at the lower edge so a set on the instant two periods share counts once.
            let periodSets = sets.filter { set in
                guard let date = set.workout?.date else { return false }
                return date > range.lowerBound && date <= range.upperBound
            }
            return PeriodVolume(
                start: range.lowerBound,
                end: range.upperBound,
                volume: getVolume(of: periodSets, for: exercise)
            )
        }
    }

    private func periodRange(periodsAgo n: Int) -> ClosedRange<Date> {
        if let window {
            return window.range(windowsAgo: n)
        }
        let calendar = Calendar.current
        let anchor = calendar.date(byAdding: .weekOfYear, value: -n, to: .now) ?? .now
        // The week's start is exclusive here (see `shownVolumes`), so back it off an instant —
        // otherwise a set logged exactly at midnight on a Monday would fall out of its own week.
        return anchor.startOfWeek.addingTimeInterval(-1) ... anchor.endOfWeek
    }

    /// The most recent trained period's volume and the day it was logged — the "last best" shown once
    /// the exercise has lapsed out of the chart.
    private func lastTrainedPeriod(in sets: [WorkoutSet]) -> (volume: Int, date: Date)? {
        let withVolume = sets.filter { $0.volume(for: exercise) > 0 }
        guard let lastDate = withVolume.compactMap({ $0.workout?.date }).max() else { return nil }
        let range = window.map { $0.currentRange(from: lastDate) }
            ?? (lastDate.startOfWeek.addingTimeInterval(-1) ... lastDate.endOfWeek)
        let periodSets = withVolume.filter { set in
            guard let date = set.workout?.date else { return false }
            return date > range.lowerBound && date <= range.upperBound
        }
        return (getVolume(of: periodSets, for: exercise), lastDate)
    }

    /// The trophy — only in weekly mode. A record week has to *beat* every previous week, not just
    /// match the best, and there has to be a previous week to beat or the first trained week would be
    /// a record by default.
    ///
    /// Rolling windows get no trophy at all. Every instant starts a window, so "the best window ever"
    /// isn't a thing the history contains — only the arbitrary five the chart happens to draw — and a
    /// trophy for beating those would claim far more than it means.
    private func isRecordPeriod(volume: Int, in sets: [WorkoutSet]) -> Bool {
        guard window == nil else { return false }
        let weekStart = Date.now.startOfWeek
        let bestPreviousWeek = Dictionary(grouping: sets) { $0.workout?.date?.startOfWeek ?? .now }
            .filter { $0.key < weekStart }
            .map { getVolume(of: $0.value, for: exercise) }
            .max() ?? 0
        return volume > 0 && bestPreviousWeek > 0 && volume > bestPreviousWeek
    }
}

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database

    var body: some View {
        NavigationStack {
            ExerciseVolumeTile(exercise: database.getExercises().first!, workoutSets: database.getExercises().flatMap { $0.sets })
        }
    }
}

struct ExerciseVolumeTileView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
            .padding()
    }
}
