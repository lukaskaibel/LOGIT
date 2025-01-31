//
//  Untitled.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 03.12.24.
//

import Charts
import SwiftUI

struct ExerciseVolumeTile: View {
        
    @StateObject var exercise: Exercise
    
    var body: some View {
        FetchRequestWrapper(
            WorkoutSet.self,
            predicate: WorkoutSetPredicateFactory.getWorkoutSets(
                with: exercise,
                from: Calendar.current.date(byAdding: .weekOfYear, value: -4, to: .now)!.startOfWeek,
                to: .now
            )
        ) { workoutSets in
            let groupedWorkoutSets = Dictionary(grouping: workoutSets) { $0.workout?.date?.startOfWeek ?? .now }.sorted { $0.key < $1.key }
            VStack {
                HStack {
                    Text(NSLocalizedString("volume", comment: ""))
                        .tileHeaderStyle()
                    Spacer()
                    NavigationChevron()
                        .foregroundStyle(.secondary)
                }
                HStack {
                    VStack(alignment: .leading) {
                        Text(NSLocalizedString("thisWeek", comment: ""))
                        HStack(alignment: .lastTextBaseline, spacing: 0) {
                            Text("\(convertWeightForDisplaying(getVolume(of: groupedWorkoutSets.first?.1 ?? [], for: exercise)))")
                                .font(.title)
                                .foregroundStyle((exercise.muscleGroup?.color ?? .label).gradient)
                            Text(WeightUnit.used.rawValue)
                                .textCase(.uppercase)
                                .foregroundStyle((exercise.muscleGroup?.color ?? .label).gradient)
                        }
                        .fontWeight(.bold)
                        .fontDesign(.rounded)
                    }
                    Spacer()
                    Chart {
                        ForEach(groupedWorkoutSets, id: \.0) { key, workoutSets in
                            BarMark(
                                x: .value("Weeks before now", key, unit: .weekOfYear),
                                y: .value("Volume in week", convertWeightForDisplaying(getVolume(of: workoutSets, for: exercise))),
                                width: .ratio(0.5)
                            )
                            .foregroundStyle(Calendar.current.isDate(key, equalTo: .now, toGranularity: .weekOfYear) ? (exercise.muscleGroup?.color ?? Color.label) : Color.fill)
                        }
                    }
                    .chartXAxis {}
                    .chartYAxis {}
                    .frame(width: 120, height: 80)
                    .padding(.trailing)
                }
            }
            .padding(CELL_PADDING)
            .tileStyle()
        }
    }
    
}


private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database
    
    var body: some View {
        NavigationStack {
            ExerciseVolumeTile(exercise: database.getExercises().first!)
        }
    }
}

struct ExerciseVolumeTileView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
            .padding()
    }
}
