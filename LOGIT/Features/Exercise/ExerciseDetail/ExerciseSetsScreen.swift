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
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(period.currentPeriodLabel)
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                // A period count is a real value even at zero ("0 this week"), clearer than a
                // "––" no-data dash — same rule as the stat tiles.
                UnitView(
                    value: "\(currentCount)",
                    unit: "",
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
            valueLabel: NSLocalizedString("sets", comment: ""),
            currentBarStyle: AnyShapeStyle(muscleGroupColor.gradient)
        )
    }

    // MARK: - Data

    private var currentCount: Int { setCount(in: period.currentRange()) }
    private var previousCount: Int { setCount(in: period.previousRange()) }

    private var percentChange: Double? {
        PeriodHistoryChart.trendPercentChange(current: currentCount, previous: previousCount)
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
