//
//  ExerciseVolumeTile.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 03.12.24.
//

import Charts
import SwiftUI

/// The full-width weekly volume tile on the exercise detail screen. Unlike the four "current
/// best" tiles it answers "how much did I do *this week*", so its pill compares this week against
/// last week — with the trophy when this week already tops every previous one — and its bar chart
/// gets the whole row (bars need the horizontal room). Sets of the workout currently being
/// recorded are excluded like everywhere on the tiles: the standings update when the session is
/// logged.
struct ExerciseVolumeTile: View {
    let exercise: Exercise
    let workoutSets: [WorkoutSet]

    private struct WeeklyVolume: Identifiable {
        let week: Date
        let volume: Int
        var id: Date { week }
    }

    var body: some View {
        let sets = workoutSets.filter { $0.workout?.isCurrentWorkout != true }
        let weeklyVolumes = weeklyVolumes(in: sets)
        let thisWeekVolume = volume(in: weeklyVolumes, equalTo: .now)
        let lastWeek = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: .now) ?? .now
        let lastWeekVolume = volume(in: weeklyVolumes, equalTo: lastWeek)
        // Baseline for the trend pill: last week, or — when last week was a rest week — the best
        // earlier week, so the pill stays present whenever there's any prior week to compare to.
        let bestPriorWeekVolume = weeklyVolumes.filter { $0.week < Date.now.startOfWeek }.map(\.volume).max() ?? 0
        let volumeBaseline = lastWeekVolume > 0 ? lastWeekVolume : bestPriorWeekVolume
        // No volume in the chart's five-week window but some further back: untrained for over a
        // month. Fall back to the "last best" — the most recent trained week's volume, dated — to
        // match the four best-value tiles, instead of a "0" floating above an empty chart.
        let isLapsed = !weeklyVolumes.isEmpty && !weeklyVolumes.contains { $0.week >= chartStartDate }
        // The day the last-best week was logged: the latest weighted set, so the date lines up with
        // the week the value comes from. Only set while lapsed.
        let lastBestDate = isLapsed ? sets.filter { $0.volume(for: exercise) > 0 }.compactMap({ $0.workout?.date }).max() : nil
        let muscleColor = exercise.muscleGroup?.color ?? .accentColor
        MetricTile(
            title: NSLocalizedString("volume", comment: ""),
            label: .plain(NSLocalizedString(isLapsed ? "lastBest" : "thisWeek", comment: "")),
            value: weeklyVolumes.isEmpty
                ? nil
                : formatWeightForDisplay(isLapsed ? weeklyVolumes.last?.volume ?? 0 : thisWeekVolume),
            unit: WeightUnit.used.rawValue,
            accent: AnyShapeStyle(muscleColor),
            accentColor: muscleColor,
            // This week against the baseline. With a real baseline but nothing logged this week yet,
            // that's a genuine "down 100%" — zero work, not missing data — so the pill says so rather
            // than disappearing. A fully lapsed exercise drops the pill for the last-best date instead.
            percentChange: volumeBaseline > 0 && !isLapsed
                ? (Double(thisWeekVolume) - Double(volumeBaseline)) / Double(volumeBaseline) * 100
                : nil,
            isRecord: isRecordWeek(volume: thisWeekVolume, in: weeklyVolumes),
            requiresPro: true,
            lastBestDate: lastBestDate,
            showsEmptyPlaceholder: weeklyVolumes.isEmpty,
            chartBleeds: false
        ) {
            // Lapsed → no chart, matching the four best-value tiles (the date carries the story); the
            // empty slot keeps the row height. Otherwise the regular five-week bars.
            if isLapsed {
                Color.clear
            } else {
                barChart(weeklyVolumes: weeklyVolumes)
            }
        }
    }

    // MARK: - Chart

    private func barChart(weeklyVolumes: [WeeklyVolume]) -> some View {
        // The regular five-week window, current week highlighted. (A lapsed exercise shows no chart
        // at all — see the tile body — so there's no last-trained-weeks variant here anymore.)
        let shownVolumes = weeklyVolumes.filter { $0.week >= chartStartDate }
        return Chart {
            ForEach(shownVolumes) { weeklyVolume in
                BarMark(
                    x: .value("Week", weeklyVolume.week, unit: .weekOfYear),
                    y: .value("Volume in week", convertWeightForDisplayingDecimal(weeklyVolume.volume)),
                    width: TileBarChartStyle.footerBarWidth
                )
                .foregroundStyle(
                    Calendar.current.isDate(weeklyVolume.week, equalTo: Date.now.startOfWeek, toGranularity: .weekOfYear)
                        ? (exercise.muscleGroup?.color ?? .accentColor) : Color.fill
                )
                .tileBarStyle()
            }
        }
        .chartXScale(domain: chartStartDate ... Date.now.endOfWeek)
        .chartXAxis {}
        .chartYAxis {}
    }

    private var chartStartDate: Date {
        (Calendar.current.date(byAdding: .weekOfYear, value: -4, to: .now) ?? .now).startOfWeek
    }

    // MARK: - Weekly Volumes

    /// Volume per trained week across the exercise's whole history, oldest → newest — the chart
    /// shows the last five, the trend and record check need them all. Zero-volume weeks (e.g.
    /// bodyweight-only training) are dropped so they can't render as invisible bars; with no
    /// weighted week at all the tile shows its "––" placeholder instead.
    private func weeklyVolumes(in sets: [WorkoutSet]) -> [WeeklyVolume] {
        Dictionary(grouping: sets) { $0.workout?.date?.startOfWeek ?? .now }
            .map { WeeklyVolume(week: $0.key, volume: getVolume(of: $0.value, for: exercise)) }
            .filter { $0.volume > 0 }
            .sorted { $0.week < $1.week }
    }

    private func volume(in weeklyVolumes: [WeeklyVolume], equalTo date: Date) -> Int {
        weeklyVolumes.first {
            Calendar.current.isDate($0.week, equalTo: date, toGranularity: .weekOfYear)
        }?.volume ?? 0
    }

    /// A record week has to *beat* every previous week, not just match the best — and there has
    /// to be a previous week to beat, or the first trained week would be a record by default.
    private func isRecordWeek(volume: Int, in weeklyVolumes: [WeeklyVolume]) -> Bool {
        let bestPreviousWeek = weeklyVolumes
            .filter { $0.week < Date.now.startOfWeek }
            .map(\.volume)
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
