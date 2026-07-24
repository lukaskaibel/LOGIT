//
//  CapabilityChartView.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 15.07.26.
//

import Charts
import SwiftUI

/// The shared scrollable line chart behind every exercise *capability* detail screen — Weight, e1RM,
/// Set Volume and Repetitions. Capability metrics track what the body can do *right now*, so the chart
/// scrolls a rolling `ChartRange` window ("3M" / "1Y" / "All") through the whole history, with a
/// scoreboard header comparing the current best against the best in the visible window.
///
/// It owns the scroll position, the selection and the range picker — deliberately, exactly like
/// `PeriodStatChartView` does for the effort stats. Scrolling and inspecting drive `chartScrollPosition`
/// / `selectedDate` on *this* view, so only this small view re-renders per frame; the screen that
/// builds the data never does. And the data it re-renders is already reduced to plain value types —
/// `Point`s carry a precomputed display value, a raw metric and a formatted string, so a scroll frame
/// touches no Core Data, does no unit conversion and runs no per-set metric math. That is the whole
/// fix for the "basically unusable" selection/scroll lag: the earlier inline charts rebuilt every
/// mark from `WorkoutSet`s and re-scanned the full set list for the header on every frame.
struct CapabilityChartView: View {
    /// One plotted day — the day's best set, reduced to plain values up front so a render frame reads
    /// numbers instead of faulting `WorkoutSet`s. There is exactly one `Point` per calendar day (the
    /// daily max), which is why the selection dimming can compare by `id` instead of by calendar day.
    struct Point: Identifiable {
        let id: Int
        /// The real timestamp of the day's best set — positioned to its day by the marks' `unit: .day`,
        /// and compared against the visible window (which is expressed in real dates) for selection.
        let date: Date
        /// The value plotted on the y-axis, already in display units (kg / lbs / reps).
        let value: Double
        /// The metric in raw storage units (grams, or a bare rep count) — what the visible-window
        /// baseline maxes over and the header trend is a percentage of, matching `bestAnchor.value`.
        let raw: Int
        /// The value spelled out for the selection tooltip, in the screen's own units ("142.5", "12").
        let formatted: String
    }

    /// The whole history, one `Point` per day, oldest first — built once by the screen.
    let points: [Point]
    /// Earliest data date — the left end of the scrollable domain and the `All` range. Passed in so it
    /// isn't re-derived from the data on every scroll/selection frame.
    let firstDataDate: Date?
    /// The fixed right-hand anchor of the header scoreboard, independent of scroll: the current best
    /// (highest in the last four weeks) or, when that window is empty, the "last best". Computed once
    /// by the screen — reading it here is a struct field, not the full-set rescan it used to be.
    let bestAnchor: (value: Int, date: Date?, isLapsed: Bool)?
    /// The y-axis cap in display units — each screen picks it by its own rule (a fixed ladder for
    /// weight / e1RM / reps, a rounded magnitude for set volume).
    let yScaleMax: Int
    let color: Color
    /// Unit shown after the header and tooltip values ("kg", "reps").
    let unit: String
    /// Accessibility series name for the y-values (not rendered).
    let valueLabel: String
    /// Formats a raw metric (the header baseline and the anchor) into the screen's units — the same
    /// formatter the `Point.formatted` strings were built with.
    let formatValue: (Int) -> String

    @State private var chartRange: ChartRange = .threeMonths
    @State private var chartScrollPosition: Date = .now
    @State private var selectedDate: Date?

