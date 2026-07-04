//
//  ExerciseRepetitionsScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 12.11.24.
//

import Charts
import SwiftUI

struct ExerciseRepetitionsScreen: View {
    private enum ChartGranularity {
        case month, year
    }

    let exercise: Exercise
    let workoutSets: [WorkoutSet]

    @State private var chartGranularity: ChartGranularity = .month
    @State private var chartScrollPosition: Date = .now
    @State private var selectedDate: Date?

    var body: some View {
        let allDailyMaxRepsSets = allDailyMaxRepetitionsSets(in: workoutSets)
        // Determine the snapped selected set only when a selection exists; snap to the overall nearest datapoint
        let snappedSelectedSet: WorkoutSet? = selectedDate != nil ? nearestSet(to: selectedDate, in: allDailyMaxRepsSets) : nil
        let bestRepsInGranularity: Int? = bestRepetitionsInGranularity(in: workoutSets)
        let yScaleCap = chartYScaleCap(
            visibleMax: chartVisibleLineMax(
                of: chartPoints(from: allDailyMaxRepsSets),
                from: chartScrollPosition,
                to: visibleEndDate
            )
        )
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
            MetricComparisonView(
                leading: .init(
                    label: NSLocalizedString("previousBest", comment: ""),
                    value: bestRepsInGranularity.map { String($0) } ?? "––",
                    unit: NSLocalizedString("rps", comment: ""),
                    caption: chartHeaderTitle
                ),
                trailing: .init(
                    label: NSLocalizedString(bestAnchor?.isLapsed == true ? "lastBest" : "currentBest", comment: ""),
                    value: bestAnchor.map { String($0.value) } ?? "––",
                    unit: NSLocalizedString("rps", comment: ""),
                    caption: bestAnchor?.date.map { $0.formatted(.dateTime.day().month()) }
                ),
                trailingValueStyle: AnyShapeStyle(exerciseMuscleGroupColor.gradient),
                percentChange: bestAnchor?.isLapsed == true ? nil : headerTrendPercentage(visibleBest: bestRepsInGranularity),
                positiveColor: exerciseMuscleGroupColor,
                explanation: NSLocalizedString("currentBestComparisonInfo", comment: "")
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            Chart {
                // Always show a selection for the closest visible datapoint (fallback to closest overall)
                // Show selection only when a selection exists, snapped to the nearest datapoint
                if selectedDate != nil, let selectedSet = snappedSelectedSet, let sDate = selectedSet.workout?.date {
                    let snapped = Calendar.current.startOfDay(for: sDate)
                    let valueDisplayed = selectedSet.maximum(.repetitions, for: exercise)
                    RuleMark(x: .value("Selected", snapped, unit: .day))
                        .foregroundStyle(exerciseMuscleGroupColor.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            VStack(alignment: .leading) {
                                UnitView(
                                    value: "\(valueDisplayed)",
                                    unit: NSLocalizedString("rps", comment: "")
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
                if let firstEntry = allDailyMaxRepsSets.first {
                    LineMark(
                        x: .value("Date", Date.distantPast, unit: .day),
                        y: .value("Max repetitions on day", firstEntry.maximum(.repetitions, for: exercise))
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(exerciseMuscleGroupColor.gradient)
                    .lineStyle(StrokeStyle(lineWidth: 5))
                    .opacity(snappedSelectedSet == nil ? 1.0 : 0.3)
                    AreaMark(
                        x: .value("Date", Date.distantPast, unit: .day),
                        y: .value("Max repetitions on day", firstEntry.maximum(.repetitions, for: exercise))
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Gradient(colors: [
                        exerciseMuscleGroupColor.opacity(0.5),
                        exerciseMuscleGroupColor.opacity(0.2),
                        exerciseMuscleGroupColor.opacity(0.05),
                    ]))
                    .opacity(snappedSelectedSet == nil ? 1.0 : 0.3)
                }
                ForEach(allDailyMaxRepsSets) { workoutSet in
                    LineMark(
                        x: .value("Date", workoutSet.workout?.date ?? .now, unit: .day),
                        y: .value("Max repetitions on day", workoutSet.maximum(.repetitions, for: exercise))
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(exerciseMuscleGroupColor.gradient)
                    .lineStyle(StrokeStyle(lineWidth: 5))
                    .opacity({
                        guard let s = snappedSelectedSet?.workout?.date else { return 1.0 }
                        return Calendar.current.isDate(workoutSet.workout?.date ?? .distantPast, inSameDayAs: s) ? 1.0 : 0.3
                    }())
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
                    AreaMark(
                        x: .value("Date", workoutSet.workout?.date ?? .now, unit: .day),
                        y: .value("Max repetitions on day", workoutSet.maximum(.repetitions, for: exercise))
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Gradient(colors: [
                        exerciseMuscleGroupColor.opacity(0.5),
                        exerciseMuscleGroupColor.opacity(0.2),
                        exerciseMuscleGroupColor.opacity(0.05),
                    ]))
                    .opacity(selectedDate == nil ? 1.0 : 0.0)
                }
                if selectedDate == nil, let lastSet = allDailyMaxRepsSets.last, let lastDate = lastSet.workout?.date, !Calendar.current.isDateInToday(lastDate) {
                    let repetitionsDisplayed = lastSet.maximum(.repetitions, for: exercise)
                    RuleMark(
                        xStart: .value("Start", lastDate),
                        xEnd: .value("End", Date()),
                        y: .value("Max repetitions on day", repetitionsDisplayed)
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
            .chartYScale(domain: 0 ... yScaleCap)
            .chartScrollableAxes(.horizontal)
            .chartScrollPosition(x: $chartScrollPosition)
            .chartScrollTargetBehavior(
                .valueAligned(
                    matching: chartGranularity == .month ? DateComponents(weekday: Calendar.current.firstWeekday) : DateComponents(month: 1, day: 1)
                )
            )
            .chartXSelection(value: $selectedDate)
            .chartXVisibleDomain(length: visibleChartDomainInSeconds)
            // Rebuild the chart when the granularity flips: reusing the chart across visible-domain
            // changes leaves its scroll offset stale (the viewport shows a window months away from
            // chartScrollPosition), so give each granularity its own chart identity.
            .id(chartGranularity)
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
            .emptyPlaceholder(allDailyMaxRepsSets) {
                Text(NSLocalizedString("noData", comment: ""))
            }
                .frame(height: 300)
                .padding(.leading)
                .padding(.trailing, 5)
                }
                
                // MARK: - About Section
                AboutSection(
                    metricTitle: NSLocalizedString("repetitions", comment: ""),
                    text: NSLocalizedString("repetitionsInfo", comment: "")
                )
                .padding(.horizontal)
            }
            .padding(.top)
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
        }
        // Free on purpose (unlike the other metric chart screens): repetitions is the free tier's
        // complete vertical slice — badge → panel → tile → this screen — so free users experience
        // the full depth Pro offers on weight/e1RM. User decision 2026-06-12.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack {
                    Text("\(NSLocalizedString("repetitions", comment: ""))")
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

    // MARK: - Private Methods

    private func allDailyMaxRepetitionsSets(in workoutSets: [WorkoutSet]) -> [WorkoutSet] {
        let groupedSets = Dictionary(grouping: workoutSets) {
            Calendar.current.startOfDay(for: $0.workout?.date ?? .now)
        }.sorted { $0.key < $1.key }
            .map { $0.1 }
        let maxSetsPerDay = groupedSets
            .compactMap { setsPerDay -> WorkoutSet? in
                return setsPerDay.max(by: { $0.maximum(.repetitions, for: exercise) < $1.maximum(.repetitions, for: exercise) })
            }
            .filter { $0.maximum(.repetitions, for: exercise) > 0 }
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
        guard let firstSetDate = allDailyMaxRepetitionsSets(in: workoutSets).first?.workout?.date, firstSetDate < maxStartDate
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

    /// The header's left value and the comparison baseline: the best reps in the visible window
    /// *other than* the current best, falling back to the most recent day's best before the window
    /// when it holds no other value (see `exerciseOtherBestBaseline`).
    private func bestRepetitionsInGranularity(in workoutSets: [WorkoutSet]) -> Int? {
        exerciseOtherBestBaseline(
            sets: workoutSets,
            windowStart: chartScrollPosition,
            windowEnd: visibleEndDate,
            currentBestDay: bestAnchor?.date
        ) { $0.maximum(.repetitions, for: exercise) }
    }

    /// The plotted daily-max series as plain (day, value) points — the input for the
    /// visible-window y-scale.
    private func chartPoints(from sets: [WorkoutSet]) -> [(date: Date, value: Double)] {
        sets.map { (
            Calendar.current.startOfDay(for: $0.workout?.date ?? .now),
            Double($0.maximum(.repetitions, for: exercise))
        ) }
    }

    /// The fixed right-hand anchor of the header scoreboard, independent of scroll: the current best
    /// (highest reps in the last four weeks) and the day it was reached. When the current-best window
    /// is empty (untrained for over a month) it falls back to the "last best" — the best on the most
    /// recent session — which flips the label to "Last Best" and drops the comparison pill.
    private var bestAnchor: (value: Int, date: Date?, isLapsed: Bool)? {
        if let best = exercise.currentBestSet(for: .repetitions, in: workoutSets) {
            return (best.maximum(.repetitions, for: exercise), best.workout?.date, false)
        }
        if let last = exercise.lastBestSet(for: .repetitions, in: workoutSets) {
            return (last.maximum(.repetitions, for: exercise), last.workout?.date, true)
        }
        return nil
    }

    /// The header pill: the current best measured against the best in the shown window. Nil when
    /// either side is empty, so the pill drops out only when there is genuinely nothing to compare.
    private func headerTrendPercentage(visibleBest: Int?) -> Double? {
        guard let current = bestAnchor?.value, current > 0,
              let visible = visibleBest, visible > 0 else { return nil }
        return (Double(current) - Double(visible)) / Double(visible) * 100
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
        let target = date ?? chartScrollPosition.addingTimeInterval(Double(visibleChartDomainInSeconds) / 2.0)
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
            ExerciseRepetitionsScreen(exercise: exercise, workoutSets: exercise.sets)
        }
    }
}

struct ExerciseRepetitionsScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
    }
}
