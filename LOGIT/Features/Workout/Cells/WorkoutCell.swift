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
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 12) {
                    Chart {
                        ForEach(muscleGroupService.getMuscleGroupOccurances(in: workout), id: \.0) { muscleGroupOccurance in
                            SectorMark(
                                angle: .value("Value", muscleGroupOccurance.1),
                                innerRadius: .ratio(0.65),
                                angularInset: 1
                            )
                            .foregroundStyle(muscleGroupOccurance.0.color.gradient)
                        }
                    }
                    .frame(width: 40, height: 40)
                    VStack(alignment: .leading) {
                        Text(
                            "\(workout.date?.description(.short) ?? "")  \(workout.date?.formatted(.dateTime.hour().minute()) ?? "")"
                        )
                        .font(.footnote.weight(.medium))
                        .foregroundColor(.secondaryLabel)
                        Text(workout.name ?? NSLocalizedString("noName", comment: ""))
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    NavigationChevron()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Computed UI Properties

    private var exercisesString: String {
        var result = ""
        for exercise in workout.exercises {
            let name = exercise.name
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
