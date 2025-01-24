//
//  ExerciseVolumeScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 03.12.24.
//

import Charts
import SwiftUI

struct ExerciseVolumeScreen: View {
    
    private enum ChartGranularity {
        case month, year
    }
    
    @EnvironmentObject private var workoutSetRepository: WorkoutSetRepository
    
    let exercise: Exercise
    
    @State private var chartGranularity: ChartGranularity = .month
    @State private var chartScrollPosition: Date = .now
    
    var body: some View {
        ScrollView {
            VStack {
                Picker("Select Chart Granularity", selection: $chartGranularity) {
                    Text(NSLocalizedString("month", comment: ""))
                        .tag(ChartGranularity.month)
                    Text(NSLocalizedString("year", comment: ""))
                        .tag(ChartGranularity.year)
                }
                .pickerStyle(.segmented)
                .padding(.vertical)
                
                VStack(alignment: .leading) {
                    Text(NSLocalizedString("total", comment: ""))
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    UnitView(
                        value: "\(totalVolumeInTimeFrame)",
                        unit: WeightUnit.used.rawValue
                    )
                    .foregroundStyle((exercise.muscleGroup?.color ?? .label).gradient)
                    Text("\(NSLocalizedString("this", comment: "")) \(NSLocalizedString(chartGranularity == .month ? "month" : "year", comment: ""))")
                        .fontWeight(.bold)
                        .fontDesign(.rounded)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Chart {
                    ForEach(setsGroupedByGranularity, id:\.first) { groupedWorkoutSets in
                        BarMark(
                            x: .value("Day", groupedWorkoutSets.first?.workout?.date ?? .now, unit: .weekOfYear),
                            y: .value("Volume", volume(for: groupedWorkoutSets)),
                            width: .ratio(0.5)
                        )
                        .foregroundStyle((exercise.muscleGroup?.color ?? Color.label).gradient)
                    }
                }
                .chartXScale(domain: xDomain)
                .chartScrollableAxes(.horizontal)
                .chartScrollPosition(x: $chartScrollPosition)
                .chartScrollTargetBehavior(
                    .valueAligned(
                        matching: chartGranularity == .month ? DateComponents(weekday: 2) : DateComponents(month: 1, day: 1)
                    )
                )
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
                    AxisMarks(values: .automatic(desiredCount: 4))
                }
                .emptyPlaceholder(setsGroupedByGranularity) {
                    Text(NSLocalizedString("noData", comment: ""))
                }
                .frame(height: 300)
                
            }
            .padding(.horizontal)
            .padding(.top)
        }
        .isBlockedWithoutPro()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack {
                    Text("\(NSLocalizedString("volume", comment: ""))")
                        .font(.headline)
                    Text(exercise.name ?? "")
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
    
    private var xDomain: some ScaleDomain {
        let maxStartDate = Calendar.current.date(
            byAdding: chartGranularity == .month ? .month : .year,
            value: -1,
            to: .now
        )!
        let endDate = chartGranularity == .month ? Date.now.endOfWeek : Date.now.endOfYear
        guard let firstSetDate = setsGroupedByGranularity.first?.first?.workout?.date, firstSetDate < maxStartDate
        else { return maxStartDate...endDate }
        let startDate = chartGranularity == .month ? firstSetDate.startOfMonth : firstSetDate.startOfYear
        return startDate...endDate
    }
    
    private var totalVolumeInTimeFrame: Int {
        let endDate = Calendar.current.date(byAdding: .second, value: visibleChartDomainInSeconds, to: chartScrollPosition)
        let setsInTimeFrame = workoutSetRepository.getWorkoutSets(
            with: exercise,
            from: chartScrollPosition,
            to: endDate
        )
        return volume(for: setsInTimeFrame)
    }
    
    private func volume(for sets: [WorkoutSet]) -> Int {
        convertWeightForDisplaying(getVolume(of: sets, for: exercise))
    }
    
    private func xAxisDateString(for date: Date) -> String {
        switch chartGranularity {
        case .month:
            return date.formatted(.dateTime.day().month(.defaultDigits))
        case .year:
            return date.formatted(Date.FormatStyle().month(.narrow))
        }
    }
    
    private func isDateNow(_ date: Date, for granularity: ChartGranularity) -> Bool {
        switch chartGranularity {
        case .month:
            return Calendar.current.isDate(date, equalTo: .now, toGranularity: [.weekOfYear, .yearForWeekOfYear])
        case .year:
            return Calendar.current.isDate(date, equalTo: .now, toGranularity: [.month, .year])
        }
    }
    
    private var setsGroupedByGranularity: [[WorkoutSet]] {
        workoutSetRepository.getGroupedWorkoutSets(
            with: exercise,
            groupedBy: [.weekOfYear, .year]
        )
    }

}

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database
    
    var body: some View {
        NavigationView {
            ExerciseVolumeScreen(exercise: database.getExercises().first!)
        }
    }
}

struct ExerciseVolumeScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
    }
}
