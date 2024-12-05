//
//  WorkoutSetsTile.swift
//  LOGIT
//
//  Created by Volker Kaibel on 06.10.24.
//

import Charts
import SwiftUI

struct OverallSetsTile: View {
    
    @EnvironmentObject private var workoutRepository: WorkoutRepository
    
    var body: some View {
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
                    Text("\(workoutRepository.getWorkouts(for: [.weekOfYear, .yearForWeekOfYear], including: .now).map({ $0.sets }).joined().count)")
                        .font(.title)
                        .fontWeight(.bold)
                        .fontDesign(.rounded)
                        .foregroundStyle(Color.accentColor.gradient)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Chart {
                    ForEach(setsOfLastWeekGroupedByDay, id: \.date) { data in
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
                            // Add vertical dotted grid lines
                            AxisGridLine()
                                .foregroundStyle(Color.gray.opacity(0.5))
//                                .dashStyle([5, 5]) // Dotted line style

                            AxisValueLabel(date.formatted(.dateTime.weekday(.narrow)))
                                .foregroundStyle(Calendar.current.isDateInToday(date) ? Color.primary : .secondary)
                                .font(.caption.weight(.bold))
                        }
                    }
                }
                .chartYAxis {
//                    AxisMarks(values: .automatic(desiredCount: 3))
                }
                .frame(width: 120, height: 80)
                .padding(.trailing)
            }
        }
        .padding(CELL_PADDING)
        .tileStyle()
    }
    
    private var setsOfLastWeekGroupedByDay: [(date: Date, workoutSets: [WorkoutSet])] {
        var result = [(date: Date, workoutSets: [WorkoutSet])]()
        let allDays = allDaysOfTheWeek

        // Create a dictionary to store the workout sets grouped by date
        var groupedByDay: [Date: [WorkoutSet]] = [:]

        workoutRepository.getWorkouts(for: [.weekOfYear, .yearForWeekOfYear], including: .now)
            .map({ $0.sets })
            .joined()
            .forEach { workoutSet in
                if let setDate = workoutSet.workout?.date {
                    let startOfDay = Calendar.current.startOfDay(for: setDate)
                    groupedByDay[startOfDay, default: []].append(workoutSet)
                }
            }

        // Ensure every day of the current week is represented, even with no data
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

        // Get the start of the current week (assuming Sunday start)
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start else { return [] }

        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

}

#Preview {
    OverallSetsTile()
        .previewEnvironmentObjects()
        .padding()
}
