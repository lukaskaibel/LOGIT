//
//  ExerciseSetsScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 22.06.26.
//

import Charts
import SwiftUI

/// Sets-per-week over time for a single exercise — the detail screen behind the weekly Sets tile.
/// Structurally the twin of `ExerciseVolumeScreen` (same scrollable weekly bar chart, month/year
/// granularity, selection and highlights), but it counts working sets per week instead of summing
/// weight: how many sets you logged is the standard training-volume landmark, alongside tonnage.
struct ExerciseSetsScreen: View {
    private enum ChartGranularity {
        case month, year
    }

    let exercise: Exercise
    let workoutSets: [WorkoutSet]

    @State private var chartGranularity: ChartGranularity = .month
    @State private var chartScrollPosition: Date = .now
    @State private var selectedDate: Date?

    var body: some View {
        let groupedWorkoutSets = Dictionary(grouping: workoutSets) { $0.workout?.date?.startOfWeek ?? .now }.sorted { $0.key < $1.key }
        let visibleTrendPercentage = trendPercentage(in: workoutSets)
        ScrollView {
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
                HStack {
                    VStack(alignment: .leading) {
                        Text(NSLocalizedString("total", comment: ""))
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)
                        UnitView(
                            value: totalSetsInTimeFrame(workoutSets),
                            unit: ""
                        )
                        .foregroundStyle((exercise.muscleGroup?.color ?? .label).gradient)
                        Text("\(visibleDomainDescription)")
                            .fontWeight(.bold)
                            .fontDesign(.rounded)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let visibleTrendPercentage {
                        TrendIndicatorView(
                            percentChange: visibleTrendPercentage,
                            positiveColor: exercise.muscleGroup?.color ?? .label
                        )
                        .animation(.snappy, value: visibleTrendPercentage)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                Chart {
                    ForEach(groupedWorkoutSets, id: \.0) { date, workoutSets in
                        BarMark(
                            x: .value("Day", date, unit: .weekOfYear),
                            y: .value("Sets", setCount(for: workoutSets)),
                            width: .ratio(0.5)
                        )
                        .foregroundStyle((exercise.muscleGroup?.color ?? Color.label).gradient)
                        .opacity(selectedDate == nil || isBarSelected(barDate: date) ? 1.0 : 0.3)
                    }
                    // Single selection rule mark snapped to the start of the selected period
                    if let selectedDate {
                        let snapped = getPeriodStart(for: selectedDate)
                        let selectedSets: String = {
                            let sets = groupedWorkoutSets.first(where: { $0.0 == snapped })?.1 ?? []
                            return setCountFormatted(for: sets)
                        }()
                        RuleMark(x: .value("Selected", snapped, unit: xUnit))
                            .foregroundStyle((exercise.muscleGroup?.color ?? Color.label).gradient.opacity(0.35))
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                                VStack(alignment: .leading) {
                                    UnitView(
                                        value: selectedSets,
                                        unit: ""
                                    )
                                    .foregroundStyle((exercise.muscleGroup?.color ?? .label).gradient)
                                    Text(domainDescription(for: selectedDate))
                                        .fontWeight(.bold)
                                        .fontDesign(.rounded)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondaryBackground))
                            }
                    }
                }
                .chartXScale(domain: xDomain(for: groupedWorkoutSets.map { $0.1 }))
                .chartScrollableAxes(.horizontal)
                .chartScrollPosition(x: $chartScrollPosition)
                .chartScrollTargetBehavior(
                    .valueAligned(
                        matching: chartGranularity == .month ? DateComponents(weekday: Calendar.current.firstWeekday) : DateComponents(month: 1, day: 1)
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
                                .foregroundStyle(isDateNow(date, for: chartGranularity) ? Color.primary : .secondary)
                                .font(.caption.weight(.bold))
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 3))
                }
                .emptyPlaceholder(groupedWorkoutSets) {
                    Text(NSLocalizedString("noData", comment: ""))
                }
                .frame(height: 300)
                .padding(.leading)
                .padding(.trailing, 5)
                }

