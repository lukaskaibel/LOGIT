//
//  WorkoutStatScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 12.06.26.
//

import Charts
import SwiftUI

/// Detail screen behind a workout stat tile: the stat across *every* workout over time — the tile
/// zooms into this workout's recent runs, the screen zooms out to the whole landscape. One bar per
/// workout in the month view, each colored by its workout's most-trained muscle group (the colors
/// draw the push/pull/legs rhythm); the year view averages each month into one bar. The header
/// shows the average per workout over the visible period with a trend against the period before,
/// matching the exercise chart screens' anatomy (picker, header, scrollable chart with
/// tap-to-inspect, highlights, about). One screen serves all four stats — `WorkoutStatMetric`
/// supplies values, formatting, and texts.
struct WorkoutStatScreen: View {
    private enum ChartGranularity {
        case month, year
    }

    /// A bar of the chart: a single workout in month granularity, a whole month's average in year
    /// granularity.
    private struct StatPoint: Identifiable {
        let id: AnyHashable
        let date: Date
        /// Raw units (grams, minutes, counts) — formatted only for display.
        let rawValue: Double
        /// Display units for the chart's y-axis.
        let value: Double
        let color: Color
        /// The single workout behind this bar — nil for a year-granularity month bar.
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

    @State private var chartGranularity: ChartGranularity = .month
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
        let points = statPoints(in: workouts)
        let snappedPoint = selectedDate != nil ? nearestPoint(to: selectedDate, in: points) : nil
        let visibleAverage = averageRaw(in: workouts, from: chartScrollPosition, to: visibleEndDate)
        let visibleTrendPercentage = trendPercentage(in: workouts)
        return ScrollView {
            VStack(spacing: SECTION_SPACING) {
                VStack {
                    Picker("Select Chart Granularity", selection: $chartGranularity) {
                        Text(NSLocalizedString("month", comment: ""))
                            .tag(ChartGranularity.month)
                        Text(NSLocalizedString("year", comment: ""))
                            .tag(ChartGranularity.year)
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical)
                    .padding(.horizontal)
                    header(visibleAverage: visibleAverage, trendPercentage: visibleTrendPercentage)
                    chart(points: points, snappedPoint: snappedPoint)
                }

                highlightsSection(workouts: workouts)

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
            let firstDayOfNextWeek = Calendar.current.date(byAdding: .day, value: 1, to: .now.endOfWeek)!
            chartScrollPosition = Calendar.current.date(
                byAdding: .second,
                value: -visibleChartDomainInSeconds,
                to: firstDayOfNextWeek
            )!
        }
        .onChange(of: chartGranularity) {
            // Re-initialize scroll position when switching granularity to avoid desync with the
            // visible window (same fix as the exercise chart screens).
            let anchor: Date
            switch chartGranularity {
            case .month:
                anchor = Calendar.current.date(byAdding: .day, value: 1, to: .now.endOfWeek)!
            case .year:
                anchor = Calendar.current.date(byAdding: .month, value: 1, to: .now.startOfMonth)!
            }
            chartScrollPosition = Calendar.current.date(
                byAdding: .second,
                value: -visibleChartDomainInSeconds,
                to: anchor
            )!
        }
    }

    // MARK: - Header

