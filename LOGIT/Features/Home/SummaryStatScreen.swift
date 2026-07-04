//
//  SummaryStatScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import Charts
import SwiftUI

/// Detail screen behind a Summary core-stat tile: the stat summed per period across history,
/// scoped by the shared `PeriodPicker`. The tile shows the current period; the screen zooms out to a
/// scrollable chart of all periods — 8 weeks / 12 months / 6 years on screen, pannable back to the
/// first workout, the current period highlighted and any bar tappable to inspect its value. One
/// screen serves all four stats — `WorkoutStatMetric` supplies values, formatting, and the about
/// text. Pro, like the other stat detail screens (the tile is the free hook).
struct SummaryStatScreen: View {
    let metric: WorkoutStatMetric
    let workouts: [Workout]

    @State private var period: StatPeriod
    @State private var chartScrollPosition: Date = .now
    @State private var selectedDate: Date?

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
        .onAppear {
            initializeChartScrollPosition()
        }
        .onChange(of: period) {
            // A new period means a new bucket grid — drop the selection and re-anchor the window
            // so the current period sits on the right edge again.
            selectedDate = nil
            initializeChartScrollPosition()
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
        let date: Date
        let rawValue: Int
        let value: Double
        let isCurrent: Bool
        var id: Date { date }
    }