                // MARK: - Highlights Section
                highlightsSection

                // MARK: - About Section
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
        .onAppear {
            let firstDayOfNextWeek = Calendar.current.date(byAdding: .day, value: 1, to: .now.endOfWeek)!
            chartScrollPosition = Calendar.current.date(byAdding: .second, value: -visibleChartDomainInSeconds, to: firstDayOfNextWeek)!
        }
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

    // MARK: - Private Methods

    private var visibleChartDomainInSeconds: Int {
        3600 * 24 * (chartGranularity == .month ? 35 : 365)
    }

    private func xDomain(for groupedWorkoutSets: [[WorkoutSet]]) -> some ScaleDomain {
        let maxStartDate = Calendar.current.date(
            byAdding: chartGranularity == .month ? .month : .year,
            value: -1,
            to: .now
        )!
        let endDate = chartGranularity == .month ? Date.now.endOfWeek : Date.now.endOfYear
        guard let firstSetDate = groupedWorkoutSets.first?.first?.workout?.date, firstSetDate < maxStartDate
        else { return maxStartDate ... endDate }
        let startDate = chartGranularity == .month ? firstSetDate.startOfMonth : firstSetDate.startOfYear
        return startDate ... endDate
    }

    private func totalSetsInTimeFrame(_ workoutSets: [WorkoutSet]) -> String {
        let endDate = Calendar.current.date(byAdding: .second, value: visibleChartDomainInSeconds, to: chartScrollPosition)!
        let setsInTimeFrame = workoutSets.filter { $0.workout?.date ?? .distantPast >= chartScrollPosition && $0.workout?.date ?? .distantFuture <= endDate }
        return setCountFormatted(for: setsInTimeFrame)
    }

    /// Working-set count — only sets with a recorded entry, matching the weekly tile.
    private func setCount(for sets: [WorkoutSet]) -> Int {
        sets.filter(\.hasEntry).count
    }

    private func setCountFormatted(for sets: [WorkoutSet]) -> String {
        "\(setCount(for: sets))"
    }

