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
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(period.currentPeriodLabel)
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                // A period sum is a real value even at zero ("0 kg this week"), clearer than a
                // "––" no-data dash — same rule as the stat tiles.
                UnitView(
                    value: formatWeightForDisplay(currentRawVolume),
                    unit: WeightUnit.used.rawValue,
                    configuration: .large,
                    unitColor: .secondaryLabel
                )
                .foregroundStyle(muscleGroupColor.gradient)
            }
            Spacer()
            if let percentChange {
                TrendIndicatorView(
                    percentChange: percentChange,
                    positiveColor: muscleGroupColor
                )
                .animation(.snappy, value: percentChange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Chart

    private var chart: some View {
        PeriodHistoryChart(
            buckets: buckets,
            period: period,
            valueLabel: NSLocalizedString("volume", comment: ""),
            currentBarStyle: AnyShapeStyle(muscleGroupColor.gradient),
            unit: WeightUnit.used.rawValue
        )
    }

    // MARK: - Data

    private var currentRawVolume: Int { rawVolume(in: period.currentRange()) }
    private var previousRawVolume: Int { rawVolume(in: period.previousRange()) }

    private var percentChange: Double? {
        PeriodHistoryChart.trendPercentChange(current: currentRawVolume, previous: previousRawVolume)
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