    private func header(visibleAverage: Double?, trendPercentage: Double?) -> some View {
        HStack {
            VStack(alignment: .leading) {
                AverageLabel()
                UnitView(
                    value: visibleAverage.map { metric.formattedAverage(rawAverage: $0) } ?? "––",
                    unit: metric.unit
                )
                .muscleGroupGradientStyle(for: workout.muscleGroups)
                Text(chartHeaderTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let trendPercentage {
                TrendIndicatorView(
                    percentChange: trendPercentage,
                    // A longer workout is neither better nor worse — duration's pill stays
                    // neutral gray in both directions, like its tile.
                    positiveColor: metric == .duration ? .secondary : dominantMuscleGroupColor
                )
                .animation(.snappy, value: trendPercentage)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }

    // MARK: - Chart

    private func chart(points: [StatPoint], snappedPoint: StatPoint?) -> some View {
        let yScaleMax = chartYScaleMax(for: points)
        return Chart {
            if let snappedPoint {
                RuleMark(x: .value("Selected", snappedPoint.date, unit: barUnit))
                    .foregroundStyle(snappedPoint.color.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .annotation(
                        position: .top,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        annotationCard(for: snappedPoint)
                    }
            }
            ForEach(points) { point in
                BarMark(
                    x: .value("Date", point.date, unit: barUnit),
                    y: .value("Value", point.value),
                    width: .ratio(chartGranularity == .month ? 0.6 : 0.5)
                )
                .foregroundStyle(point.color.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .opacity(snappedPoint == nil || snappedPoint?.id == point.id ? 1.0 : 0.4)
            }
        }
        .chartXScale(domain: xDomain(for: points))
        .chartYScale(domain: 0 ... yScaleMax)
        .chartScrollableAxes(.horizontal)
        .chartScrollPosition(x: $chartScrollPosition)
        .chartScrollTargetBehavior(
            .valueAligned(
                matching: chartGranularity == .month
                    ? DateComponents(weekday: Calendar.current.firstWeekday)
                    : DateComponents(month: 1, day: 1)
            )
        )
        .chartXSelection(value: $selectedDate)
        .chartXVisibleDomain(length: visibleChartDomainInSeconds)
        .chartXAxis {
            AxisMarks(
                position: .bottom,
                values: .stride(by: chartGranularity == .month ? .weekOfYear : .month)
            ) { value in
                if let date = value.as(Date.self) {
                    AxisGridLine()
                        .foregroundStyle(Color.gray.opacity(0.5))
                    AxisValueLabel(xAxisDateString(for: date))
                        .foregroundStyle(isDateNow(date) ? Color.primary : .secondary)
                        .font(.caption.weight(.bold))
                }
            }
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

    private func annotationCard(for point: StatPoint) -> some View {
        VStack(alignment: .leading) {
            UnitView(value: annotationValue(for: point), unit: metric.unit)
                .foregroundStyle(point.color.gradient)
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
        switch chartGranularity {
        case .month: return metric.formattedValue(fromRaw: Int(point.rawValue.rounded()))
        case .year: return metric.formattedAverage(rawAverage: point.rawValue)
        }
    }

    private func annotationSubtitle(for point: StatPoint) -> String {
        switch chartGranularity {
        case .month:
            let day = point.date.formatted(.dateTime.day().month())
            guard let name = point.workout?.name, !name.isEmpty else { return day }
            return "\(name) · \(day)"
        case .year:
            let month = point.date.formatted(.dateTime.month(.abbreviated).year())
            return "\(month) · \(point.workoutCount) \(NSLocalizedString("workouts", comment: ""))"
        }
    }

    // MARK: - Points

    private func statPoints(in workouts: [Workout]) -> [StatPoint] {
        switch chartGranularity {
        case .month:
            return workouts.map { workout in
                let raw = metric.rawValue(of: workout)
                return StatPoint(
                    id: workout.objectID,
                    date: workout.date ?? .now,
                    rawValue: Double(raw),
                    value: metric.displayValue(fromRaw: raw),
                    color: dominantMuscleGroupColor(of: workout),
                    workout: workout,
                    workoutCount: 1
                )
            }
        case .year:
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
                        color: muscleGroupService.getMuscleGroupOccurances(in: monthWorkouts).first?.0.color
                            ?? .accentColor,
                        workout: nil,
                        workoutCount: monthWorkouts.count
                    )
                }
                .sorted { $0.date < $1.date }
        }
    }

    /// Bars are single days in month granularity, whole months in year granularity.
    private var barUnit: Calendar.Component {
        chartGranularity == .month ? .day : .month
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

    /// Percent change of the visible window's average over the equal-length window before it —
    /// the same window-vs-window comparison as the exercise chart screens' pill, on averages
    /// because sessions are discrete amounts (a single best would just crown the biggest day).
    private func trendPercentage(in workouts: [Workout]) -> Double? {
        let windowStart = chartScrollPosition
        let previousStart = Calendar.current.date(
            byAdding: .second,
            value: -visibleChartDomainInSeconds,
            to: windowStart
        )!
        guard
            let current = averageRaw(in: workouts, from: windowStart, to: visibleEndDate),
            let previous = averageRaw(in: workouts, from: previousStart, to: windowStart),
            previous > 0
        else { return nil }
        return (current - previous) / previous * 100
    }

    // MARK: - Highlights

    @ViewBuilder
    private func highlightsSection(workouts: [Workout]) -> some View {
        let granularity: HighlightView.Granularity = chartGranularity == .month ? .month : .year
        let ranges = granularity.periodRanges()
        let currentAverage = averageRaw(in: workouts, from: ranges.current.start, to: ranges.current.end) ?? 0
        let previousAverage = averageRaw(in: workouts, from: ranges.previous.start, to: ranges.previous.end) ?? 0

        HighlightView(
            headline: metric.highlightHeadline(
                isMore: currentAverage >= previousAverage,
                isYearGranularity: chartGranularity == .year
            ),
            currentValue: currentAverage > 0 ? metric.highlightValue(rawAverage: currentAverage) : "––",
            previousValue: previousAverage > 0 ? metric.highlightValue(rawAverage: previousAverage) : "––",
            unit: metric.highlightUnit,
            currentNumericValue: currentAverage,
            previousNumericValue: previousAverage,
            granularity: granularity,
            accentColor: dominantMuscleGroupColor
        )
        .padding(.horizontal)
    }

    // MARK: - Chart Window

    private var visibleChartDomainInSeconds: Int {
        3600 * 24 * (chartGranularity == .month ? 35 : 365)
    }

    private var visibleEndDate: Date {
        Calendar.current.date(byAdding: .second, value: visibleChartDomainInSeconds, to: chartScrollPosition)!
    }

    private func xDomain(for points: [StatPoint]) -> some ScaleDomain {
        let maxStartDate = Calendar.current.date(
            byAdding: chartGranularity == .month ? .month : .year,
            value: -1,
            to: .now
        )!
        let endDate = chartGranularity == .month ? Date.now.endOfWeek : Date.now.endOfYear
        guard let firstDate = points.first?.date, firstDate < maxStartDate
        else { return maxStartDate ... endDate }
        let startDate = chartGranularity == .month ? firstDate.startOfMonth : firstDate.startOfYear
        return startDate ... endDate
    }

    private var chartHeaderTitle: String {
        let endDate = visibleEndDate
        switch chartGranularity {
        case .month:
            return "\(chartScrollPosition.isInCurrentYear ? chartScrollPosition.formatted(.dateTime.day().month()) : chartScrollPosition.formatted(.dateTime.day().month().year())) - \(endDate.isInCurrentYear ? endDate.formatted(.dateTime.day().month()) : endDate.formatted(.dateTime.day().month().year()))"
        case .year:
            return "\(chartScrollPosition.formatted(.dateTime.month().year())) - \(endDate.formatted(.dateTime.month().year()))"
        }
    }

    private func xAxisDateString(for date: Date) -> String {
        switch chartGranularity {
        case .month:
            return date.formatted(.dateTime.day().month(.defaultDigits))
        case .year:
            return date.formatted(Date.FormatStyle().month(.narrow))
        }
    }

    private func isDateNow(_ date: Date) -> Bool {
        switch chartGranularity {
        case .month:
            return Calendar.current.isDate(date, equalTo: .now, toGranularity: [.weekOfYear, .yearForWeekOfYear])
        case .year:
            return Calendar.current.isDate(date, equalTo: .now, toGranularity: [.month, .year])
        }
    }

    /// Smallest "nice" number (1/2/2.5/5 × power of ten) at or above the largest bar, so the
    /// y-axis marks land on round values whatever unit the stat uses.
    private func chartYScaleMax(for points: [StatPoint]) -> Double {
        let maxValue = points.map(\.value).max() ?? 0
        guard maxValue > 0 else { return 1 }
        let magnitude = pow(10, floor(log10(maxValue)))
        let normalized = maxValue / magnitude
        let niceNormalized: Double = normalized <= 1 ? 1 : normalized <= 2 ? 2 : normalized <= 2.5 ? 2.5 : normalized <= 5 ? 5 : 10
        return niceNormalized * magnitude
    }

    // MARK: - Selection

    private func nearestPoint(to date: Date?, in points: [StatPoint]) -> StatPoint? {
        guard let target = date else { return nil }
        let visiblePoints = points.filter { $0.date >= chartScrollPosition && $0.date <= visibleEndDate }
        let candidates = visiblePoints.isEmpty ? points : visiblePoints
        return candidates.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(target)) < abs(rhs.date.timeIntervalSince(target))
        }
    }

    // MARK: - Colors

    private func dominantMuscleGroupColor(of workout: Workout) -> Color {
        muscleGroupService.getMuscleGroupOccurances(in: workout).first?.0.color ?? .accentColor
    }

    private var dominantMuscleGroupColor: Color {
        dominantMuscleGroupColor(of: workout)
    }
}

// MARK: - Average Label

/// The "Average" header label on the stat screens — `CurrentBestLabel`'s anatomy with the stat
/// vocabulary: explains that the value is the mean per workout over the visible period and what
/// the trend pill compares it against.
private struct AverageLabel: View {
    @State private var isShowingInfo = false

    var body: some View {
        HStack(spacing: 4) {
            Text(NSLocalizedString("average", comment: ""))
                .fontWeight(.medium)
                .textCase(.uppercase)
            Button {
                isShowingInfo = true
            } label: {
                Image(systemName: "info.circle")
            }
            .popover(isPresented: $isShowingInfo) {
                Text(NSLocalizedString("workoutStatAverageInfo", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding()
                    .frame(width: 300)
                    .presentationCompactAdaptation(.popover)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
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
