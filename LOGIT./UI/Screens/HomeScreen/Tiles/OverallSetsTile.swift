//
//  WorkoutSetsTile.swift
//  LOGIT
//
//  Created by Volker Kaibel on 06.10.24.
//

import Charts
import SwiftUI

struct OverallSetsTile: View {
        
    var body: some View {
        FetchRequestWrapper(
            Workout.self,
            sortDescriptors: [SortDescriptor(\.date, order: .reverse)],
            predicate: WorkoutPredicateFactory.getWorkouts(
                from: .now.startOfWeek,
                to: .now
            )
        ) { workouts in
            VStack(spacing: 20) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(NSLocalizedString("overallSets", comment: ""))
                            .tileHeaderStyle()
                        
                    }
                    Spacer()
                    NavigationChevron()
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    VStack(alignment: .leading) {
                        Text(NSLocalizedString("thisWeek", comment: ""))
                        Text("\(workouts.map({ $0.sets }).joined().count)")
                            .font(.title)
                            .fontWeight(.bold)
                            .fontDesign(.rounded)
                            .foregroundStyle(Color.accentColor.gradient)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Chart {
                        ForEach(setsOfLastWeekGroupedByDay(workouts), id: \.date) { data in
                            BarMark(
                                x: .value("Day", data.date, unit: .day),
                                y: .value("Number of Sets", data.workoutSets.count),
                                width: .ratio(0.5)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 1))
                        }
                    }
                    .chartXAxis {
                        AxisMarks(position: .bottom, values: .stride(by: .day)) { value in
                            if let date = value.as(Date.self) {
                                AxisGridLine()
                                    .foregroundStyle(Color.gray.opacity(0.5))
                                AxisValueLabel(date.formatted(.dateTime.weekday(.narrow)))
                                    .foregroundStyle(Calendar.current.isDateInToday(date) ? Color.primary : .secondary)
                                    .font(.caption.weight(.bold))
                            }
                        }
                    }
                    .chartYAxis {}
                    .frame(width: 120, height: 80)
                    .padding(.trailing)
                }
            }
            .padding(CELL_PADDING)
            .tileStyle()
        }
    }
    
    private func setsOfLastWeekGroupedByDay(_ workouts: [Workout]) -> [(date: Date, workoutSets: [WorkoutSet])] {
        var result = [(date: Date, workoutSets: [WorkoutSet])]()
        let allDays = allDaysOfTheWeek

        var groupedByDay: [Date: [WorkoutSet]] = [:]

        workouts
            .map({ $0.sets })
            .joined()
            .forEach { workoutSet in
                if let setDate = workoutSet.workout?.date {
                    let startOfDay = Calendar.current.startOfDay(for: setDate)
                    groupedByDay[startOfDay, default: []].append(workoutSet)
                }
            }

        allDays.forEach { day in
            let startOfDay = Calendar.current.startOfDay(for: day)
            let setsForDay = groupedByDay[startOfDay] ?? []
            result.append((date: startOfDay, workoutSets: setsForDay))
        }

        return result
    }

    private var allDaysOfTheWeek: [Date] {
        let calendar = Calendar.current
        let today = Date()

        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start else { return [] }

        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

}

#Preview {
    OverallSetsTile()
        .previewEnvironmentObjects()
        .padding()
}
