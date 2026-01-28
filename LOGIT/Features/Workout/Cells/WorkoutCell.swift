//
//  WorkoutCell.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 18.07.22.
//

import Charts
import ColorfulX
import SwiftUI

struct WorkoutCell: View {
    
    // MARK: - Environment

    @EnvironmentObject private var muscleGroupService: MuscleGroupService

    // MARK: - Variables

    @ObservedObject var workout: Workout

    // MARK: - Body

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 10) {
                headerRow
                exercisesRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(CELL_PADDING)
        .background(backgroundGradient)
        .clipShape(RoundedRectangle(cornerRadius: 30))
    }
    
    // MARK: - View Components
    
    private var headerRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                dateAndDurationRow
                HStack(spacing: 5) {
                    workoutTitle
                    NavigationChevron()
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            muscleGroupChart
        }
    }
    
    private var dateAndDurationRow: some View {
        HStack {
            Text(formattedDate)
            if let durationString = workoutDurationString {
                Text("·")
                Text(durationString)
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }
    
    private var workoutTitle: some View {
        Text(workout.name ?? NSLocalizedString("noName", comment: ""))
            .font(.body.weight(.semibold))
            .foregroundColor(.primary)
            .lineLimit(1)
    }
    
    private var muscleGroupChart: some View {
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
        .frame(width: 40, height: 40)
    }
    
    private var exercisesRow: some View {
        HStack(alignment: .bottom, spacing: 4) {
            Text(exercisesSummary)
                .font(.footnote)
                .lineLimit(2)
            Spacer()
        }
    }
    
    private var backgroundGradient: some View {
        ColorfulView(color: workout.muscleGroups.map { $0.color }, speed: .constant(0))
            .mask(
                LinearGradient(
                    colors: [.black.opacity(0.5), .black.opacity(0.3)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .opacity(0.5)
    }

    // MARK: - Computed Properties
    
    private var formattedDate: String {
        guard let date = workout.date else { return "" }
        
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            return NSLocalizedString("today", comment: "").capitalized
        } else if calendar.isDateInYesterday(date) {
            return NSLocalizedString("yesterday", comment: "").capitalized
        } else if let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now), date < oneYearAgo {
            return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year())
        } else {
            return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        }
    }
    
    private var workoutDurationString: String? {
        guard let start = workout.date, let end = workout.endDate else { return nil }
        let totalMinutes = Calendar.current.dateComponents([.minute], from: start, to: end).minute ?? 0
        
        if totalMinutes < 60 {
            return "\(totalMinutes) min"
        } else {
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
        }
    }

    private var exercisesSummary: String {
        let exercises = workout.exercises
        let maxToShow = 20
        
        if exercises.isEmpty {
            return NSLocalizedString("noExercises", comment: "")
        }
        
        let names = exercises.prefix(maxToShow).compactMap { $0.displayName.isEmpty ? nil : $0.displayName }
        let remaining = exercises.count - maxToShow
        
        return remaining > 0 ? names.joined(separator: ", ") + " & more" : names.joined(separator: ", ")
    }
}

// MARK: - Preview

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database

    var body: some View {
        ScrollView {
            VStack(spacing: CELL_PADDING) {
                ForEach(database.fetch(Workout.self) as! [Workout], id: \.id) { workout in
                    WorkoutCell(workout: workout)
                }
            }
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
