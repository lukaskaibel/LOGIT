//
//  WorkoutStatScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 12.06.26.
//

import Charts
import SwiftUI

/// Detail screen behind a workout stat tile: the stat across *every* workout over time — the tile
/// zooms into this workout's recent runs, the screen zooms out to the whole landscape. Scoped by the
/// shared `RangePicker` (3M / 1Y / All) like every scrollable capability chart: one bar per workout
/// in the 3M view — this workout's bar in its muscle-group gradient — and monthly averages in the
/// 1Y and All views, where this workout instead gets its own dedicated column at the far right,
/// outside the month grid: the months stay honest averages, never dressed up as this workout, yet
/// its gradient bar always exists to read them against. A tapped bar lights up white, every other
/// stays a quiet gray. The header is a
/// two-value scoreboard like the in-workout metric popover: the average per workout across the
/// *shown* window (the reference — neutral, and it moves as you scroll) on one side, this workout's
/// own value (the bold white constant) on the other, and a pill between them reading this workout
/// against that average. Scroll the chart and the average + pill retarget while this workout stays
/// the anchor — we're in its detail, after all. One screen serves all four stats —
/// `WorkoutStatMetric` supplies values, formatting, and texts.
struct WorkoutStatScreen: View {
    /// A bar of the chart: a single workout in the 3M range, a whole month's average in 1Y / All.
    private struct StatPoint: Identifiable {
        let id: AnyHashable
        let date: Date
        /// Raw units (grams, minutes, counts) — formatted only for display.
        let rawValue: Double
        /// Display units for the chart's y-axis.
        let value: Double
        /// The 3M bar for the workout the screen was opened from — drawn with the workout's
        /// muscle-group gradient; every other bar stays a quiet gray (a tapped bar lights up
        /// white). At month zoom no bar is current — this workout has its own column there.
        let isCurrent: Bool
        /// The single workout behind this bar — nil for a monthly average bar.
        let workout: Workout?
        let workoutCount: Int
    }

    // MARK: - Variables

    let metric: WorkoutStatMetric
    /// The workout the screen was opened from — names the screen and supplies its theme.
    @ObservedObject var workout: Workout

    // MARK: - Environment

    @EnvironmentObject private var muscleGroupService: MuscleGroupService

    // MARK: - State

    @State private var chartRange: ChartRange = .threeMonths
    @State private var chartScrollPosition: Date = .now
    @State private var selectedDate: Date?

    // MARK: - Body

    var body: some View {
        FetchRequestWrapper(
            Workout.self,
            sortDescriptors: [SortDescriptor(\.date)],
            predicate: WorkoutPredicateFactory.getWorkouts()
        ) { allWorkouts in
            // Workouts without a usable value (e.g. no recorded end for the duration screen)
            // would render as invisible bars and drag every average down — they don't count.
            screen(workouts: allWorkouts.filter { $0.date != nil && metric.rawValue(of: $0) > 0 })
        }
    }

