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
        // No sets in the chart's five-week window but some further back: fall back to the best week
        // ever over the last trained weeks' bars — mirrors the Volume tile's lapsed state instead
        // of a "0" floating above an empty chart.
        let isLapsed = !weeklySets.isEmpty && !weeklySets.contains { $0.week >= chartStartDate }
        ExerciseMetricTileLayout(
            title: NSLocalizedString("sets", comment: ""),
            label: .plain(NSLocalizedString(isLapsed ? "personalBest" : "thisWeek", comment: "")),
            value: weeklySets.isEmpty
                ? nil
                : "\(isLapsed ? weeklySets.map(\.count).max() ?? 0 : thisWeekCount)",
            // A count needs no unit — the title ("Sets") and label ("This Week") carry the meaning,
            // and an empty unit renders as nothing through UnitView.
            unit: "",
            color: exercise.muscleGroup?.color ?? .accentColor,
            percentChange: thisWeekCount > 0 && lastWeekCount > 0
                ? (Double(thisWeekCount) - Double(lastWeekCount)) / Double(lastWeekCount) * 100
                : nil,
            isRecord: isRecordWeek(count: thisWeekCount, in: weeklySets),
            requiresPro: true,
            lapsedSince: isLapsed ? sets.compactMap({ $0.workout?.date }).max() : nil,
            showsEmptyPlaceholder: weeklySets.isEmpty
        ) {
            barChart(weeklySets: weeklySets, isLapsed: isLapsed)
        }
    }

    // MARK: - Chart

    private func barChart(weeklySets: [WeeklySets], isLapsed: Bool) -> some View {
        // Lapsed: the last five trained weeks, with the best one highlighted (it's the week the
        // value above refers to). Otherwise: the regular five-week window, current week
        // highlighted.
        let shownSets = isLapsed
            ? Array(weeklySets.suffix(5))
            : weeklySets.filter { $0.week >= chartStartDate }
        let highlightedWeek = isLapsed
            ? shownSets.max { $0.count < $1.count }?.week
            : Date.now.startOfWeek
        let domainStart = isLapsed ? (shownSets.first?.week ?? chartStartDate) : chartStartDate
        let domainEnd = isLapsed
            ? (shownSets.last?.week.endOfWeek ?? Date.now.endOfWeek) : Date.now.endOfWeek
        return Chart {
            ForEach(shownSets) { weeklySet in
                BarMark(
                    x: .value("Week", weeklySet.week, unit: .weekOfYear),
                    y: .value("Sets in week", weeklySet.count),
                    width: .ratio(0.5)
                )
                .foregroundStyle(
                    highlightedWeek.map({ Calendar.current.isDate(weeklySet.week, equalTo: $0, toGranularity: .weekOfYear) }) == true
                        ? (exercise.muscleGroup?.color ?? Color.label) : Color.fill
                )
            }
        }
        .chartXScale(domain: domainStart ... domainEnd)
        .chartXAxis {}
        .chartYAxis {}
        .frame(maxWidth: .infinity)
        .frame(height: 62)
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
