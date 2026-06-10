//
//  ExerciseE1RMScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 04.06.26.
//

import Charts
import SwiftUI

struct ExerciseE1RMScreen: View {
    private enum ChartGranularity {
        case month, year
    }

    private let yAxisMaxValuesKG = [10, 25, 50, 100, 150, 200, 300, 400, 500, 600, 700, 800, 900, 1000]
    private let yAxisMaxValuesLBS = [25, 55, 110, 225, 335, 445, 665, 885, 1105, 1325, 1545, 1765, 1985, 2205]

    let exercise: Exercise
    let workoutSets: [WorkoutSet]

    @State private var chartGranularity: ChartGranularity = .month
    @State private var chartScrollPosition: Date = .now
    @State private var selectedDate: Date?
    @State private var isShowingE1RMInfo = false

    var body: some View {
        let allDailyMaxSets = allDailyMaxE1RMSets(in: workoutSets)
        // Determine the snapped selected set only when a selection exists; snap to the nearest datapoint (prefer visible)
        let snappedSelectedSet: WorkoutSet? = selectedDate != nil ? nearestSet(to: selectedDate, in: allDailyMaxSets) : nil
        let bestVisibleE1RM = bestE1RMInGranularity(workoutSets)
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
                            Text(NSLocalizedString("best", comment: ""))
                                .font(.footnote)
                                .fontWeight(.medium)
                                .textCase(.uppercase)
                                .foregroundStyle(.secondary)
                            UnitView(
                                value: "\(bestVisibleE1RM != nil ? formatEstimatedOneRepMax(bestVisibleE1RM!) : "––")",
                                unit: WeightUnit.used.rawValue
                            )
                            .foregroundStyle(exerciseMuscleGroupColor.gradient)
                            Text(chartHeaderTitle)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let visibleTrendPercentage {
                            TrendIndicatorView(
                                percentChange: visibleTrendPercentage,
                                positiveColor: exerciseMuscleGroupColor
                            )
                            .animation(.snappy, value: visibleTrendPercentage)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    Chart {
                        // Show selection only when a selection exists, snapped to the nearest datapoint
                        if selectedDate != nil, let selectedSet = snappedSelectedSet, let sDate = selectedSet.workout?.date {
                            let snapped = Calendar.current.startOfDay(for: sDate)
                            let valueDisplayed = formatEstimatedOneRepMax(selectedSet.estimatedOneRepMax(for: exercise))
                            RuleMark(x: .value("Selected", snapped, unit: .day))
                                .foregroundStyle(exerciseMuscleGroupColor.opacity(0.35))
                                .lineStyle(StrokeStyle(lineWidth: 2))
                                .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                                    VStack(alignment: .leading) {
                                        UnitView(
                                            value: "\(valueDisplayed)",
                                            unit: WeightUnit.used.rawValue
                                        )
                                        .foregroundStyle(exerciseMuscleGroupColor.gradient)
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
                        if let firstEntry = allDailyMaxSets.first {
                            LineMark(
                                x: .value("Date", Date.distantPast, unit: .day),
                                y: .value("Max e1RM on day", convertWeightForDisplayingDecimal(firstEntry.estimatedOneRepMax(for: exercise)))
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(exerciseMuscleGroupColor.gradient)
                            .lineStyle(StrokeStyle(lineWidth: 5))
                            .opacity(snappedSelectedSet == nil ? 1.0 : 0.3)
                            AreaMark(
                                x: .value("Date", Date.distantPast, unit: .day),
                                y: .value("Max e1RM on day", convertWeightForDisplayingDecimal(firstEntry.estimatedOneRepMax(for: exercise)))
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Gradient(colors: [
                                exerciseMuscleGroupColor.opacity(0.5),
                                exerciseMuscleGroupColor.opacity(0.2),
                                exerciseMuscleGroupColor.opacity(0.05),
                            ]))
                            .opacity(snappedSelectedSet == nil ? 1.0 : 0.3)
                        }
                        ForEach(allDailyMaxSets) { workoutSet in
                            LineMark(
                                x: .value("Date", workoutSet.workout?.date ?? .now, unit: .day),
                                y: .value("Max e1RM on day", convertWeightForDisplayingDecimal(workoutSet.estimatedOneRepMax(for: exercise)))
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(exerciseMuscleGroupColor.gradient)
                            .lineStyle(StrokeStyle(lineWidth: 5))
                            .symbol {
                                Circle()
                                    .frame(width: 10, height: 10)
                                    .foregroundStyle(
                                        exerciseMuscleGroupColor.gradient
                                            .opacity({
                                                guard let s = snappedSelectedSet?.workout?.date else { return 1.0 }
                                                return Calendar.current.isDate(workoutSet.workout?.date ?? .distantPast, inSameDayAs: s) ? 1.0 : 0.3
                                            }())
                                    )
                                    .overlay {
                                        Circle()
                                            .frame(width: 4, height: 4)
                                            .foregroundStyle(Color.black)
                                    }
                                    .background(Circle().fill(Color.black))
                            }
                            .opacity({
                                guard let s = snappedSelectedSet?.workout?.date else { return 1.0 }
                                return Calendar.current.isDate(workoutSet.workout?.date ?? .distantPast, inSameDayAs: s) ? 1.0 : 0.3
                            }())
                            AreaMark(
                                x: .value("Date", workoutSet.workout?.date ?? .now, unit: .day),
                                y: .value("Max e1RM on day", convertWeightForDisplayingDecimal(workoutSet.estimatedOneRepMax(for: exercise)))
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Gradient(colors: [
                                exerciseMuscleGroupColor.opacity(0.5),
                                exerciseMuscleGroupColor.opacity(0.2),
                                exerciseMuscleGroupColor.opacity(0.05),
                            ]))
                            .opacity(selectedDate == nil ? 1.0 : 0.0)
                        }
                        if selectedDate == nil, let lastSet = allDailyMaxSets.last, let lastDate = lastSet.workout?.date, !Calendar.current.isDateInToday(lastDate) {
                            let e1RMDisplayed = convertWeightForDisplayingDecimal(lastSet.estimatedOneRepMax(for: exercise))
                            RuleMark(
                                xStart: .value("Start", lastDate),
                                xEnd: .value("End", Date()),
                                y: .value("Max e1RM on day", e1RMDisplayed)
                            )
                            .foregroundStyle(exerciseMuscleGroupColor.opacity(0.45))
                            .lineStyle(
                                StrokeStyle(
                                    lineWidth: 5,
                                    lineCap: .round,
                                    dash: [5, 10]
                                )
                            )
                        }
                    }
                    .chartXScale(domain: xDomain(for: workoutSets))
                    .chartYScale(domain: 0 ... chartYScaleMax(maxYValue: allTimeE1RMPR(in: workoutSets)))
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
                        let chartYScaleMax = chartYScaleMax(maxYValue: allTimeE1RMPR(in: workoutSets))
                        AxisMarks(values: [0, chartYScaleMax / 2, chartYScaleMax])
                    }
                    .emptyPlaceholder(allDailyMaxSets) {
                        Text(NSLocalizedString("noData", comment: ""))
                    }
                    .frame(height: 300)
                    .padding(.leading)
                    .padding(.trailing, 5)
                }

                // MARK: - Highlights Section
                highlightsSection(allDailyMaxSets: allDailyMaxSets)
            }
            .padding(.top)
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
        }
        .isBlockedWithoutPro()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack {
                    Text("\(NSLocalizedString("estimatedOneRepMax", comment: ""))")
                        .font(.headline)
                    Text(exercise.displayName)
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingE1RMInfo = true
                } label: {
                    Image(systemName: "info.circle")
                }
            }
        }
        .popover(isPresented: $isShowingE1RMInfo) {
            e1RMInfoPopover
        }
        .onAppear {
            let firstDayOfNextWeek = Calendar.current.date(byAdding: .day, value: 1, to: .now.endOfWeek)!
            chartScrollPosition = Calendar.current.date(byAdding: .second, value: -visibleChartDomainInSeconds, to: firstDayOfNextWeek)!
        }
        .onChange(of: chartGranularity) { _ in
            // Re-initialize scroll position when switching granularity to avoid desync with visible window
            let anchor: Date
            switch chartGranularity {
            case .month:
                anchor = Calendar.current.date(byAdding: .day, value: 1, to: .now.endOfWeek)!
            case .year:
                // Align right edge roughly to next month for a stable yearly view
                anchor = Calendar.current.date(byAdding: .month, value: 1, to: .now.startOfMonth)!
            }
            chartScrollPosition = Calendar.current.date(byAdding: .second, value: -visibleChartDomainInSeconds, to: anchor)!
        }
    }

    private var e1RMInfoPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("e1RM", comment: ""))
                .font(.headline)
            Text(NSLocalizedString("e1RMInfo", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(width: 280)
        .presentationCompactAdaptation(.popover)
    }

    private func allDailyMaxE1RMSets(in workoutSets: [WorkoutSet]) -> [WorkoutSet] {
        let groupedSets = Dictionary(grouping: workoutSets) {
            Calendar.current.startOfDay(for: $0.workout?.date ?? .now)
        }.sorted { $0.key < $1.key }
            .map { $0.1 }
        let maxSetsPerDay = groupedSets
            .compactMap { setsPerDay -> WorkoutSet? in
                return setsPerDay.max(by: { $0.estimatedOneRepMax(for: exercise) < $1.estimatedOneRepMax(for: exercise) })
            }
            .filter { $0.estimatedOneRepMax(for: exercise) > 0 }
        return maxSetsPerDay
    }

    private var visibleChartDomainInSeconds: Int {
        3600 * 24 * (chartGranularity == .month ? 35 : 365)
    }

    private func xDomain(for workoutSets: [WorkoutSet]) -> some ScaleDomain {
        let maxStartDate = Calendar.current.date(
            byAdding: chartGranularity == .month ? .month : .year,
            value: -1,
            to: .now
        )!
        let endDate = chartGranularity == .month ? Date.now.endOfWeek : Date.now.endOfYear
        guard let firstSetDate = allDailyMaxE1RMSets(in: workoutSets).first?.workout?.date, firstSetDate < maxStartDate
        else { return maxStartDate ... endDate }
        let startDate = chartGranularity == .month ? firstSetDate.startOfMonth : firstSetDate.startOfYear
        return startDate ... endDate
    }

    private var exerciseMuscleGroupColor: Color {
        exercise.muscleGroup?.color ?? Color.accentColor
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

    private var chartHeaderTitle: String {
        let endDate = Calendar.current.date(byAdding: .second, value: visibleChartDomainInSeconds, to: chartScrollPosition)!
        switch chartGranularity {
        case .month:
            return "\(chartScrollPosition.isInCurrentYear ? chartScrollPosition.formatted(.dateTime.day().month()) : chartScrollPosition.formatted(.dateTime.day().month().year())) - \(endDate.isInCurrentYear ? endDate.formatted(.dateTime.day().month()) : endDate.formatted(.dateTime.day().month().year()))"
        case .year:
            return "\(chartScrollPosition.formatted(.dateTime.month().year())) - \(endDate.formatted(.dateTime.month().year()))"
        }
    }

    private func allTimeE1RMPR(in workoutSets: [WorkoutSet]) -> Int {
        convertWeightForDisplaying(
            workoutSets
                .map {
                    $0.estimatedOneRepMax(for: exercise)
                }
                .max() ?? 0
        )
    }

    private func bestE1RMInGranularity(_ workoutSets: [WorkoutSet]) -> Int? {
        let endDate = Calendar.current.date(byAdding: .second, value: visibleChartDomainInSeconds, to: chartScrollPosition)!
        let setsInTimeFrame = workoutSets.filter { $0.workout?.date ?? .distantPast >= chartScrollPosition && $0.workout?.date ?? .distantFuture <= endDate }

        guard !setsInTimeFrame.isEmpty else {
            return workoutSets.first?.estimatedOneRepMax(for: exercise)
        }

        return setsInTimeFrame
            .map { $0.estimatedOneRepMax(for: exercise) }
            .max()
    }

    private func chartYScaleMax(maxYValue: Int) -> Int {
        let values = WeightUnit.used == .kg ? yAxisMaxValuesKG : yAxisMaxValuesLBS
        let nextBiggerYAxisMaxValue = values.filter { $0 > maxYValue }.min()
        return nextBiggerYAxisMaxValue ?? maxYValue
    }

    /// Percent change of the best e1RM in the visible chart window versus the
    /// equal-length window immediately before it. Nil when either window has no data.
    private func trendPercentage(in workoutSets: [WorkoutSet]) -> Double? {
        let windowStart = chartScrollPosition
        let windowEnd = Calendar.current.date(byAdding: .second, value: visibleChartDomainInSeconds, to: windowStart)!
        let previousStart = Calendar.current.date(byAdding: .second, value: -visibleChartDomainInSeconds, to: windowStart)!
        let current = workoutSets
            .filter {
                guard let date = $0.workout?.date else { return false }
                return date >= windowStart && date <= windowEnd
            }
            .map { $0.estimatedOneRepMax(for: exercise) }
            .max()
        let previous = workoutSets
            .filter {
                guard let date = $0.workout?.date else { return false }
                return date >= previousStart && date < windowStart
            }
            .map { $0.estimatedOneRepMax(for: exercise) }
            .max()
        guard let current = current, let previous = previous, previous > 0 else { return nil }
        return (Double(current) - Double(previous)) / Double(previous) * 100
    }

    // MARK: - Selection helpers

    private var visibleEndDate: Date {
        Calendar.current.date(byAdding: .second, value: visibleChartDomainInSeconds, to: chartScrollPosition)!
    }

    private func nearestSet(to date: Date?, in sets: [WorkoutSet]) -> WorkoutSet? {
        let visibleSets = sets.filter {
            guard let d = $0.workout?.date else { return false }
            return d >= chartScrollPosition && d <= visibleEndDate
        }
        let candidates = visibleSets.isEmpty ? sets : visibleSets
        guard !candidates.isEmpty else { return nil }
        guard let target = date else { return nil }
        return candidates.min { a, b in
            let ad = a.workout?.date ?? .distantPast
            let bd = b.workout?.date ?? .distantPast
            return abs(ad.timeIntervalSince(target)) < abs(bd.timeIntervalSince(target))
        }
    }

    // MARK: - Highlights

    @ViewBuilder
    private func highlightsSection(allDailyMaxSets: [WorkoutSet]) -> some View {
        let ranges = periodRanges()
        let currentMax = maxE1RM(in: ranges.current, sets: allDailyMaxSets)
        let previousMax = maxE1RM(in: ranges.previous, sets: allDailyMaxSets)
        let headlineKey = e1RMHeadlineKey(isHigher: currentMax >= previousMax)
        let unit = WeightUnit.used.rawValue

        HighlightView(
            headline: NSLocalizedString(headlineKey, comment: ""),
            currentValue: currentMax > 0 ? formatEstimatedOneRepMax(currentMax) : "––",
            previousValue: previousMax > 0 ? formatEstimatedOneRepMax(previousMax) : "––",
            unit: unit,
            currentNumericValue: Double(convertWeightForDisplaying(currentMax)),
            previousNumericValue: Double(convertWeightForDisplaying(previousMax)),
            granularity: chartGranularity == .month ? .month : .year,
            accentColor: exerciseMuscleGroupColor
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

    private func maxE1RM(in range: (start: Date, end: Date), sets: [WorkoutSet]) -> Int {
        let s = range.start, e = range.end
        let setsInRange = sets.filter {
            guard let d = $0.workout?.date else { return false }
            return d >= s && d <= e
        }
        return setsInRange.map { $0.estimatedOneRepMax(for: exercise) }.max() ?? 0
    }

    private func e1RMHeadlineKey(isHigher: Bool) -> String {
        switch chartGranularity {
        case .month: return isHigher ? "higherMaxE1RMThisMonthThanLastMonth" : "lowerMaxE1RMThisMonthThanLastMonth"
        case .year: return isHigher ? "higherMaxE1RMThisYearThanLastYear" : "lowerMaxE1RMThisYearThanLastYear"
        }
    }
}

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database

    var body: some View {
        let exercise = database.getExercises().first!
        NavigationView {
            ExerciseE1RMScreen(exercise: exercise, workoutSets: exercise.sets)
        }
    }
}

struct ExerciseE1RMScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
    }
}