    private func screen(workouts: [Workout]) -> some View {
        let firstDataDate = workouts.first?.date
        let visibleEnd = visibleEndDate(firstDataDate: firstDataDate)
        let points = statPoints(in: workouts)
        let snappedPoint = selectedDate != nil ? nearestPoint(to: selectedDate, in: points, visibleEnd: visibleEnd) : nil
        // The average per workout across the visible window — recomputed as the chart scrolls, so the
        // header's reference value and its pill always describe the window currently on screen.
        let visibleAverage = averageRaw(in: workouts, from: chartScrollPosition, to: visibleEnd)
        return ScrollView {
            VStack(spacing: SECTION_SPACING) {
                VStack {
                    RangePicker(selection: $chartRange)
                        .padding(.vertical)
                        .padding(.horizontal)
                    header(visibleAverage: visibleAverage, firstDataDate: firstDataDate)
                    chart(points: points, snappedPoint: snappedPoint, firstDataDate: firstDataDate)
                }

                AboutSection(metricTitle: metric.title, text: metric.aboutText)
                    .padding(.horizontal)
            }
            .padding(.top)
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
        }
        .isBlockedWithoutPro(metric.requiresPro)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack {
                    Text(metric.title)
                        .font(.headline)
                    Text(workout.name ?? "")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            }
        }
        .onAppear {
            chartScrollPosition = initialScrollPosition(firstDataDate: firstDataDate)
        }
        .onChange(of: chartRange) {
            // Re-initialize scroll position when switching ranges to avoid desync with the
            // visible window (same fix as the exercise chart screens).
            chartScrollPosition = initialScrollPosition(firstDataDate: firstDataDate)
        }
    }

    /// The shared initial position, but framing *this workout* instead of today: the window opens
    /// with this workout's bar at its right edge — an off-screen subject reads as a missing one, and
    /// the visible average then compares it against the workouts leading up to it. For recent
    /// workouts this lands exactly on the shared anchor; All shows everything anyway. Clamped to the
    /// domain start so a subject near the first data point doesn't aim past the left edge.
    private func initialScrollPosition(firstDataDate: Date?) -> Date {
        guard chartRange != .allTime, let workoutDate = workout.date else {
            return chartRange.initialScrollPosition(firstDataDate: firstDataDate)
        }
        let anchored = chartRange.initialScrollPosition(firstDataDate: firstDataDate, now: workoutDate)
        return max(anchored, chartRange.xDomain(firstDataDate: firstDataDate).lowerBound)
    }

    // MARK: - Header

    /// A scoreboard like the in-workout metric popover: the average across the shown window (the
    /// reference, neutral, moving with the scroll) on the left, this workout's own value (the bold
    /// white constant) on the right, the pill between them reading this workout against that average.
    /// We're in the workout detail, so this workout is always the subject — scrolling retargets the
    /// average and the pill, never the side they're compared to.
    private func header(visibleAverage: Double?, firstDataDate: Date?) -> some View {
        // This workout's own value for the metric — "––" when it has none (e.g. duration with no end).
        let raw = metric.rawValue(of: workout)
        // This workout vs the visible window's average — positive when this session beat it. Duration
        // stays neutral gray (longer is neither better nor worse), matching its tile.
        let percentChange: Double? = {
            guard let average = visibleAverage, average > 0, raw > 0 else { return nil }
            return (Double(raw) - average) / average * 100
        }()
        let isDuration = metric == .duration
        return MetricComparisonView(
            leading: .init(
                label: NSLocalizedString("average", comment: ""),
                value: visibleAverage.map { metric.formattedAverage(rawAverage: $0) } ?? "––",
                unit: metric.unit,
                caption: chartRange.visibleWindowDescription(from: chartScrollPosition, firstDataDate: firstDataDate)
            ),
            trailing: .init(
                label: NSLocalizedString("thisWorkout", comment: ""),
                value: raw > 0 ? metric.formattedValue(fromRaw: raw) : "––",
                unit: metric.unit,
                caption: workout.date?.formatted(.dateTime.day().month())
            ),
            trailingValueStyle: isDuration ? AnyShapeStyle(Color.label) : workout.sets.muscleGroupGradientStyle(startPoint: .bottomLeading, endPoint: .topTrailing),
            percentChange: percentChange,
            positiveColor: isDuration ? .secondary : dominantMuscleGroupColor,
            positiveStyle: isDuration ? nil : workout.sets.muscleGroupGradientStyle(startPoint: .bottomLeading, endPoint: .topTrailing)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }

    // MARK: - Chart

    private func chart(points: [StatPoint], snappedPoint: StatPoint?, firstDataDate: Date?) -> some View {
        let yScaleMax = chartYScaleMax(for: points)
        // At month zoom this workout gets its own dedicated column at the far right instead of a
        // bar inside the month grid; in 3M its bar already stands among the other workouts.
        let ownColumnValue = chartRange == .threeMonths ? nil : thisWorkoutDisplayValue
        return HStack(alignment: .top, spacing: 8) {
            historyChart(
                points: points,
                snappedPoint: snappedPoint,
                firstDataDate: firstDataDate,
                yScaleMax: yScaleMax,
                showsYAxisLabels: ownColumnValue == nil
            )
            if let ownColumnValue {
                thisWorkoutColumn(value: ownColumnValue, yScaleMax: yScaleMax)
            }
        }
        .frame(height: 300)
        .padding(.leading)
        .padding(.trailing, 5)
    }

    /// The scrollable history: one bar per workout in 3M, month averages in 1Y / All. When this
    /// workout's dedicated column stands beside it, the y-axis labels move over there — the shared
    /// scale reads once, at the far right — and this chart keeps just the gridlines.
    private func historyChart(
        points: [StatPoint],
        snappedPoint: StatPoint?,
        firstDataDate: Date?,
        yScaleMax: Double,
        showsYAxisLabels: Bool
    ) -> some View {
        Chart {
            if let snappedPoint {
                RuleMark(x: .value("Selected", snappedPoint.date, unit: barUnit))
                    .foregroundStyle(Color.label.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .annotation(
                        position: annotationPosition(for: snappedPoint, firstDataDate: firstDataDate),
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        annotationCard(for: snappedPoint)
                    }
            }
            ForEach(points) { point in
                BarMark(
                    x: .value("Date", point.date, unit: barUnit),
                    y: .value("Value", point.value),
                    width: .ratio(chartRange == .threeMonths ? 0.6 : 0.5)
                )
                .foregroundStyle(barStyle(for: point, snappedPoint: snappedPoint))
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .opacity(snappedPoint == nil || snappedPoint?.id == point.id ? 1.0 : 0.4)
            }
        }
        .chartXScale(domain: xDomain(firstDataDate: firstDataDate))
        .chartYScale(domain: 0 ... yScaleMax)
        .chartScrollableAxes(.horizontal)
        .chartScrollPosition(x: $chartScrollPosition)
        .chartScrollTargetBehavior(
            .valueAligned(matching: chartRange.scrollSnapComponents)
        )
        .chartXSelection(value: $selectedDate)
        .chartXVisibleDomain(length: visibleDomainSeconds(firstDataDate: firstDataDate))
        .chartXAxis {
            let axisStride = chartRange.axisStride(firstDataDate: firstDataDate)
            AxisMarks(
                position: .bottom,
                values: .stride(by: axisStride.component, count: axisStride.count)
            ) { value in
                if let date = value.as(Date.self) {
                    AxisGridLine()
                        .foregroundStyle(Color.gray.opacity(0.5))
                    AxisValueLabel(chartRange.axisLabel(for: date, firstDataDate: firstDataDate))
                        .foregroundStyle(chartRange.isCurrentAxisMark(date, firstDataDate: firstDataDate) ? Color.primary : .secondary)
                        .font(.caption.weight(.bold))
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: [0, yScaleMax / 2, yScaleMax]) { _ in
                AxisGridLine()
                if showsYAxisLabels {
                    AxisValueLabel()
                }
            }
        }
        .emptyPlaceholder(points) {
            Text(NSLocalizedString("noData", comment: ""))
        }
    }

    /// This workout's dedicated column at the far right of the month-zoom charts: its own bar in
    /// the workout's gradient, standing outside the month grid — the months stay honest averages,
    /// never dressed up as this workout, yet its bar is always there to read them against. The
    /// column carries the row's y-axis labels, and its x label is the workout's day, highlighted
    /// like the axis' "now" marks.
    private func thisWorkoutColumn(value: Double, yScaleMax: Double) -> some View {
        Chart {
            BarMark(
                x: .value("Workout", "thisWorkout"),
                y: .value("Value", value),
                width: .fixed(16)
            )
            .foregroundStyle(workout.sets.muscleGroupGradientStyle(startPoint: .bottom, endPoint: .top))
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        }
        .chartYScale(domain: 0 ... yScaleMax)
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel {
                    Text(workout.date?.formatted(.dateTime.day().month()) ?? "")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.primary)
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: [0, yScaleMax / 2, yScaleMax])
        }
        .frame(width: 84)
    }

    /// Where the tooltip hangs off the rule mark: bars in the right third of the visible window get
    /// a leading card, the left third a trailing one. `fit(to: .chart)` alone can't keep the card
    /// on screen here — the plot scrolls, so "the chart" includes off-viewport months and an edge
    /// bar's card happily lays out into them, clipped by the viewport.
    private func annotationPosition(for point: StatPoint, firstDataDate: Date?) -> AnnotationPosition {
        let windowSeconds = Double(visibleDomainSeconds(firstDataDate: firstDataDate))
        guard windowSeconds > 0 else { return .top }
        let fraction = point.date.timeIntervalSince(chartScrollPosition) / windowSeconds
        if fraction > 0.66 { return .topLeading }
        if fraction < 0.33 { return .topTrailing }
        return .top
    }

    private func annotationCard(for point: StatPoint) -> some View {
        VStack(alignment: .leading) {
            UnitView(value: annotationValue(for: point), unit: metric.unit, unitColor: .secondaryLabel)
                .foregroundStyle(Color.label)
            Text(annotationSubtitle(for: point))
                .fontWeight(.bold)
                .fontDesign(.rounded)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondaryBackground))
    }

    private func annotationValue(for point: StatPoint) -> String {
        // A bar backed by a single workout shows that workout's exact value whatever the range;
        // only month bars format as averages.
        point.workout != nil
            ? metric.formattedValue(fromRaw: Int(point.rawValue.rounded()))
            : metric.formattedAverage(rawAverage: point.rawValue)
    }

    private func annotationSubtitle(for point: StatPoint) -> String {
        switch chartRange {
        case .threeMonths:
            let day = point.date.formatted(.dateTime.day().month())
            guard let name = point.workout?.name, !name.isEmpty else { return day }
            return "\(name) · \(day)"
        case .year, .allTime:
            let month = point.date.formatted(.dateTime.month(.abbreviated).year())
            return "\(month) · \(point.workoutCount) \(NSLocalizedString("workouts", comment: ""))"
        }
    }

    // MARK: - Points

    private func statPoints(in workouts: [Workout]) -> [StatPoint] {
        switch chartRange {
        case .threeMonths:
            return workouts.map { workout in
                let raw = metric.rawValue(of: workout)
                return StatPoint(
                    id: workout.objectID,
                    date: workout.date ?? .now,
                    rawValue: Double(raw),
                    value: metric.displayValue(fromRaw: raw),
                    isCurrent: workout.objectID == self.workout.objectID,
                    workout: workout,
                    workoutCount: 1
                )
            }
        case .year, .allTime:
            // At month zoom every bar is an honest whole-month average (this workout included) —
            // a month is never dressed up as a single workout. This workout itself stands in its
            // dedicated column beside the chart, not in the month grid.
            let grouped = Dictionary(grouping: workouts) { $0.date?.startOfMonth ?? .now }
            return grouped
                .map { month, monthWorkouts in
                    let rawAverage = Double(monthWorkouts.map { metric.rawValue(of: $0) }.reduce(0, +))
                        / Double(monthWorkouts.count)
                    return StatPoint(
                        id: month,
                        date: month,
                        rawValue: rawAverage,
                        value: metric.displayValue(fromRaw: Int(rawAverage.rounded())),
                        isCurrent: false,
                        workout: nil,
                        workoutCount: monthWorkouts.count
                    )
                }
                .sorted { $0.date < $1.date }
        }
    }

    /// Bars are single days in the 3M range, whole months in 1Y / All.
    private var barUnit: Calendar.Component {
        chartRange == .threeMonths ? .day : .month
    }

    // MARK: - Averages & Trend

    /// Mean raw value per workout between `from` and `to`, or nil with no workout in the range.
    private func averageRaw(in workouts: [Workout], from: Date, to: Date) -> Double? {
        let values = workouts
            .filter {
                guard let date = $0.date else { return false }
                return date >= from && date <= to
            }
            .map { metric.rawValue(of: $0) }
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    // MARK: - Chart Window

    /// The shared range domain, except All extends through the current month's end: this screen
    /// draws whole-month bars at that zoom, and the shared week-aligned end would clip the newest
    /// month's bar — usually this workout's own — to an invisible sliver.
    private func xDomain(firstDataDate: Date?) -> ClosedRange<Date> {
        let domain = chartRange.xDomain(firstDataDate: firstDataDate)
        guard chartRange == .allTime else { return domain }
        return domain.lowerBound ... max(domain.upperBound, Date.now.endOfMonth)
    }

    /// Matches `xDomain`: All fits its (month-extended) domain into view, the scrolling ranges
    /// keep the shared window lengths.
    private func visibleDomainSeconds(firstDataDate: Date?) -> Int {
        guard chartRange == .allTime else {
            return chartRange.visibleDomainSeconds(firstDataDate: firstDataDate)
        }
        let domain = xDomain(firstDataDate: firstDataDate)
        return Int(domain.upperBound.timeIntervalSince(domain.lowerBound).rounded(.up))
    }

    private func visibleEndDate(firstDataDate: Date?) -> Date {
        Calendar.current.date(
            byAdding: .second,
            value: visibleDomainSeconds(firstDataDate: firstDataDate),
            to: chartScrollPosition
        )!
    }

    /// This workout's value in display units — the height of its dedicated column's bar; nil when
    /// the workout has no usable value (e.g. duration without a recorded end), which also hides
    /// the column, matching the header's "––".
    private var thisWorkoutDisplayValue: Double? {
        let raw = metric.rawValue(of: workout)
        guard raw > 0 else { return nil }
        return metric.displayValue(fromRaw: raw)
    }

    /// Smallest "nice" number (1/2/2.5/5 × power of ten) at or above the largest bar (this
    /// workout's dedicated column included, when it tops every history bar), so the y-axis marks
    /// land on round values whatever unit the stat uses.
    private func chartYScaleMax(for points: [StatPoint]) -> Double {
        let maxValue = max(points.map(\.value).max() ?? 0, thisWorkoutDisplayValue ?? 0)
        guard maxValue > 0 else { return 1 }
        let magnitude = pow(10, floor(log10(maxValue)))
        let normalized = maxValue / magnitude
        let niceNormalized: Double = normalized <= 1 ? 1 : normalized <= 2 ? 2 : normalized <= 2.5 ? 2.5 : normalized <= 5 ? 5 : 10
        return niceNormalized * magnitude
    }

    // MARK: - Selection

    private func nearestPoint(to date: Date?, in points: [StatPoint], visibleEnd: Date) -> StatPoint? {
        guard let target = date else { return nil }
        let visiblePoints = points.filter { $0.date >= chartScrollPosition && $0.date <= visibleEnd }
        let candidates = visiblePoints.isEmpty ? points : visiblePoints
        return candidates.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(target)) < abs(rhs.date.timeIntervalSince(target))
        }
    }

    // MARK: - Colors

    /// The bar for the workout the screen was opened from (only the 3M view has one inside the
    /// history — at month zoom this workout stands in its own column) wears the workout's own
    /// muscle-group gradient — its identity color, the screen's accent. A bar tapped to inspect
    /// lights up white ("now showing this"); every other bar stays a quiet gray. `isCurrent` wins
    /// when the current bar is itself the tapped one — its gradient already stands out.
    private func barStyle(for point: StatPoint, snappedPoint: StatPoint?) -> AnyShapeStyle {
        if point.isCurrent { return workout.sets.muscleGroupGradientStyle(startPoint: .bottom, endPoint: .top) }
        if snappedPoint?.id == point.id { return AnyShapeStyle(Color.label) }
        return AnyShapeStyle(Color.fill)
    }

    private func dominantMuscleGroupColor(of workout: Workout) -> Color {
        muscleGroupService.getMuscleGroupOccurances(in: workout).first?.0.color ?? .accentColor
    }

    private var dominantMuscleGroupColor: Color {
        dominantMuscleGroupColor(of: workout)
    }
}

// MARK: - Preview

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database

    var body: some View {
        NavigationStack {
            WorkoutStatScreen(metric: .volume, workout: database.testWorkout)
        }
    }
}

struct WorkoutStatScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
    }
}
