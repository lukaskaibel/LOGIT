//
//  ExerciseSetVolumeScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 11.06.26.
//

import Charts
import SwiftUI

struct ExerciseSetVolumeScreen: View {
    private enum ChartGranularity {
        case month, year
    }

    let exercise: Exercise
    let workoutSets: [WorkoutSet]

    @State private var chartGranularity: ChartGranularity = .month
    @State private var chartScrollPosition: Date = .now
    @State private var selectedDate: Date?

    var body: some View {
        let allDailyMaxSets = allDailyMaxSetVolumeSets(in: workoutSets)
        // Determine the snapped selected set only when a selection exists; snap to the nearest datapoint (prefer visible)
        let snappedSelectedSet: WorkoutSet? = selectedDate != nil ? nearestSet(to: selectedDate, in: allDailyMaxSets) : nil
        let bestVisibleSetVolume = bestSetVolumeInGranularity(workoutSets)
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
                            if isShowingCurrentBestWindow {
                                CurrentBestLabel(uppercased: true)
                            } else {
                                Text(NSLocalizedString("best", comment: ""))
                                    .font(.footnote)
                                    .fontWeight(.medium)
                                    .textCase(.uppercase)
                                    .foregroundStyle(.secondary)
                            }
                            UnitView(
                                value: "\(bestVisibleSetVolume != nil ? formatWeightForDisplay(bestVisibleSetVolume!) : "––")",
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
                            let valueDisplayed = formatWeightForDisplay(selectedSet.volume(for: exercise))
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
                                y: .value("Max set volume on day", convertWeightForDisplayingDecimal(firstEntry.volume(for: exercise)))
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(exerciseMuscleGroupColor.gradient)
                            .lineStyle(StrokeStyle(lineWidth: 5))
                            .opacity(snappedSelectedSet == nil ? 1.0 : 0.3)
                            AreaMark(
                                x: .value("Date", Date.distantPast, unit: .day),
                                y: .value("Max set volume on day", convertWeightForDisplayingDecimal(firstEntry.volume(for: exercise)))
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
                                y: .value("Max set volume on day", convertWeightForDisplayingDecimal(workoutSet.volume(for: exercise)))
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
                                y: .value("Max set volume on day", convertWeightForDisplayingDecimal(workoutSet.volume(for: exercise)))
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
                            let setVolumeDisplayed = convertWeightForDisplayingDecimal(lastSet.volume(for: exercise))
                            RuleMark(
                                xStart: .value("Start", lastDate),
                                xEnd: .value("End", Date()),
                                y: .value("Max set volume on day", setVolumeDisplayed)
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
                    .chartYScale(domain: 0 ... chartYScaleMax(maxYValue: allTimeSetVolumePR(in: workoutSets)))
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
                        let chartYScaleMax = chartYScaleMax(maxYValue: allTimeSetVolumePR(in: workoutSets))
                        AxisMarks(values: [0, chartYScaleMax / 2, chartYScaleMax])
                    }
                    .emptyPlaceholder(allDailyMaxSets) {
                        Text(NSLocalizedString("noData", comment: ""))
                    }
                    .frame(height: 300)
                    .padding(.leading)
                    .padding(.trailing, 5)
                }

                // MARK: - About Section
                AboutSection(
                    metricTitle: NSLocalizedString("setVolume", comment: ""),
                    text: NSLocalizedString("setVolumeInfo", comment: "")
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
                    Text("\(NSLocalizedString("setVolume", comment: ""))")
                        .font(.headline)
                    Text(exercise.displayName)
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            }
        }
        .onAppear {
            let firstDayOfNextWeek = Calendar.current.date(byAdding: .day, value: 1, to: .now.endOfWeek)!
            chartScrollPosition = Calendar.current.date(byAdding: .second, value: -visibleChartDomainInSeconds, to: firstDayOfNextWeek)!
        }
        .onChange(of: chartGranularity) {
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

    private func allDailyMaxSetVolumeSets(in workoutSets: [WorkoutSet]) -> [WorkoutSet] {
        let groupedSets = Dictionary(grouping: workoutSets) {
            Calendar.current.startOfDay(for: $0.workout?.date ?? .now)
        }.sorted { $0.key < $1.key }
            .map { $0.1 }
        let maxSetsPerDay = groupedSets
            .compactMap { setsPerDay -> WorkoutSet? in
                return setsPerDay.max(by: { $0.volume(for: exercise) < $1.volume(for: exercise) })
            }
            .filter { $0.volume(for: exercise) > 0 }
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
        guard let firstSetDate = allDailyMaxSetVolumeSets(in: workoutSets).first?.workout?.date, firstSetDate < maxStartDate
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

    private func allTimeSetVolumePR(in workoutSets: [WorkoutSet]) -> Int {
        convertWeightForDisplaying(
            workoutSets
                .map {
                    $0.volume(for: exercise)
                }
                .max() ?? 0
        )
    }

    private func bestSetVolumeInGranularity(_ workoutSets: [WorkoutSet]) -> Int? {
        let endDate = Calendar.current.date(byAdding: .second, value: visibleChartDomainInSeconds, to: chartScrollPosition)!
        let setsInTimeFrame = workoutSets.filter { $0.workout?.date ?? .distantPast >= chartScrollPosition && $0.workout?.date ?? .distantFuture <= endDate }

        guard !setsInTimeFrame.isEmpty else {
            return workoutSets.first?.volume(for: exercise)
        }

        return setsInTimeFrame
            .map { $0.volume(for: exercise) }
            .max()
    }

    /// Set volume has no practical upper bound, so unlike the weight and e1RM screens (which pick
    /// from a fixed list of axis caps) the cap is the PR rounded up to a clean half-magnitude step
    /// — keeping the mid axis mark (cap / 2) a round number too.
    private func chartYScaleMax(maxYValue: Int) -> Int {
        guard maxYValue > 0 else { return 10 }
        let magnitude = pow(10.0, floor(log10(Double(maxYValue))))
        let step = magnitude / 2
        return Int((Double(maxYValue) / step).rounded(.up) * step)
    }

    /// Percent change of the best set volume in the visible chart window versus a comparable window
    /// before it — the window right before, or the last window with training when that's empty
    /// (see `exerciseWindowTrendPercentage`). Nil only when there's no earlier history at all.
    private func trendPercentage(in workoutSets: [WorkoutSet]) -> Double? {
        exerciseWindowTrendPercentage(
            sets: workoutSets,
            windowStart: chartScrollPosition,
            windowSeconds: visibleChartDomainInSeconds
        ) { start, end in
            workoutSets
                .filter { ($0.workout?.date).map { $0 >= start && $0 <= end } ?? false }
                .map { $0.volume(for: exercise) }
                .max()
                .map(Double.init)
        }
    }

    // MARK: - Selection helpers

    private var visibleEndDate: Date {
        Calendar.current.date(byAdding: .second, value: visibleChartDomainInSeconds, to: chartScrollPosition)!
    }

    /// True while the month view sits at its newest scroll position (the default), where the
    /// visible window's best IS the exercise's current best — the header label says so then, with
    /// the info popover explaining the term.
    private var isShowingCurrentBestWindow: Bool {
        chartGranularity == .month && visibleEndDate >= .now
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

}

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database

    var body: some View {
        let exercise = database.getExercises().first!
        NavigationView {
            ExerciseSetVolumeScreen(exercise: exercise, workoutSets: exercise.sets)
        }
    }
}

struct ExerciseSetVolumeScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
    }
}
