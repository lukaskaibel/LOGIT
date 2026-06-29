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
                Text(periodLabel)
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
        return Chart {
            ForEach(buckets) { bucket in
                BarMark(
                    x: .value("Period", bucket.date, unit: barUnit),
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
            AxisMarks(values: .stride(by: strideComponent)) { value in
                if let date = value.as(Date.self) {
                    AxisGridLine()
                        .foregroundStyle(Color.gray.opacity(0.4))
                    AxisValueLabel(axisLabel(for: date))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
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
        let count = chartBucketCount
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

    private var chartBucketCount: Int {
        switch period {
        case .week: return 8
        case .month: return 12
        case .year: return 6
        }
    }

    // MARK: - Formatting

    private var periodLabel: String {
        switch period {
        case .week: return NSLocalizedString("thisWeek", comment: "")
        case .month: return NSLocalizedString("thisMonth", comment: "")
        case .year: return NSLocalizedString("thisYear", comment: "")
        }
    }

    private var barUnit: Calendar.Component {
        switch period {
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        }
    }

    private var strideComponent: Calendar.Component {
        switch period {
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        }
    }

    private func axisLabel(for date: Date) -> String {
        switch period {
        case .week: return date.formatted(.dateTime.day().month(.abbreviated))
        case .month: return date.formatted(.dateTime.month(.narrow))
        case .year: return date.formatted(.dateTime.year())
        }
    }
}
