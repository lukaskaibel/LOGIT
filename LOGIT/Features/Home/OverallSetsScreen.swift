//
//  OverallSetsScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 08.10.24.
//

import Charts
import SwiftUI

struct OverallSetsScreen: View {
    private enum ChartGranularity {
        case week, month, year
    }

    @State private var chartGranularity: ChartGranularity = .week
    @State private var chartScrollPosition: Date = .now
    @State private var selectedDate: Date?

    let workouts: [Workout]

    var body: some View {
        ScrollView {
            VStack(spacing: SECTION_SPACING) {
                VStack {
                    Picker("Select Chart Granularity", selection: $chartGranularity) {
                        Text(NSLocalizedString("week", comment: ""))
                            .tag(ChartGranularity.week)
                        Text(NSLocalizedString("month", comment: ""))
                            .tag(ChartGranularity.month)
                        Text(NSLocalizedString("year", comment: ""))
                            .tag(ChartGranularity.year)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: chartGranularity) { _ in
                        // Keep the right edge showing the current period when switching granularity
                        chartScrollPosition = initialScrollPosition
                    }

                    VStack(alignment: .leading) {
                        Text(NSLocalizedString("total", comment: ""))
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)
                        UnitView(
                            value: "\(totalSetsInTimeFrame(workouts))",
                            unit: NSLocalizedString("sets", comment: "")
                        )
                        .foregroundStyle(.tint)
                        Text(visibleDomainDescription)
                            .fontWeight(.bold)
                            .fontDesign(.rounded)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    let grouped = setsGroupedByGranularity(workouts)
                    Chart {
                        ForEach(grouped, id: \.date) { data in
                            if data.workoutSets.count > 0 {
                                BarMark(
                                    x: .value("Period", data.date, unit: xUnit),
                                    y: .value("Number of Sets", data.workoutSets.count),
                                    width: .ratio(0.5)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 1))
                                .foregroundStyle(Color.accentColor)
                                .opacity(selectedDate == nil || isBarSelected(barDate: data.date) ? 1.0 : 0.3)
                            } else {
                                // Keep spacing with a transparent zero bar (optional)
                                BarMark(
                                    x: .value("Period", data.date, unit: xUnit),
                                    y: .value("Number of Sets", 0),
                                    width: .ratio(0.5)
                                )
                                .opacity(0)
                            }
                        }
                        // Single selection rule mark snapped to the start of the selected period
                        if let selectedDate {
                            let snapped = getPeriodStart(for: selectedDate)
                            let selectedCount = grouped.first(where: { $0.date == snapped })?.workoutSets.count ?? 0
                            RuleMark(x: .value("Selected", snapped, unit: xUnit))
                                .foregroundStyle(Color.accentColor.opacity(0.35))
                                .lineStyle(StrokeStyle(lineWidth: 2))
                                .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                                    VStack(alignment: .leading) {
                                        UnitView(
                                            value: "\(selectedCount)",
                                            unit: NSLocalizedString("sets", comment: "")
                                        )
                                        .foregroundStyle(Color.accentColor.gradient)
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
                    .chartXScale(domain: xDomain(for: grouped.map { $0.workoutSets }))
                    .chartScrollableAxes(.horizontal)
                    .chartScrollPosition(x: $chartScrollPosition)
                    .chartScrollTargetBehavior(
                        .valueAligned(
                            matching: scrollAlignmentComponents
                        )
                    )
                    .chartXSelection(value: $selectedDate)
                    .chartXVisibleDomain(length: visibleChartDomainInSeconds)
                    .chartXAxis {
                        AxisMarks(
                            position: .bottom,
                            values: .stride(by: chartGranularity == .week ? .day : chartGranularity == .month ? .weekOfYear : .month)
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
                    .frame(height: 300)
                }
                .padding(.horizontal)
                VStack(spacing: SECTION_HEADER_SPACING) {
                    Text(NSLocalizedString("highlights", comment: ""))
                        .sectionHeaderStyle2()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 14) {
                        // Minimal helpers used for readability
                        let ranges = periodRanges()
                        let currentAvg = averagePerWorkout(in: ranges.current)
                        let previousAvg = averagePerWorkout(in: ranges.previous)
                        let summaryKey = headlineKey(isMore: currentAvg >= previousAvg)

                        let currentLabel: String = {
                            switch chartGranularity {
                            case .week: return NSLocalizedString("thisWeek", comment: "")
                            case .month: return NSLocalizedString("thisMonth", comment: "")
                            case .year: return String(Calendar.current.component(.year, from: Date()))
                            }
                        }()
                        let previousLabel: String = {
                            switch chartGranularity {
                            case .week: return NSLocalizedString("lastWeek", comment: "")
                            case .month: return NSLocalizedString("lastMonth", comment: "")
                            case .year: return String(Calendar.current.component(.year, from: Date()) - 1)
                            }
                        }()

                        let numberFormatter: NumberFormatter = {
                            let f = NumberFormatter()
                            f.numberStyle = .decimal
                            f.maximumFractionDigits = 1
                            f.minimumFractionDigits = 0
                            return f
                        }()
                        let currentText = numberFormatter.string(from: NSNumber(value: currentAvg)) ?? String(format: "%.1f", currentAvg)
                        let previousText = numberFormatter.string(from: NSNumber(value: previousAvg)) ?? String(format: "%.1f", previousAvg)
                        let maxBar = max(max(currentAvg, previousAvg), 1.0)

                        // Headline
                        Text(NSLocalizedString(summaryKey, comment: "Overall sets comparison headline"))
                            .font(.headline)
                            .fontWeight(.semibold)
                            .fixedSize(horizontal: false, vertical: true)

                        // Current period
                        VStack(alignment: .leading, spacing: 6) {
                            UnitView(value: currentText, unit: unitLabel, configuration: .large, unitColor: Color.secondaryLabel)
                            ComparisonBar(value: currentAvg, maxValue: maxBar, tint: .accentColor)
                                .frame(height: 30)
                                .overlay(
                                    Text(currentLabel)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 10), alignment: .leading
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }

                        // Previous period
                        VStack(alignment: .leading, spacing: 6) {
                            UnitView(value: previousText, unit: unitLabel, configuration: .large, unitColor: Color.secondaryLabel)
                            ComparisonBar(value: previousAvg, maxValue: maxBar, tint: .gray.opacity(0.25))
                                .frame(height: 30)
                                .overlay(
                                    Text(previousLabel)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .padding(.horizontal, 10), alignment: .leading
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                    .padding(CELL_PADDING)
                    .tileStyle()
                }
                .padding(.horizontal)
            }
            .padding(.top)
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
        }
        .isBlockedWithoutPro()
        .onAppear {
            // Initialize scroll position so right edge shows current period(s)
            chartScrollPosition = initialScrollPosition
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(NSLocalizedString("overallSets", comment: ""))
                    .font(.headline)
            }
        }
    }

    // MARK: - Scroll / Domain Helpers

    private var visibleChartDomainInSeconds: Int {
        switch chartGranularity {
        case .week: return 3600 * 24 * 7
        case .month: return 3600 * 24 * 35
        case .year: return 3600 * 24 * 365
        }
    }

    private var visibleDomainDescription: String {
        let endDate = Calendar.current.date(byAdding: .second, value: visibleChartDomainInSeconds, to: chartScrollPosition)!
        switch chartGranularity {
        case .week:
            if Calendar.current.isDate(chartScrollPosition, equalTo: .now, toGranularity: [.weekOfYear, .yearForWeekOfYear]) {
                return NSLocalizedString("thisWeek", comment: "")
            }
            return "\(chartScrollPosition.isInCurrentYear ? chartScrollPosition.formatted(.dateTime.day().month()) : chartScrollPosition.formatted(.dateTime.day().month().year())) - \(endDate.isInCurrentYear ? endDate.formatted(.dateTime.day().month()) : endDate.formatted(.dateTime.day().month().year()))"
        case .month:
            return "\(chartScrollPosition.isInCurrentYear ? chartScrollPosition.formatted(.dateTime.day().month()) : chartScrollPosition.formatted(.dateTime.day().month().year())) - \(endDate.isInCurrentYear ? endDate.formatted(.dateTime.day().month()) : endDate.formatted(.dateTime.day().month().year()))"
        case .year:
            return "\(chartScrollPosition.formatted(.dateTime.month().year())) - \(endDate.formatted(.dateTime.month().year()))"
        }
    }

    private func domainDescription(for date: Date) -> String {
        switch chartGranularity {
        case .week:
            return "\(date.formatted(.dateTime.day().month()))"
        case .month:
            return "\(date.startOfWeek.formatted(.dateTime.day().month())) - \(date.endOfWeek.formatted(.dateTime.day().month()))"
        case .year:
            return "\(date.formatted(.dateTime.month(.wide)))"
        }
    }

    private func isBarSelected(barDate: Date) -> Bool {
        guard let selectedDate = selectedDate else { return false }
        return selectedDate >= barDate && selectedDate <= Calendar.current.date(
            byAdding: chartGranularity == .week ? .day : chartGranularity == .month ? .weekOfYear : .month,
            value: 1,
            to: barDate
        )!
    }

    private func totalSetsInTimeFrame(_ workouts: [Workout]) -> Int {
        let endDate = Calendar.current.date(byAdding: .second, value: visibleChartDomainInSeconds, to: chartScrollPosition)!
        let sets = workouts.flatMap { $0.sets }.filter { set in
            guard let d = set.workout?.date else { return false }
            return d >= chartScrollPosition && d <= endDate
        }
        return sets.count
    }

    private var scrollAlignmentComponents: DateComponents {
        switch chartGranularity {
        case .week: return DateComponents(weekday: Calendar.current.firstWeekday) // Align to locale start of week
        case .month: return DateComponents(weekday: Calendar.current.firstWeekday) // Align to locale start of week
        case .year: return DateComponents(month: 1, day: 1)
        }
    }

    private var xUnit: Calendar.Component {
        switch chartGranularity {
        case .week: return .day
        case .month: return .weekOfYear
        case .year: return .month
        }
    }

    private var initialScrollPosition: Date {
        switch chartGranularity {
        case .week:
            // Show current week fully
            let firstDayOfNextWeek = Calendar.current.date(byAdding: .day, value: 1, to: .now.endOfWeek)!
            return Calendar.current.date(byAdding: .second, value: -visibleChartDomainInSeconds, to: firstDayOfNextWeek)!
        case .month:
            let firstDayOfNextWeek = Calendar.current.date(byAdding: .day, value: 1, to: .now.endOfWeek)!
            return Calendar.current.date(byAdding: .second, value: -visibleChartDomainInSeconds, to: firstDayOfNextWeek)!
        case .year:
            let firstDayOfNextMonth = Calendar.current.date(byAdding: .month, value: 1, to: .now.startOfMonth)!
            return Calendar.current.date(byAdding: .second, value: -visibleChartDomainInSeconds, to: firstDayOfNextMonth)!
        }
    }

    private func xDomain(for groupedWorkoutSets: [[WorkoutSet]]) -> some ScaleDomain {
        let endDate: Date
        let startDate: Date
        switch chartGranularity {
        case .week:
            endDate = Date.now.endOfWeek
            if let earliestDate = groupedWorkoutSets.compactMap({ $0.first?.workout?.date }).min() {
                startDate = earliestDate.startOfWeek
            } else {
                startDate = Date.now.startOfWeek
            }
        case .month:
            let maxStartDate = Calendar.current.date(byAdding: .month, value: -1, to: .now)!
            endDate = Date.now.endOfWeek
            if let earliestDate = groupedWorkoutSets.compactMap({ $0.first?.workout?.date }).min(), earliestDate < maxStartDate {
                startDate = earliestDate.startOfMonth
            } else {
                startDate = maxStartDate
            }
        case .year:
            let maxStartDate = Calendar.current.date(byAdding: .year, value: -1, to: .now)!
            endDate = Date.now.endOfYear
            if let earliestDate = groupedWorkoutSets.compactMap({ $0.first?.workout?.date }).min(), earliestDate < maxStartDate {
                startDate = earliestDate.startOfYear
            } else {
                startDate = maxStartDate
            }
        }
        return startDate ... endDate
    }

    private func xAxisDateString(for date: Date) -> String {
        switch chartGranularity {
        case .week:
            return date.formatted(Date.FormatStyle().weekday(.abbreviated))
        case .month:
            return date.formatted(.dateTime.day().month(.defaultDigits))
        case .year:
            return date.formatted(Date.FormatStyle().month(.narrow))
        }
    }

    private func isDateNow(_ date: Date, for _: ChartGranularity) -> Bool {
        switch chartGranularity {
        case .week:
            return Calendar.current.isDateInToday(date)
        case .month:
            return Calendar.current.isDate(date, equalTo: .now, toGranularity: [.weekOfYear, .yearForWeekOfYear])
        case .year:
            return Calendar.current.isDate(date, equalTo: .now, toGranularity: [.month, .year])
        }
    }

    private func getPeriodStart(for date: Date) -> Date {
        switch chartGranularity {
        case .week: return Calendar.current.startOfDay(for: date)
        case .month: return date.startOfWeek
        case .year: return date.startOfMonth
        }
    }

    private func setsGroupedByGranularity(_ workouts: [Workout]) -> [(date: Date, workoutSets: [WorkoutSet])] {
        let allSets = workouts.flatMap { $0.sets }
        let groupedDict = Dictionary(grouping: allSets) { getPeriodStart(for: $0.workout?.date ?? .now) }
        let sortedKeys = groupedDict.keys.sorted()
        // Ensure current period dates with zero sets appear (for current week/day granularity) by adding placeholders inside visible domain start
        return sortedKeys.map { ($0, groupedDict[$0] ?? []) }
    }

    // MARK: - Highlights (helpers kept intentionally minimal)

    private var unitLabel: String { "\(NSLocalizedString("sets", comment: ""))/\(NSLocalizedString("workout", comment: ""))" }

    private func periodRanges() -> (current: (start: Date, end: Date), previous: (start: Date, end: Date)) {
        switch chartGranularity {
        case .week:
            let current = (Date.now.startOfWeek, Date.now.endOfWeek)
            let lastStart = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: .now.startOfWeek)!
            let previous = (lastStart, lastStart.endOfWeek)
            return (current, previous)
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

    private func averagePerWorkout(in range: (start: Date, end: Date)) -> Double {
        let s = range.start, e = range.end
        let sets = workouts.flatMap { $0.sets }.reduce(into: 0) { acc, set in
            if let d = set.workout?.date, d >= s && d <= e { acc += 1 }
        }
        let sessions = workouts.reduce(into: 0) { acc, w in
            if let d = w.date, d >= s && d <= e { acc += 1 }
        }
        return Double(sets) / max(Double(sessions), 1)
    }

    private func headlineKey(isMore: Bool) -> String {
        switch chartGranularity {
        case .week: return isMore ? "avgMoreSetsPerWorkoutThisWeekThanLastWeek" : "avgFewerSetsPerWorkoutThisWeekThanLastWeek"
        case .month: return isMore ? "avgMoreSetsPerWorkoutThisMonthThanLastMonth" : "avgFewerSetsPerWorkoutThisMonthThanLastMonth"
        case .year: return isMore ? "avgMoreSetsPerWorkoutThisYearThanLastYear" : "avgFewerSetsPerWorkoutThisYearThanLastYear"
        }
    }
}

// MARK: - Small UI helper for the filled horizontal bar

private struct ComparisonBar: View {
    let value: Double
    let maxValue: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let ratio = maxValue > 0 ? CGFloat(min(max(value / maxValue, 0), 1)) : 0
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondaryBackground)
                RoundedRectangle(cornerRadius: 10)
                    .fill(tint)
                    .frame(width: width * ratio)
            }
        }
    }
}

// #Preview {
//    OverallSetsScreen(workouts: )
//        .previewEnvironmentObjects()
// }
