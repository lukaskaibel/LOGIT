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
/// for: five bars, one per calendar week, the current one tinted.
///
/// Pinned on the Summary it gets that screen's selected `TrendWindow` instead, and then it draws the
/// same thing every other tile under the picker draws: the window split into its **bins** (days for
/// four weeks, weeks for a quarter, months for a year), every bar tinted because every bar is in
/// scope, compared against the equally long window immediately before. It used to show five whole
/// windows with one tinted — so a tile set to "4 weeks" spent four fifths of its chart outside the
/// timeframe — and its pill fell back to the *best* of those five when the previous window was empty,
/// a baseline reaching months outside the span the tile claimed to report.
struct ExerciseVolumeTile: View {
    let exercise: Exercise
    let workoutSets: [WorkoutSet]
    /// Leads the tile with the exercise name and moves the metric name into the subtitle (the pinned
    /// Summary grid); see `ExerciseBestMetricTile`. Off by default (the detail screen).
    var showsExerciseName: Bool = false
    /// The span the tile reports: nil for the calendar week, otherwise the Summary's rolling window.
    var window: TrendWindow? = nil

    /// Bars in the weekly footer chart — this week plus the four before it.
    private static let weekCount = 5

    /// What the tile draws and says, however its span is defined.
    private struct Report {
        /// Bar heights in display units, oldest → newest. A zero draws no bar.
        let bars: [Double]
        /// The reported span's volume, in raw storage units.
        let current: Int
        /// What the trend pill measures against, in raw units. Zero means nothing to compare.
        let baseline: Int
        /// Trained at some point, but not inside anything the tile can show.
        let isLapsed: Bool
    }

    var body: some View {
        let sets = workoutSets.filter { $0.workout?.isCurrentWorkout != true }
        let hasAnyVolume = sets.contains { $0.volume(for: exercise) > 0 }
        let report = window.map { self.windowReport(in: sets, window: $0, hasAnyVolume: hasAnyVolume) }
            ?? weeklyReport(in: sets, hasAnyVolume: hasAnyVolume)
        let currentVolume = report.current
        let baseline = report.baseline
        let isLapsed = report.isLapsed
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
            // empty slot keeps the row height.
            if isLapsed {
                Color.clear
            } else {
                barChart(report.bars)
            }
        }
    }

    // MARK: - Chart

    /// The bars, oldest → newest. Windowed, every bar wears the muscle colour — they are all inside
    /// the selected timeframe. Weekly, only the current week does and the four behind it stay quiet
    /// gray, which is the comparison that mode is built on.
    ///
    /// The x-axis is **categorical** — one slot per bar, keyed by its position — not a date on a
    /// continuous scale. Neither a rolling window nor a mixed run of bins has a calendar unit for
    /// `BarMark` to bin by, and without a bin the axis has no band for a proportional bar width to be
    /// a proportion *of*: the shared `footerBarWidth` ratio resolved to nothing and the bars vanished
    /// entirely. Slots also match how the other tile charts lay their bars out, so every tile's bars
    /// end up the same width.
    private func barChart(_ bars: [Double]) -> some View {
        let slots = (0 ..< max(bars.count, 1)).map(String.init)
        let muscleColor = exercise.muscleGroup?.color ?? .accentColor
        let isWindowed = window != nil
        return Chart {
            ForEach(Array(bars.enumerated()), id: \.offset) { index, value in
                if value > 0 {
                    BarMark(
                        x: .value("Period", String(index)),
                        y: .value("Volume", value),
                        width: TileBarChartStyle.footerBarWidth
                    )
                    .foregroundStyle(
                        isWindowed || index == bars.count - 1 ? muscleColor : Color.fill
                    )
                    .tileBarStyle()
                }
            }
        }
        .chartXScale(domain: slots)
        .chartXAxis {}
        .chartYAxis {}
    }

    // MARK: - Periods

    /// The pinned reading: the selected window split into its bins, against the window before it.
    ///
    /// Both windows are binned in **one** strip so the two spans are defined by exactly the same
    /// boundaries — the same construction the Summary's own stat tiles use — and only the newer half
    /// is drawn. There is no "best earlier period" fallback here: a baseline is the previous window or
    /// there is none, because anything else would compare the named timeframe against an unnamed one.
    private func windowReport(in sets: [WorkoutSet], window: TrendWindow, hasAnyVolume: Bool) -> Report {
        let perWindow = window.binsPerWindow
        let ranges = window.binRanges(count: perWindow * 2)
        var binned = [[WorkoutSet]](repeating: [], count: ranges.count)
        for set in sets {
            guard let date = set.workout?.date,
                  let index = TrendWindow.binIndex(of: date, in: ranges) else { continue }
            binned[index].append(set)
        }
        let volumes = binned.map { getVolume(of: $0, for: exercise) }
        let split = ranges.count - perWindow
        let current = volumes[split...].reduce(0, +)
        let previous = volumes[..<split].reduce(0, +)
        return Report(
            bars: volumes[split...].map { convertWeightForDisplayingDecimal($0) },
            current: current,
            baseline: previous,
            // Trained at some point, but nothing in either window the tile can draw or compare.
            isLapsed: hasAnyVolume && current == 0 && previous == 0
        )
    }

    /// The detail screen's reading: five calendar weeks, this one last. The baseline is last week, or
    /// — when that was a rest week — the best of the weeks on the chart, so the pill stays present
    /// whenever there is a prior week to compare to. That fallback is safe here in a way it is not
    /// under a picker: all five weeks are on screen, and the tile names its span "This Week" rather
    /// than borrowing a timeframe the whole screen claims.
    private func weeklyReport(in sets: [WorkoutSet], hasAnyVolume: Bool) -> Report {
        let volumes = (0 ..< Self.weekCount).reversed().map { weeksAgo -> Int in
            let range = weekRange(weeksAgo: weeksAgo)
            // Half-open at the lower edge so a set on the instant two weeks share counts once.
            let weekSets = sets.filter { set in
                guard let date = set.workout?.date else { return false }
                return date > range.lowerBound && date <= range.upperBound
            }
            return getVolume(of: weekSets, for: exercise)
        }
        let current = volumes.last ?? 0
        let previous = volumes.dropLast().last ?? 0
        let bestPrior = volumes.dropLast().max() ?? 0
        return Report(
            bars: volumes.map { convertWeightForDisplayingDecimal($0) },
            current: current,
            baseline: previous > 0 ? previous : bestPrior,
            isLapsed: hasAnyVolume && !volumes.contains { $0 > 0 }
        )
    }

    private func weekRange(weeksAgo n: Int) -> ClosedRange<Date> {
        let calendar = Calendar.current
        let anchor = calendar.date(byAdding: .weekOfYear, value: -n, to: .now) ?? .now
        // The week's start is exclusive here (see `weeklyReport`), so back it off an instant —
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
