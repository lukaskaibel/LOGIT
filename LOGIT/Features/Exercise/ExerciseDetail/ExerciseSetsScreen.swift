//
//  ExerciseSetsScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 22.06.26.
//

import Charts
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
                UnitView(
                    value: currentCount > 0 ? "\(currentCount)" : "––",
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

    private struct Bucket: Identifiable {
        let id: Int
        let date: Date
        let value: Int
        let isCurrent: Bool
    }

    private var chart: some View {
        let buckets = self.buckets
        let maxValue = buckets.map(\.value).max() ?? 0
        // At most ~4 axis labels, counted back from the current bucket so "now" is always labeled.
        let labelStride = max(1, Int((Double(buckets.count) / 4.0).rounded(.up)))
        let labeledDates = stride(from: buckets.count - 1, through: 0, by: -labelStride).map { buckets[$0].date }
        return Chart {
            ForEach(buckets) { bucket in
                BarMark(
                    x: .value("Period", bucket.date, unit: period.calendarComponent),
                    y: .value(NSLocalizedString("sets", comment: ""), bucket.value),
                    width: .ratio(0.6)
                )
                .foregroundStyle(bucket.isCurrent ? AnyShapeStyle(muscleGroupColor.gradient) : AnyShapeStyle(Color.fill))
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            }
        }
        .chartYScale(domain: 0 ... max(maxValue, 1))
        .chartXAxis {
            AxisMarks(values: labeledDates) { value in
                if let date = value.as(Date.self) {
                    let isCurrent = period.currentRange().contains(date)
                    AxisGridLine()
                        .foregroundStyle(Color.gray.opacity(0.4))
                    AxisValueLabel {
                        Text(period.axisLabel(for: date))
                            .font(.caption.weight(isCurrent ? .bold : .semibold))
                            .foregroundStyle(isCurrent ? Color.label : Color.secondaryLabel)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3))
        }
        .frame(height: 260)
    }

    // MARK: - Data

    private var currentCount: Int { setCount(in: period.currentRange()) }
    private var previousCount: Int { setCount(in: period.previousRange()) }

    private var percentChange: Double? {
        previousCount > 0 ? (Double(currentCount) - Double(previousCount)) / Double(previousCount) * 100 : nil
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

    private var buckets: [Bucket] {
        let count = period.historyBucketCount
        return (0 ..< count).map { index in
            let periodsAgo = count - 1 - index
            let range = period.range(periodsAgo: periodsAgo)
            return Bucket(
                id: index,
                date: range.lowerBound,
                value: setCount(in: range),
                isCurrent: periodsAgo == 0
            )
        }
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
