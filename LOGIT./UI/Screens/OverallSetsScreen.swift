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
    
    @EnvironmentObject private var workoutRepository: WorkoutRepository
    
    @State private var chartGranularity: ChartGranularity = .week
    
    var body: some View {
        ScrollView {
            VStack(spacing: SECTION_SPACING) {
                VStack(alignment: .leading) {
                    Text(NSLocalizedString("overallSets", comment: ""))
                        .screenHeaderStyle()
                    Text(NSLocalizedString("PerWeek", comment: ""))
                         .screenHeaderSecondaryStyle()
                         .foregroundColor(.secondaryLabel)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
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
                            value: "\(workoutsInSelectedGranularity.map({ $0.sets }).joined().count)",
                            unit: NSLocalizedString("sets", comment: "")
                        )
                        .foregroundStyle(.tint)
                        Text("\(NSLocalizedString("this", comment: "")) \(NSLocalizedString(chartGranularity == .week ? "week" : chartGranularity == .month ? "month" : "year", comment: ""))")
                            .fontWeight(.bold)
                            .fontDesign(.rounded)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Chart {
                        ForEach(setsGroupedByGranularity, id: \.date) { data in
                            BarMark(
                                x: .value("Day", data.date, unit: chartGranularity == .week ? .day : chartGranularity == .month ? .weekOfYear : .month),
                                y: .value("Number of Sets", data.workoutSets.count),
                                width: .ratio(0.5)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 1))
                        }
                    }
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
                
                VStack(spacing: SECTION_HEADER_SPACING) {
                    Text(NSLocalizedString("workouts", comment: ""))
                        .sectionHeaderStyle2()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: CELL_SPACING) {
                        ForEach(workoutsInSelectedGranularity) { workout in
                            WorkoutCell(workout: workout)
                                .padding(CELL_PADDING)
                                .tileStyle()
                        }
                        .emptyPlaceholder(workoutsInSelectedGranularity) {
                            Text(NSLocalizedString("noWorkouts", comment: ""))
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
        
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
    
    private func isDateNow(_ date: Date, for granularity: ChartGranularity) -> Bool {
        switch chartGranularity {
        case .week:
            return Calendar.current.isDateInToday(date)
        case .month:
            return Calendar.current.isDate(date, equalTo: .now, toGranularity: [.weekOfYear, .yearForWeekOfYear])
        case .year:
            return Calendar.current.isDate(date, equalTo: .now, toGranularity: [.month, .year])
        }
    }
    
    private var workoutsInSelectedGranularity: [Workout] {
        workoutRepository.getWorkouts(
            for: chartGranularity == .week ? [.weekOfYear, .yearForWeekOfYear] : chartGranularity == .month ? [.month, .year] : [.year],
            including: .now)
    }
    
    private func getPeriodStart(for date: Date, granularity: ChartGranularity) -> Date? {
        let calendar = Calendar.current
        switch granularity {
        case .week:
            return calendar.startOfDay(for: date)
        case .month:
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start
        case .year:
            return calendar.dateInterval(of: .month, for: date)?.start
        }
    }

    private var setsGroupedByGranularity: [(date: Date, workoutSets: [WorkoutSet])] {
        var result = [(date: Date, workoutSets: [WorkoutSet])]()
        let allPeriods = allPeriodsInSelectedGranularity
        var groupedByPeriod: [Date: [WorkoutSet]] = [:]

        workoutsInSelectedGranularity
            .flatMap { $0.sets }
            .forEach { workoutSet in
                if let setDate = workoutSet.workout?.date,
                   let periodStart = getPeriodStart(for: setDate, granularity: chartGranularity) {
                    groupedByPeriod[periodStart, default: []].append(workoutSet)
                }
            }

        allPeriods.forEach { periodStart in
            let setsForPeriod = groupedByPeriod[periodStart] ?? []
            result.append((date: periodStart, workoutSets: setsForPeriod))
        }

        return result
    }

    private var allPeriodsInSelectedGranularity: [Date] {
        let calendar = Calendar.current
        let today = Date()
        var periods = [Date]()

        switch chartGranularity {
        case .week:
            guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start else { return [] }
            periods = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
        case .month:
            guard let monthInterval = calendar.dateInterval(of: .month, for: today),
                  let firstWeekStart = getPeriodStart(for: monthInterval.start, granularity: .month) else { return [] }
            var periodStart = firstWeekStart
            while periodStart < monthInterval.end {
                periods.append(periodStart)
                guard let nextPeriodStart = calendar.date(byAdding: .weekOfYear, value: 1, to: periodStart) else { break }
                periodStart = nextPeriodStart
            }
        case .year:
            guard let yearStart = calendar.dateInterval(of: .year, for: today)?.start else { return [] }
            periods = (0..<12).compactMap { calendar.date(byAdding: .month, value: $0, to: yearStart) }
        }
        return periods
    }

}

#Preview {
    OverallSetsScreen()
        .previewEnvironmentObjects()
}