    private var chart: some View {
        let buckets = self.buckets
        let points = buckets.map { (date: $0.date, value: $0.value) }
        let yScaleCap = chartYScaleCap(
            visibleMax: chartVisibleMax(
                of: points,
                from: chartScrollPosition,
                to: visibleEndDate,
                bucketLength: bucketLengthInSeconds
            ),
            fallbackMax: points.map(\.value).max()
        )
        return Chart {
            ForEach(buckets) { bucket in
                BarMark(
                    x: .value("Period", bucket.date, unit: barUnit),
                    y: .value(metric.title, bucket.value),
                    width: .ratio(0.6)
                )
                .foregroundStyle(barStyle(for: bucket))
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .opacity(selectedDate == nil || isSelected(bucket) ? 1.0 : 0.4)
            }
            if let selectedDate {
                let snapped = periodStart(of: selectedDate)
                RuleMark(x: .value("Selected", snapped, unit: barUnit))
                    .foregroundStyle(Color.label.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .annotation(
                        position: .top,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        annotationCard(for: snapped)
                    }
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: 0 ... yScaleCap)
        .chartScrollableAxes(.horizontal)
        .chartScrollPosition(x: $chartScrollPosition)
        .chartScrollTargetBehavior(.valueAligned(matching: scrollAlignment))
        .chartXSelection(value: $selectedDate)
        .chartXVisibleDomain(length: visibleChartDomainInSeconds)
        // Rebuild the chart when the period flips: reusing the chart across visible-domain
        // changes leaves its scroll offset stale (the viewport shows a window months away from
        // chartScrollPosition), so give each period its own chart identity.
        .id(period)
        .chartXAxis {
            AxisMarks(
                position: .bottom,
                values: .stride(by: strideComponent, count: axisStrideCount)
            ) { value in
                if let date = value.as(Date.self) {
                    let isCurrent = period.currentRange().contains(date)
                    AxisGridLine()
                        .foregroundStyle(Color.gray.opacity(0.4))
                    // Styling lives on the Text inside the label closure — hierarchical styles on the
                    // AxisMark itself resolve against the chart's accent on iOS 26 (labels turned lime).
                    // Centered puts the label under the period's bar, keeping the newest label clear
                    // of the plot's right edge (it clipped to "29…" when anchored on the gridline).
                    AxisValueLabel(centered: true) {
                        Text(axisLabel(for: date))
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

    /// The current period keeps the accent (grey for duration, matching its tile); a tapped past
    /// bar lights up white; every other bar stays a quiet gray.
    private func barStyle(for bucket: Bucket) -> Color {
        if bucket.isCurrent { return isDuration ? Color.secondary : Color.accentColor }
        if isSelected(bucket) { return Color.label }
        return Color.fill
    }

    private func annotationCard(for periodStartDate: Date) -> some View {
        let raw = buckets.first { $0.date == periodStartDate }?.rawValue ?? 0
        return VStack(alignment: .leading) {
            UnitView(
                value: raw > 0 ? metric.formattedValue(fromRaw: raw) : "––",
                unit: metric.unit,
                unitColor: .secondaryLabel
            )
            .foregroundStyle(Color.label)
            Text(annotationLabel(for: periodStartDate))
                .fontWeight(.bold)
                .fontDesign(.rounded)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondaryBackground))
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

    /// One bar per trained period, plus the current one so the accent bar always exists. Sparse —
    /// the chart's scrollable domain (not this list) decides how far back the user can pan.
    private var buckets: [Bucket] {
        let currentStart = periodStart(of: .now)
        var sums: [Date: Int] = [:]
        for workout in workouts {
            guard let date = workout.date else { continue }
            sums[periodStart(of: date), default: 0] += metric.rawValue(of: workout)
        }
        sums[currentStart] = sums[currentStart] ?? 0
        return sums
            .map { start, raw in
                Bucket(
                    date: start,
                    rawValue: raw,
                    value: metric.displayValue(fromRaw: raw),
                    isCurrent: start == currentStart
                )
            }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Chart Window

    /// 8 weeks / 12 months / 6 years on screen at a time.
    private var visibleChartDomainInSeconds: Int {
        switch period {
        case .week: return 3600 * 24 * 7 * 8
        case .month: return 3600 * 24 * 365
        case .year: return 3600 * 24 * 365 * 6
        }
    }

    private var visibleEndDate: Date {
        Calendar.current.date(byAdding: .second, value: visibleChartDomainInSeconds, to: chartScrollPosition)!
    }

    /// How long one bar's bucket spans on the x-axis.
    private var bucketLengthInSeconds: TimeInterval {
        switch period {
        case .week: return 3600 * 24 * 7
        case .month: return 3600 * 24 * 31
        case .year: return 3600 * 24 * 366
        }
    }

    /// From the first trained period (or one full window back, whichever is earlier) to the end of
    /// the current period.
    private var xDomain: ClosedRange<Date> {
        let endDate = period.currentRange().upperBound
        let minStartDate = Calendar.current.date(byAdding: .second, value: -visibleChartDomainInSeconds, to: endDate)!
        guard let earliest = workouts.compactMap(\.date).min().map({ periodStart(of: $0) }), earliest < minStartDate
        else { return minStartDate ... endDate }
        return earliest ... endDate
    }

    private var scrollAlignment: DateComponents {
        switch period {
        case .week: return DateComponents(weekday: Calendar.current.firstWeekday)
        case .month: return DateComponents(day: 1)
        case .year: return DateComponents(month: 1, day: 1)
        }
    }

    private func initializeChartScrollPosition() {
        chartScrollPosition = Calendar.current.date(
            byAdding: .second,
            value: -visibleChartDomainInSeconds,
            to: period.currentRange().upperBound
        )!
    }

    // MARK: - Selection

    private func periodStart(of date: Date) -> Date {
        switch period {
        case .week: return date.startOfWeek
        case .month: return date.startOfMonth
        case .year: return date.startOfYear
        }
    }

    private func isSelected(_ bucket: Bucket) -> Bool {
        guard let selectedDate else { return false }
        return periodStart(of: selectedDate) == bucket.date
    }

    private func annotationLabel(for start: Date) -> String {
        switch period {
        case .week:
            return "\(start.formatted(.dateTime.day().month())) - \(start.endOfWeek.formatted(.dateTime.day().month()))"
        case .month:
            return start.formatted(.dateTime.month(.abbreviated).year())
        case .year:
            return start.formatted(.dateTime.year())
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

    /// Label every other week (the 8-week view would crowd otherwise), every month, every year.
    private var axisStrideCount: Int {
        period == .week ? 2 : 1
    }

    private func axisLabel(for date: Date) -> String {
        switch period {
        case .week: return date.formatted(.dateTime.day().month(.defaultDigits))
        case .month: return date.formatted(.dateTime.month(.narrow))
        case .year: return date.formatted(.dateTime.year())
        }
    }
}
