//
//  WorkoutCell.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 18.07.22.
//

import Charts
import SwiftUI

struct WorkoutCell: View {
    // MARK: - Environment

    @EnvironmentObject private var muscleGroupService: MuscleGroupService

    // MARK: - Variables

    @ObservedObject var workout: Workout

    // MARK: Body

    var body: some View {
        HStack(spacing: 14) {
            // Muscle group pie chart
            Chart {
                ForEach(muscleGroupService.getMuscleGroupOccurances(in: workout), id: \.0) { muscleGroupOccurance in
                    SectorMark(
                        angle: .value("Value", muscleGroupOccurance.1),
                        innerRadius: .ratio(0.6),
                        angularInset: 1.5
                    )
                    .foregroundStyle(muscleGroupOccurance.0.color.gradient)
                }
            }
            .frame(width: 50, height: 50)
            
            VStack(alignment: .leading, spacing: 4) {
                // Workout name
                Text(workout.name ?? NSLocalizedString("noName", comment: ""))
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                // Date and time
                Text(formattedDateTime)
                    .font(.subheadline)
                    .foregroundColor(.secondaryLabel)
                
                // Stats row
                HStack(spacing: 16) {
                    // Duration
                    if let durationString = workoutDurationString {
                        Label {
                            Text(durationString)
                        } icon: {
                            Image(systemName: "clock")
                        }
                    }
                    
                    // Exercises count
                    Label {
                        Text("\(workout.numberOfSetGroups)")
                    } icon: {
                        Image(systemName: "figure.strengthtraining.traditional")
                    }
                }
                .font(.caption)
                .foregroundColor(.tertiaryLabel)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            NavigationChevron()
                .foregroundStyle(Color.secondaryLabel)
        }
    }

    // MARK: - Computed Properties
    
    private var formattedDateTime: String {
        guard let date = workout.date else { return "" }
        
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            return NSLocalizedString("today", comment: "") + ", " + date.formatted(.dateTime.hour().minute())
        } else if calendar.isDateInYesterday(date) {
            return NSLocalizedString("yesterday", comment: "") + ", " + date.formatted(.dateTime.hour().minute())
        } else if let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now), date < oneYearAgo {
            return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()) + ", " + date.formatted(.dateTime.hour().minute())
        } else {
            return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) + ", " + date.formatted(.dateTime.hour().minute())
        }
    }
    
    private var workoutDurationString: String? {
        guard let start = workout.date, let end = workout.endDate else { return nil }
        let totalMinutes = Calendar.current.dateComponents([.minute], from: start, to: end).minute ?? 0
        
        if totalMinutes < 1 {
            return nil
        } else if totalMinutes < 60 {
            return "\(totalMinutes) min"
        } else {
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            if minutes == 0 {
                return "\(hours)h"
            } else {
                return "\(hours)h \(minutes)m"
            }
        }
    }

    private var exercisesString: String {
        var result = ""
        for exercise in workout.exercises {
            let name = exercise.displayName
            if !name.isEmpty {
                result += (!result.isEmpty ? ", " : "") + name
            }
        }
        return result.isEmpty ? " " : result
    }
}

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database

    var body: some View {
        ScrollView {
            WorkoutCell(workout: database.fetch(Workout.self).first! as! Workout)
        }
    }
}

struct WorkoutCell_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .padding()
            .previewEnvironmentObjects()
    }
}
