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
                        // Single selection rule mark snapped to the start of the selected period
                        if let selectedDate {
                            let snapped = getPeriodStart(for: selectedDate)
                            let selectedCount = grouped.first(where: { $0.date == snapped })?.workoutSets.count ?? 0
                            RuleMark(x: .value("Selected", snapped, unit: xUnit))
                                .foregroundStyle(Color.accentColor.opacity(0.35))
                                .lineStyle(StrokeStyle(lineWidth: 1))
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
            }
            .padding(.top)
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
}



//#Preview {
//    OverallSetsScreen(workouts: )
//        .previewEnvironmentObjects()
//}
