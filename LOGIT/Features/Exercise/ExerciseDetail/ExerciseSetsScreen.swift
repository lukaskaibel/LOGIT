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
                    PeriodStatChartView(
                        period: period,
                        buckets: buckets,
                        firstDataDate: firstDataDate,
                        valueLabel: NSLocalizedString("sets", comment: ""),
                        unit: "",
                        currentBarStyle: AnyShapeStyle(muscleGroupColor.gradient),
                        currentLabel: period.currentPeriodLabel,
                        currentValue: "\(currentCount)",
                        currentRaw: currentCount,
                        trailingValueStyle: AnyShapeStyle(muscleGroupColor.gradient),
                        positiveColor: muscleGroupColor,
                        formatAverage: { "\($0)" },
                        displayAverage: { Double($0) },
                        explanation: NSLocalizedString("averageComparisonInfo", comment: "")
                    )
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

    // MARK: - Data

    private var currentCount: Int { setCount(in: period.currentRange()) }

    /// Earliest recorded set — the left end of the scrollable domain.
    private var firstDataDate: Date? {
        workoutSets.compactMap { $0.workout?.date }.min()
    }

    /// Working-set count per period start, built in one pass so the scrollable chart looks each period
    /// up instead of re-filtering the sets per bar. Only sets with a recorded entry count, matching
    /// the weekly tile; keyed the same way `scrollableBuckets` keys its lookups.
    private var countByPeriodStart: [Date: Int] {
        var dict: [Date: Int] = [:]
        for set in workoutSets where set.hasEntry {
            guard let date = set.workout?.date else { continue }
            let start = period.currentRange(containing: date).lowerBound
            dict[start, default: 0] += 1
        }
        return dict
    }

    private var buckets: [PeriodHistoryChart.Bucket] {
        PeriodHistoryChart.scrollableBuckets(
            for: period,
            rawByPeriodStart: countByPeriodStart,
            firstDataDate: firstDataDate,
            display: { Double($0) },
            formatted: { "\($0)" }
        )
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