    /// Percent change of the total set count in the visible chart window versus a comparable window
    /// before it — the window right before, or the last window with training when that's empty
    /// (see `exerciseWindowTrendPercentage`). Nil only when there's no earlier history at all.
    private func trendPercentage(in workoutSets: [WorkoutSet]) -> Double? {
        exerciseWindowTrendPercentage(
            sets: workoutSets,
            windowStart: chartScrollPosition,
            windowSeconds: visibleChartDomainInSeconds
        ) { start, end in
            let inRange = workoutSets.filter { ($0.workout?.date).map { $0 >= start && $0 <= end } ?? false }
            return inRange.isEmpty ? nil : Double(setCount(for: inRange))
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

    private func isDateNow(_ date: Date, for _: ChartGranularity) -> Bool {
        switch chartGranularity {
        case .month:
            return Calendar.current.isDate(date, equalTo: .now, toGranularity: [.weekOfYear, .yearForWeekOfYear])
        case .year:
            return Calendar.current.isDate(date, equalTo: .now, toGranularity: [.month, .year])
        }
    }

    private var visibleDomainDescription: String {
        let endDate = Calendar.current.date(byAdding: .second, value: visibleChartDomainInSeconds, to: chartScrollPosition)!
        switch chartGranularity {
        case .month:
            return "\(chartScrollPosition.isInCurrentYear ? chartScrollPosition.formatted(.dateTime.day().month()) : chartScrollPosition.formatted(.dateTime.day().month().year())) - \(endDate.isInCurrentYear ? endDate.formatted(.dateTime.day().month()) : endDate.formatted(.dateTime.day().month().year()))"
        case .year:
            return "\(chartScrollPosition.formatted(.dateTime.month().year())) - \(endDate.formatted(.dateTime.month().year()))"
        }
    }

    // MARK: - Selection helpers

    private var xUnit: Calendar.Component {
        switch chartGranularity {
        case .month: return .weekOfYear
        case .year: return .weekOfYear // select by week in year view
        }
    }

    private func getPeriodStart(for date: Date) -> Date {
        switch chartGranularity {
        case .month: return date.startOfWeek
        case .year: return date.startOfWeek // weekly selection in year view
        }
    }

    private func isBarSelected(barDate: Date) -> Bool {
        guard let selectedDate = selectedDate else { return false }
        switch chartGranularity {
        case .month:
            return selectedDate >= barDate && selectedDate <= barDate.endOfWeek
        case .year:
            // Year view: still select by week
            return selectedDate >= barDate && selectedDate <= barDate.endOfWeek
        }
    }

    private func domainDescription(for date: Date) -> String {
        switch chartGranularity {
        case .month:
            return "\(date.startOfWeek.formatted(.dateTime.day().month())) - \(date.endOfWeek.formatted(.dateTime.day().month()))"
        case .year:
            // Year view: describe the selected week range
            return "\(date.startOfWeek.formatted(.dateTime.day().month())) - \(date.endOfWeek.formatted(.dateTime.day().month()))"
        }
    }

    // MARK: - Highlights

    @ViewBuilder
    private var highlightsSection: some View {
        let ranges = periodRanges()
        let currentAvg = averageSetsPerWorkout(in: ranges.current)
        let previousAvg = averageSetsPerWorkout(in: ranges.previous)
        let headlineKey = exerciseSetsHeadlineKey(isMore: currentAvg >= previousAvg)
        let unit = "\(NSLocalizedString("sets", comment: ""))/\(NSLocalizedString("workout", comment: ""))"

        HighlightView(
            headline: NSLocalizedString(headlineKey, comment: ""),
            currentValue: HighlightView.formatNumber(currentAvg),
            previousValue: HighlightView.formatNumber(previousAvg),
            unit: unit,
            currentNumericValue: currentAvg,
            previousNumericValue: previousAvg,
            granularity: chartGranularity == .month ? .month : .year,
            accentColor: exercise.muscleGroup?.color ?? .accentColor
        )
        .padding(.horizontal)
    }

    private func periodRanges() -> (current: (start: Date, end: Date), previous: (start: Date, end: Date)) {
        switch chartGranularity {
        case .month:
            let current = (Date.now.startOfMonth, Date.now.endOfMonth)
            let lastStart = Calendar.current.date(byAdding: .month, value: -1, to: .now.startOfMonth)!
            let previous = (lastStart, lastStart.endOfMonth)
            return (current, previous)
        case .year:
            let current = (Date.now.startOfYear, Date.now.endOfYear)
            let lastStart = Calendar.current.date(byAdding: .year, value: -1, to: .now.startOfYear)!
            let previous = (lastStart, lastStart.endOfYear)
            return (current, previous)
        }
    }

    private func averageSetsPerWorkout(in range: (start: Date, end: Date)) -> Double {
        let s = range.start, e = range.end
        let setsInRange = workoutSets.filter {
            guard let d = $0.workout?.date else { return false }
            return d >= s && d <= e
        }
        let totalSets = Double(setCount(for: setsInRange))
        let workoutsInRange = Set(setsInRange.compactMap { $0.workout }).filter {
            guard let d = $0.date else { return false }
            return d >= s && d <= e
        }
        let workoutCount = max(workoutsInRange.count, 1)
        return totalSets / Double(workoutCount)
    }

    private func exerciseSetsHeadlineKey(isMore: Bool) -> String {
        switch chartGranularity {
        case .month: return isMore ? "avgMoreExerciseSetsThisMonthThanLastMonth" : "avgLessExerciseSetsThisMonthThanLastMonth"
        case .year: return isMore ? "avgMoreExerciseSetsThisYearThanLastYear" : "avgLessExerciseSetsThisYearThanLastYear"
        }
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