    var body: some View {
        // Per-frame work, now all O(points) integer/date math over the precomputed values — no Core
        // Data, no unit conversion, no full-set rescan.
        let snappedSelectedPoint = selectedDate.flatMap { nearestPoint(to: $0) }
        let baselineRaw = otherBestBaseline(currentBestDay: bestAnchor?.date)
        VStack {
            RangePicker(selection: $chartRange)
                .padding(.vertical)
                .padding(.horizontal)
            MetricComparisonView(
                leading: .init(
                    label: NSLocalizedString("previousBest", comment: ""),
                    value: baselineRaw.map(formatValue) ?? "––",
                    unit: unit,
                    caption: chartRange.visibleWindowDescription(from: chartScrollPosition, firstDataDate: firstDataDate)
                ),
                trailing: .init(
                    label: NSLocalizedString(bestAnchor?.isLapsed == true ? "lastBest" : "currentBest", comment: ""),
                    value: bestAnchor.map { formatValue($0.value) } ?? "––",
                    unit: unit,
                    caption: bestAnchor?.date.map { $0.formatted(.dateTime.day().month()) }
                ),
                trailingValueStyle: AnyShapeStyle(color.gradient),
                percentChange: bestAnchor?.isLapsed == true ? nil : headerTrendPercentage(visibleBest: baselineRaw),
                positiveColor: color,
                explanation: NSLocalizedString("currentBestComparisonInfo", comment: "")
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            Chart {
                // The selection: a rule mark and a value card, snapped to the nearest datapoint, shown
                // only while a selection exists.
                if selectedDate != nil, let selectedPoint = snappedSelectedPoint {
                    let snapped = Calendar.current.startOfDay(for: selectedPoint.date)
                    RuleMark(x: .value("Selected", snapped, unit: .day))
                        .foregroundStyle(color.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            VStack(alignment: .leading) {
                                UnitView(value: selectedPoint.formatted, unit: unit)
                                    .foregroundStyle(color.gradient)
                                Text(snapped.formatted(.dateTime.day().month()))
                                    .fontWeight(.bold)
                                    .fontDesign(.rounded)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondaryBackground))
                        }
                }
                // A flat lead-in from the far past to the first datapoint, so a young history still
                // reads as a line rather than a lone dot at the right edge.
                if let firstPoint = points.first {
                    LineMark(
                        x: .value("Date", Date.distantPast, unit: .day),
                        y: .value(valueLabel, firstPoint.value)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(color.gradient)
                    .lineStyle(StrokeStyle(lineWidth: 5))
                    .opacity(snappedSelectedPoint == nil ? 1.0 : 0.3)
                    AreaMark(
                        x: .value("Date", Date.distantPast, unit: .day),
                        y: .value(valueLabel, firstPoint.value)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Gradient(colors: [
                        color.opacity(0.5),
                        color.opacity(0.2),
                        color.opacity(0.05),
                    ]))
                    .opacity(snappedSelectedPoint == nil ? 1.0 : 0.3)
                }
                ForEach(points) { point in
                    let isSelected = snappedSelectedPoint?.id == point.id
                    let lineOpacity = snappedSelectedPoint == nil || isSelected ? 1.0 : 0.3
                    LineMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value(valueLabel, point.value)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(color.gradient)
                    .lineStyle(StrokeStyle(lineWidth: 5))
                    .opacity(lineOpacity)
                    .symbol {
                        Circle()
                            .frame(width: 10, height: 10)
                            .foregroundStyle(color.gradient.opacity(lineOpacity))
                            .overlay {
                                Circle()
                                    .frame(width: 4, height: 4)
                                    .foregroundStyle(Color.black)
                            }
                            .background(Circle().fill(Color.black))
                    }
                    AreaMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value(valueLabel, point.value)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Gradient(colors: [
                        color.opacity(0.5),
                        color.opacity(0.2),
                        color.opacity(0.05),
                    ]))
                    .opacity(selectedDate == nil ? 1.0 : 0.0)
                }
                // A dashed carry-forward from the last datapoint to today, so a lapsed metric doesn't
                // just stop mid-chart. Hidden while inspecting.
                if selectedDate == nil, let lastPoint = points.last, !Calendar.current.isDateInToday(lastPoint.date) {
                    RuleMark(
                        xStart: .value("Start", lastPoint.date),
                        xEnd: .value("End", Date()),
                        y: .value(valueLabel, lastPoint.value)
                    )
                    .foregroundStyle(color.opacity(0.45))
                    .lineStyle(
                        StrokeStyle(
                            lineWidth: 5,
                            lineCap: .round,
                            dash: [5, 10]
                        )
                    )
                }
            }
            .chartXScale(domain: chartRange.xDomain(firstDataDate: firstDataDate))
            .chartYScale(domain: 0 ... yScaleMax)
            .chartScrollableAxes(.horizontal)
            .chartScrollPosition(x: $chartScrollPosition)
            .chartScrollTargetBehavior(
                .valueAligned(matching: chartRange.scrollSnapComponents)
            )
            .chartXSelection(value: $selectedDate)
            .chartXVisibleDomain(length: chartRange.visibleDomainSeconds(firstDataDate: firstDataDate))
            .chartXAxis {
                chartRange.xAxisMarks(firstDataDate: firstDataDate)
            }
            .chartYAxis {
                AxisMarks(values: [0, yScaleMax / 2, yScaleMax])
            }
            .emptyPlaceholder(points) {
                Text(NSLocalizedString("noData", comment: ""))
            }
            .frame(height: 300)
            .padding(.leading)
            .padding(.trailing, 5)
        }
        .onAppear {
            chartScrollPosition = chartRange.initialScrollPosition(firstDataDate: firstDataDate)
        }
        .onChange(of: chartRange) {
            // Re-initialize scroll position when switching ranges to avoid desync with visible window.
            chartScrollPosition = chartRange.initialScrollPosition(firstDataDate: firstDataDate)
        }
    }

