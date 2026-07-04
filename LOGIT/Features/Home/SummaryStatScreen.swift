//
//  SummaryStatScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import Charts
import SwiftUI

/// Detail screen behind a Summary core-stat tile: the stat summed per period across recent history,
/// scoped by the shared `PeriodPicker`. The tile shows the current period; the screen zooms out to the
/// last several periods, the current one highlighted. One screen serves all four stats —
/// `WorkoutStatMetric` supplies values, formatting, and the about text. Pro, like the other stat
/// detail screens (the tile is the free hook).
struct SummaryStatScreen: View {
    let metric: WorkoutStatMetric
    let workouts: [Workout]

    @State private var period: StatPeriod

    init(metric: WorkoutStatMetric, workouts: [Workout], initialPeriod: StatPeriod = .week) {
        self.metric = metric
        self.workouts = workouts
        _period = State(initialValue: initialPeriod)
    }

    private var isDuration: Bool { metric == .duration }

    var body: some View {
        ScrollView {
            VStack(spacing: SECTION_SPACING) {
                VStack(spacing: 16) {
                    PeriodPicker(selection: $period)
                    header
                    chart
                }
                .padding(.horizontal)
                AboutSection(metricTitle: metric.title, text: metric.aboutText)
                    .padding(.horizontal)
            }
            .padding(.top)
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
        }
        .isBlockedWithoutPro()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(metric.title)
                    .font(.headline)
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
                    value: currentRaw > 0 ? metric.formattedValue(fromRaw: currentRaw) : "––",
                    unit: metric.unit,
                    configuration: .large,
                    unitColor: .secondaryLabel
                )
                .foregroundStyle(isDuration ? AnyShapeStyle(Color.label) : AnyShapeStyle(Color.accentColor.gradient))
            }
            Spacer()
            if let percentChange {
                TrendIndicatorView(
                    percentChange: percentChange,
                    positiveColor: isDuration ? .secondary : .accentColor
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
        let value: Double
        let isCurrent: Bool
    }

    private var chart: some View {
        let buckets = self.buckets
        let maxValue = buckets.map(\.value).max() ?? 0
        // At most ~4 axis labels, counted back from the current bucket so "now" is always labeled —
        // one label per bucket sat shoulder-to-shoulder on the week view.
        let labelStride = max(1, Int((Double(buckets.count) / 4.0).rounded(.up)))
        let labeledDates = stride(from: buckets.count - 1, through: 0, by: -labelStride).map { buckets[$0].date }
        return Chart {
            ForEach(buckets) { bucket in
                BarMark(
                    x: .value("Period", bucket.date, unit: period.calendarComponent),
                    y: .value(metric.title, bucket.value),
                    width: .ratio(0.6)
                )
                .foregroundStyle(
                    bucket.isCurrent
                        ? (isDuration ? Color.secondary : Color.accentColor)
                        : Color.fill
                )
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
                    // Styling lives on the Text inside the label closure — hierarchical styles on the
                    // AxisMark itself resolve against the chart's accent on iOS 26 (labels turned lime).
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

    private var currentRaw: Int { sum(in: period.currentRange()) }
    private var previousRaw: Int { sum(in: period.previousRange()) }

    private var percentChange: Double? {
        previousRaw > 0 ? (Double(currentRaw) - Double(previousRaw)) / Double(previousRaw) * 100 : nil
    }

    private func sum(in range: ClosedRange<Date>) -> Int {
        workouts
            .filter { ($0.date).map { range.contains($0) } ?? false }
            .reduce(0) { $0 + metric.rawValue(of: $1) }
    }

    private var buckets: [Bucket] {
        let count = period.historyBucketCount
        return (0 ..< count).map { index in
            let periodsAgo = count - 1 - index
            let range = period.range(periodsAgo: periodsAgo)
            let raw = sum(in: range)
            return Bucket(
                id: index,
                date: range.lowerBound,
                value: metric.displayValue(fromRaw: raw),
                isCurrent: periodsAgo == 0
            )
        }
    }
}
