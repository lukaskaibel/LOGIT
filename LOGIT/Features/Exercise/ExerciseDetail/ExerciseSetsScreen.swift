//
//  ExerciseSetsScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 22.06.26.
//

import SwiftUI

/// Working sets per period for a single exercise — the detail screen behind the weekly Sets tile.
/// Sets are an *effort* metric (did I do the work?), so the screen is scoped by the shared
/// `PeriodPicker` exactly like the Summary stat screens: the current calendar week / month / year,
/// a trend against the previous period, and the recent periods as history bars. Structurally the
/// twin of `ExerciseVolumeScreen`, which sums tonnage instead of counting sets.
struct ExerciseSetsScreen: View {
    let exercise: Exercise
    let workoutSets: [WorkoutSet]

    @State private var period: StatPeriod = .week

    var body: some View {
        ScrollView {
            VStack(spacing: SECTION_SPACING) {
                VStack(spacing: 16) {
                    PeriodPicker(selection: $period)
                    header
                    chart
                }
                .padding(.horizontal)
                AboutSection(
                    metricTitle: NSLocalizedString("sets", comment: ""),
                    text: NSLocalizedString("setsInfo", comment: "")
                )
                .padding(.horizontal)
            }
            .padding(.top)
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
        }
        .isBlockedWithoutPro()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack {
                    Text("\(NSLocalizedString("sets", comment: ""))")
                        .font(.headline)
                    Text(exercise.displayName)
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        MetricComparisonView(
            leading: .init(
                label: NSLocalizedString("average", comment: ""),
                value: averageSetCount.map { "\($0)" } ?? "––",
                unit: "",
                caption: period.rangeCaption(period.completedHistoryRange())
            ),
            trailing: .init(
                label: period.currentPeriodLabel,
                // A period count is a real value even at zero ("0 this week"), clearer than a
                // "––" no-data dash — same rule as the stat tiles.
                value: "\(currentCount)",
                unit: "",
                caption: period.rangeCaption(period.currentRange())
            ),
            trailingValueStyle: AnyShapeStyle(muscleGroupColor.gradient),
            percentChange: percentChange,
            positiveColor: muscleGroupColor,
            explanation: NSLocalizedString("averageComparisonInfo", comment: "")
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Chart

    private var chart: some View {
        PeriodHistoryChart(
            buckets: buckets,
            period: period,
            valueLabel: NSLocalizedString("sets", comment: ""),
            currentBarStyle: AnyShapeStyle(muscleGroupColor.gradient),
            averageLine: averageSetCount.map(Double.init)
        )
    }

    // MARK: - Data

    private var currentCount: Int { setCount(in: period.currentRange()) }

    /// Working-set counts of the completed periods on screen — every history bucket except the
    /// current, still-growing one, and only periods actually trained (a rest period is "no data"
    /// for the average, the same rule the trend already uses). The comparison baseline and the
    /// dashed average line both read from this one value.
    private var completedSetCounts: [Int] {
        (1 ..< period.historyBucketCount)
            .map { setCount(in: period.range(periodsAgo: $0)) }
            .filter { $0 > 0 }
    }

    private var averageSetCount: Int? {
        guard !completedSetCounts.isEmpty else { return nil }
        return Int((Double(completedSetCounts.reduce(0, +)) / Double(completedSetCounts.count)).rounded())
    }

    /// The current period against the average of the completed periods shown — nil (pill hidden)
    /// until both the current period and the history hold data, the same suppression as the tiles.
    private var percentChange: Double? {
        PeriodHistoryChart.trendPercentChange(current: currentCount, previous: averageSetCount ?? 0)
    }

    /// Working-set count in the range — only sets with a recorded entry, matching the weekly tile.
    private func setCount(in range: ClosedRange<Date>) -> Int {
        workoutSets
            .filter {
                guard let date = $0.workout?.date else { return false }
                return range.contains(date)
            }
            .filter(\.hasEntry)
            .count
    }

    private var buckets: [PeriodHistoryChart.Bucket] {
        PeriodHistoryChart.buckets(for: period) { Double(setCount(in: $0)) }
    }

    private var muscleGroupColor: Color {
        exercise.muscleGroup?.color ?? .accentColor
    }
}

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database

    var body: some View {
        let exercise = database.getExercises().first!
        NavigationView {
            ExerciseSetsScreen(exercise: exercise, workoutSets: exercise.sets)
        }
    }
}

struct ExerciseSetsScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
    }
}
