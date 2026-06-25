//
//  ExerciseSetsTile.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 22.06.26.
//

import Charts
import SwiftUI

/// The weekly *sets* tile on the exercise detail screen, sitting beside the weekly Volume tile and
/// sharing its shape. Where Volume answers "how much total weight did I move this week", this
/// answers "how many working sets did I do this week" — the standard training-volume landmark (the
/// "10–20 sets per week" guideline). Like Volume it compares this week against last week, wears the
/// trophy when this week already tops every previous one, and excludes the sets of the workout
/// currently being recorded so the tile tells the standing going *into* this session.
struct ExerciseSetsTile: View {
    let exercise: Exercise
    let workoutSets: [WorkoutSet]

    private struct WeeklySets: Identifiable {
        let week: Date
        let count: Int
        var id: Date { week }
    }

    var body: some View {
        let sets = workoutSets.filter { $0.workout?.isCurrentWorkout != true }
        let weeklySets = weeklySets(in: sets)
        let thisWeekCount = count(in: weeklySets, equalTo: .now)
        let lastWeek = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: .now) ?? .now
        let lastWeekCount = count(in: weeklySets, equalTo: lastWeek)
        // Baseline for the trend pill: last week, or — when last week was a rest week — the best
        // earlier week, so the pill stays present whenever there's any prior week to compare to.
        let bestPriorWeekCount = weeklySets.filter { $0.week < Date.now.startOfWeek }.map(\.count).max() ?? 0
        let countBaseline = lastWeekCount > 0 ? lastWeekCount : bestPriorWeekCount
        // No sets in the chart's five-week window but some further back: untrained for over a month.
        // Fall back to the "last best" — the most recent trained week's set count, dated — to match
        // the four best-value tiles, instead of a "0" floating above an empty chart.
        let isLapsed = !weeklySets.isEmpty && !weeklySets.contains { $0.week >= chartStartDate }
        // The day the last-best week was logged: the latest completed set, so the date lines up with
        // the week the value comes from. Only set while lapsed.
        let lastBestDate = isLapsed ? sets.filter(\.hasEntry).compactMap({ $0.workout?.date }).max() : nil
        let muscleColor = exercise.muscleGroup?.color ?? .accentColor
        MetricTile(
            title: NSLocalizedString("sets", comment: ""),
            label: .plain(NSLocalizedString(isLapsed ? "lastBest" : "thisWeek", comment: "")),
            value: weeklySets.isEmpty
                ? nil
                : "\(isLapsed ? weeklySets.last?.count ?? 0 : thisWeekCount)",
            // A count needs no unit — the title ("Sets") and label ("This Week") carry the meaning,
            // and an empty unit renders as nothing through UnitView.
            unit: "",
            accent: AnyShapeStyle(muscleColor),
            accentColor: muscleColor,
            // This week against the baseline. With a real baseline but nothing logged this week yet,
            // that's a genuine "down 100%" — zero work, not missing data — so the pill says so rather
            // than disappearing. A fully lapsed exercise drops the pill for the last-best date instead.
            percentChange: countBaseline > 0 && !isLapsed
                ? (Double(thisWeekCount) - Double(countBaseline)) / Double(countBaseline) * 100
                : nil,
            isRecord: isRecordWeek(count: thisWeekCount, in: weeklySets),
            requiresPro: true,
            lastBestDate: lastBestDate,
            showsEmptyPlaceholder: weeklySets.isEmpty
        ) {
            // Lapsed → no chart, matching the four best-value tiles (the date carries the story); the
            // empty slot keeps the row height. Otherwise the regular five-week bars.
            if isLapsed {
                Color.clear
            } else {
                barChart(weeklySets: weeklySets)
            }
        }
    }

    // MARK: - Chart

    private func barChart(weeklySets: [WeeklySets]) -> some View {
        // The regular five-week window, current week highlighted. (A lapsed exercise shows no chart
        // at all — see the tile body — so there's no last-trained-weeks variant here anymore.)
        let shownSets = weeklySets.filter { $0.week >= chartStartDate }
        return Chart {
            ForEach(shownSets) { weeklySet in
                BarMark(
                    x: .value("Week", weeklySet.week, unit: .weekOfYear),
                    y: .value("Sets in week", weeklySet.count),
                    width: TileBarChartStyle.barWidth
                )
                .foregroundStyle(
                    Calendar.current.isDate(weeklySet.week, equalTo: Date.now.startOfWeek, toGranularity: .weekOfYear)
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

    // MARK: - Weekly Sets

    /// Working-set count per trained week across the exercise's whole history, oldest → newest —
    /// the chart shows the last five, the trend and record check need them all. A set counts only
    /// when it has an entry (`hasEntry`); empty, unfilled sets aren't training volume. Weeks that
    /// end up with no completed set are dropped so they can't render as invisible bars.
    private func weeklySets(in sets: [WorkoutSet]) -> [WeeklySets] {
        Dictionary(grouping: sets) { $0.workout?.date?.startOfWeek ?? .now }
            .map { WeeklySets(week: $0.key, count: $0.value.filter(\.hasEntry).count) }
            .filter { $0.count > 0 }
            .sorted { $0.week < $1.week }
    }

    private func count(in weeklySets: [WeeklySets], equalTo date: Date) -> Int {
        weeklySets.first {
            Calendar.current.isDate($0.week, equalTo: date, toGranularity: .weekOfYear)
        }?.count ?? 0
    }

    /// A record week has to *beat* every previous week, not just match the best — and there has to
    /// be a previous week to beat, or the first trained week would be a record by default.
    private func isRecordWeek(count: Int, in weeklySets: [WeeklySets]) -> Bool {
        let bestPreviousWeek = weeklySets
            .filter { $0.week < Date.now.startOfWeek }
            .map(\.count)
            .max() ?? 0
        return count > 0 && bestPreviousWeek > 0 && count > bestPreviousWeek
    }
}

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database

    var body: some View {
        NavigationStack {
            ExerciseSetsTile(exercise: database.getExercises().first!, workoutSets: database.getExercises().flatMap { $0.sets })
        }
    }
}

struct ExerciseSetsTileView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
            .padding()
    }
}