    // MARK: - Selection

    private var visibleEndDate: Date {
        Calendar.current.date(
            byAdding: .second,
            value: chartRange.visibleDomainSeconds(firstDataDate: firstDataDate),
            to: chartScrollPosition
        ) ?? chartScrollPosition
    }

    /// The datapoint nearest the raw selection point, preferring the visible window so a tap always
    /// lands on a bar on screen. Mirrors the old `nearestSet`, over precomputed points.
    private func nearestPoint(to date: Date) -> Point? {
        let visible = points.filter { $0.date >= chartScrollPosition && $0.date <= visibleEndDate }
        let candidates = visible.isEmpty ? points : visible
        guard !candidates.isEmpty else { return nil }
        return candidates.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }

    // MARK: - Header

    /// The header's left value and comparison baseline: the best value in the visible window *other
    /// than* the current best (its day excluded), falling back to the most recent day's best before
    /// the window when the window holds no other value. Runs over the precomputed points, so it costs
    /// integer compares per frame, not the full-set rescan the inline charts did.
    private func otherBestBaseline(currentBestDay: Date?) -> Int? {
        let calendar = Calendar.current
        let windowStart = chartScrollPosition
        let windowEnd = visibleEndDate
        let otherInWindow = points.filter { point in
            guard point.date >= windowStart, point.date <= windowEnd else { return false }
            if let currentBestDay, calendar.isDate(point.date, inSameDayAs: currentBestDay) { return false }
            return point.raw > 0
        }
        if let best = otherInWindow.map(\.raw).max(), best > 0 { return best }
        // No other value in the shown window: the most recent day's best before it.
        let prior = points.filter { $0.date < windowStart && $0.raw > 0 }
        guard let lastDate = prior.map(\.date).max() else { return nil }
        return prior
            .filter { calendar.isDate($0.date, inSameDayAs: lastDate) }
            .map(\.raw)
            .max()
    }

    /// The header pill: the current best measured against the best in the shown window. Nil when
    /// either side is empty, so the pill drops out only when there's genuinely nothing to compare.
    private func headerTrendPercentage(visibleBest: Int?) -> Double? {
        guard let current = bestAnchor?.value, current > 0,
              let visible = visibleBest, visible > 0 else { return nil }
        return (Double(current) - Double(visible)) / Double(visible) * 100
    }
}

extension ChartRange {
    /// The one x-axis every `ChartRange` chart shares — this capability chart, the measurement
    /// detail and the workout stat screens — so cadence, styling and edge handling can't drift
    /// apart. Styling lives on the `Text` inside the label closure (hierarchical styles on the
    /// AxisMark resolve against the chart's accent on iOS 26). The weekly day-month labels are the
    /// wide ones that need edge handling: the domain's last mark sits close enough to the right
    /// edge that its centered label truncates ("7/…" for "7/19"), so it hangs trailing instead —
    /// and the mark it hangs toward gives up its own label (keeping the grid line) so the two
    /// can't collide, same as the period-history chart. The narrow month letters and the year
    /// numbers (whose last mark sits months from the edge) stay centered, every label kept.
    func xAxisMarks(firstDataDate: Date?) -> some AxisContent {
        let stride = axisStride(firstDataDate: firstDataDate)
        return AxisMarks(
            position: .bottom,
            values: .stride(by: stride.component, count: stride.count)
        ) { value in
            if let date = value.as(Date.self) {
                AxisGridLine()
                    .foregroundStyle(Color.gray.opacity(0.5))
                let weekly = stride.component == .weekOfYear
                let hugsTrailingEdge = weekly && value.index == value.count - 1
                let yieldsToEdgeLabel = weekly && value.index == value.count - 2
                if !yieldsToEdgeLabel {
                    AxisValueLabel(anchor: hugsTrailingEdge ? .topTrailing : nil) {
                        Text(axisLabel(for: date, firstDataDate: firstDataDate))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(
                                isCurrentAxisMark(date, firstDataDate: firstDataDate)
                                    ? Color.primary
                                    : Color.secondary
                            )
                    }
                }
            }
        }
    }
}
