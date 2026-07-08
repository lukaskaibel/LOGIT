//
//  ExerciseVolumeScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 03.12.24.
//

import SwiftUI

/// Training volume per period for a single exercise — the detail screen behind the weekly Volume
/// tile. Volume is an *effort* metric (did I do the work?), so the screen is scoped by the shared
/// `PeriodPicker` exactly like the Summary stat screens: the current calendar week / month / year,
/// a trend against the previous period, and the recent periods as history bars. Structurally the
/// twin of `ExerciseSetsScreen`, which counts working sets instead of summing tonnage.
struct ExerciseVolumeScreen: View {
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
                    metricTitle: NSLocalizedString("volume", comment: ""),
                    text: NSLocalizedString("volumeInfo", comment: "")
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
                    Text("\(NSLocalizedString("volume", comment: ""))")
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
                value: averageDisplayVolume.map { "\($0)" } ?? "––",
                unit: WeightUnit.used.rawValue,
                caption: period.rangeCaption(period.completedHistoryRange())
            ),
            trailing: .init(
                label: period.currentPeriodLabel,
                // A period sum is a real value even at zero ("0 kg this week"), clearer than a
                // "––" no-data dash — same rule as the stat tiles.
                value: formatWeightForDisplay(currentRawVolume),
                unit: WeightUnit.used.rawValue,
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
            valueLabel: NSLocalizedString("volume", comment: ""),
            currentBarStyle: AnyShapeStyle(muscleGroupColor.gradient),
            unit: WeightUnit.used.rawValue,
            averageLine: averageDisplayVolume.map { Double($0) }
        )
    }

    // MARK: - Data

    private var currentRawVolume: Int { rawVolume(in: period.currentRange()) }

    /// Raw volumes of the completed periods on screen — every history bucket except the current,
    /// still-growing one, and only periods actually trained (a rest period is "no data" for the
    /// average, the same rule the trend already uses). The comparison baseline and the dashed
    /// average line both read from this, so "average" means the same in the header and on the chart.
    private var completedRawVolumes: [Int] {
        (1 ..< period.historyBucketCount)
            .map { rawVolume(in: period.range(periodsAgo: $0)) }
            .filter { $0 > 0 }
    }

    private var averageRawVolume: Int? {
        guard !completedRawVolumes.isEmpty else { return nil }
        return completedRawVolumes.reduce(0, +) / completedRawVolumes.count
    }

    /// The average as a whole display-unit value. Volumes run to thousands, so the mean's fractional
    /// tail (`formatWeightForDisplay` keeps up to 3 decimals) only wraps the large header number onto
    /// a second line — round it. Feeds the header and the chart's dashed line so the two stay in step;
    /// the pill reads `averageRawVolume`, where the ratio is exact.
    private var averageDisplayVolume: Int? {
        averageRawVolume.map { Int(convertWeightForDisplayingDecimal($0).rounded()) }
    }

    /// The current period against the average of the completed periods shown — nil (pill hidden)
    /// until both the current period and the history hold data, the same suppression as the tiles.
    private var percentChange: Double? {
        PeriodHistoryChart.trendPercentChange(current: currentRawVolume, previous: averageRawVolume ?? 0)
    }

    /// Total volume (weight × reps over every set) in the range, in raw storage units.
    private func rawVolume(in range: ClosedRange<Date>) -> Int {
        let sets = workoutSets.filter {
            guard let date = $0.workout?.date else { return false }
            return range.contains(date)
        }
        return getVolume(of: sets, for: exercise)
    }

    private var buckets: [PeriodHistoryChart.Bucket] {
        PeriodHistoryChart.buckets(
            for: period,
            value: { convertWeightForDisplayingDecimal(rawVolume(in: $0)) },
            formatted: { formatWeightForDisplay(rawVolume(in: $0)) }
        )
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
            ExerciseVolumeScreen(exercise: exercise, workoutSets: exercise.sets)
        }
    }
}

struct ExerciseVolumeScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
    }
}
