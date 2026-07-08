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
                    PeriodStatChartView(
                        period: period,
                        buckets: buckets,
                        firstDataDate: firstDataDate,
                        valueLabel: NSLocalizedString("volume", comment: ""),
                        unit: WeightUnit.used.rawValue,
                        currentBarStyle: AnyShapeStyle(muscleGroupColor.gradient),
                        currentLabel: period.currentPeriodLabel,
                        currentValue: formatWeightForDisplay(currentRawVolume),
                        currentRaw: currentRawVolume,
                        trailingValueStyle: AnyShapeStyle(muscleGroupColor.gradient),
                        positiveColor: muscleGroupColor,
                        // Volumes run to thousands, so round the mean to a whole unit — the raw
                        // decimals only wrap the large header number onto a second line.
                        formatAverage: { "\(Int(convertWeightForDisplayingDecimal($0).rounded()))" },
                        displayAverage: { Double(Int(convertWeightForDisplayingDecimal($0).rounded())) },
                        explanation: NSLocalizedString("averageComparisonInfo", comment: "")
                    )
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

    // MARK: - Data

    private var currentRawVolume: Int { rawVolume(in: period.currentRange()) }

    /// Earliest recorded set — the left end of the scrollable domain.
    private var firstDataDate: Date? {
        workoutSets.compactMap { $0.workout?.date }.min()
    }

    /// Raw volume per period start, built in one pass over the sets so the scrollable chart can look
    /// each period up instead of re-filtering the sets per bar. Keyed the same way `scrollableBuckets`
    /// keys its lookups — `currentRange(containing:).lowerBound`.
    private var rawByPeriodStart: [Date: Int] {
        var dict: [Date: Int] = [:]
        for set in workoutSets {
            guard let date = set.workout?.date else { continue }
            let start = period.currentRange(containing: date).lowerBound
            dict[start, default: 0] += getVolume(of: [set], for: exercise)
        }
        return dict
    }

    private var buckets: [PeriodHistoryChart.Bucket] {
        PeriodHistoryChart.scrollableBuckets(
            for: period,
            rawByPeriodStart: rawByPeriodStart,
            firstDataDate: firstDataDate,
            display: { convertWeightForDisplayingDecimal($0) },
            formatted: { formatWeightForDisplay($0) }
        )
    }

    /// Total volume (weight × reps over every set) in the range, in raw storage units.
    private func rawVolume(in range: ClosedRange<Date>) -> Int {
        let sets = workoutSets.filter {
            guard let date = $0.workout?.date else { return false }
            return range.contains(date)
        }
        return getVolume(of: sets, for: exercise)
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
