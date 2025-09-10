//
//  VolumeScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 03.12.24.
//

import Charts
import SwiftUI

struct VolumeScreen: View {
    private enum ChartGranularity {
        case month, year
    }

    @State private var chartGranularity: ChartGranularity = .month
    @State private var selectedMuscleGroup: MuscleGroup?
    @State private var chartScrollPosition: Date = .now
    @State private var selectedDate: Date?
    
    let workoutSets: [WorkoutSet]

    var body: some View {
        let groupedWorkoutSets = Dictionary(grouping: workoutSets) { $0.workout?.date?.startOfWeek ?? .now }
            .sorted { $0.key < $1.key }
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
                    .padding(.bottom)
                    .padding(.horizontal)
                    VStack(alignment: .leading) {
                        Text(NSLocalizedString("total", comment: ""))
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)
                        UnitView(
                            value: "\(totalVolumeInTimeFrame(workoutSets))",
                            unit: WeightUnit.used.rawValue
                        )
                        .foregroundStyle((selectedMuscleGroup?.color ?? Color.accentColor).gradient)
                        Text("\(visibleDomainDescription)")
                            .fontWeight(.bold)
                            .fontDesign(.rounded)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    Chart {
                        // Single selection rule mark snapped to the start of the selected period
            if let selectedDate {
                            let snapped = getPeriodStart(for: selectedDate)
                            let selectedVolume: Int = {
                                switch chartGranularity {
                                case .month:
                                    let sets = groupedWorkoutSets.first(where: { $0.0 == snapped })?.1 ?? []
                                    if let mg = selectedMuscleGroup { return volume(for: sets, muscleGroup: mg) }
                                    return volume(for: sets)
                case .year:
                    // Year view still selects per week
                    let sets = groupedWorkoutSets.first(where: { $0.0 == snapped })?.1 ?? []
                                    if let mg = selectedMuscleGroup { return volume(for: sets, muscleGroup: mg) }
                                    return volume(for: sets)
                                }
                            }()
                RuleMark(x: .value("Selected", snapped, unit: xUnit))
                                .foregroundStyle(Color.accentColor.opacity(0.35))
                                .lineStyle(StrokeStyle(lineWidth: 1))
                                .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                                    VStack(alignment: .leading) {
                                        UnitView(
                                            value: "\(selectedVolume)",
                                            unit: WeightUnit.used.rawValue
                                        )
                                        .foregroundStyle((selectedMuscleGroup?.color ?? Color.accentColor).gradient)
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

                        ForEach(groupedWorkoutSets, id: \.0) { date, workoutSets in
                            if let selectedMuscleGroup = selectedMuscleGroup {
                                let mgVolume = volume(for: workoutSets, muscleGroup: selectedMuscleGroup)
                                if mgVolume > 0 {
                                    BarMark(
                                        x: .value("Day", date, unit: .weekOfYear),
                                        y: .value("Volume", mgVolume),
                                        width: .ratio(0.5)
                                    )
                                    .foregroundStyle(selectedMuscleGroup.color.gradient)
                                    .opacity(selectedDate == nil || isBarSelected(barDate: date) ? 1.0 : 0.3)
                                }
                            }
                            let total = volume(for: workoutSets)
                            let rest = selectedMuscleGroup != nil ? max(0, total - volume(for: workoutSets, muscleGroup: selectedMuscleGroup!)) : total
                            if rest > 0 {
                                BarMark(
                                    x: .value("Day", date, unit: .weekOfYear),
                                    y: .value("Volume", rest),
                                    width: .ratio(0.5)
                                )
                                .foregroundStyle((selectedMuscleGroup == nil ? Color.accentColor : Color.placeholder).gradient)
                                .opacity(selectedDate == nil || isBarSelected(barDate: date) ? 1.0 : 0.3)
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
                    .emptyPlaceholder(groupedWorkoutSets) {
                        Text(NSLocalizedString("noData", comment: ""))
                    }
                    .frame(height: 300)
                    .padding(.leading)
                    .padding(.trailing, 5)
                }
                MuscleGroupSelector(selectedMuscleGroup: $selectedMuscleGroup)
                    .padding(.top)
            }
            .padding(.top)
        }
        .isBlockedWithoutPro()
        .onAppear {
            // Start showing the most recent period on the right edge like ExerciseVolumeScreen
            let firstDayOfNextWeek = Calendar.current.date(byAdding: .day, value: 1, to: .now.endOfWeek)!
            chartScrollPosition = Calendar.current.date(byAdding: .second, value: -visibleChartDomainInSeconds, to: firstDayOfNextWeek)!
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack {
                    Text("\(NSLocalizedString("volume", comment: ""))")
                        .font(.headline)
                    if let selectedMuscleGroup = selectedMuscleGroup {
                        Text(selectedMuscleGroup.description)
                            .foregroundStyle(selectedMuscleGroup.color.gradient)
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .fontDesign(.rounded)
                    }
                }
            }
        }
    }

    // MARK: - Private Helpers

    private var visibleChartDomainInSeconds: Int { 3600 * 24 * (chartGranularity == .month ? 35 : 365) }

    private var xUnit: Calendar.Component {
        switch chartGranularity {
        case .month: return .weekOfYear
        case .year: return .weekOfYear // select by week in year view
        }
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

    private func totalVolumeInTimeFrame(_ workoutSets: [WorkoutSet]) -> Int {
        let endDate = Calendar.current.date(byAdding: .second, value: visibleChartDomainInSeconds, to: chartScrollPosition)!
        let setsInTimeFrame = workoutSets.filter { $0.workout?.date ?? .distantPast >= chartScrollPosition && $0.workout?.date ?? .distantFuture <= endDate }
        if let selectedMuscleGroup = selectedMuscleGroup {
            return volume(for: setsInTimeFrame, muscleGroup: selectedMuscleGroup)
        }
        return volume(for: setsInTimeFrame)
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

    private func volume(for sets: [WorkoutSet], muscleGroup: MuscleGroup? = nil) -> Int {
        if let muscleGroup = muscleGroup {
            return convertWeightForDisplaying(getVolume(of: sets, for: muscleGroup))
        } else {
            return convertWeightForDisplaying(getVolume(of: sets))
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

    // Removed old non-scrollable grouping helpers

    private func getPeriodStart(for date: Date) -> Date {
        switch chartGranularity {
        case .month: return date.startOfWeek
        case .year: return date.startOfWeek // weekly selection in year view
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
}

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database

    var body: some View {
        NavigationView {
            VolumeScreen(workoutSets: database.testWorkout.sets)
        }
    }
}

struct VolumeScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
    }
}
