//
//  Untitled.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 03.12.24.
//

import Charts
import SwiftUI

struct ExerciseVolumeTile: View {
    
    @EnvironmentObject private var workoutSetRepository: WorkoutSetRepository
    
    let exercise: Exercise
    
    var body: some View {
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
                        Text("\(exerciseVolumePerWeek(for: 0))")
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
                    ForEach(0..<5, id: \.self) { weeksBeforeNow in
                        let date = Calendar.current.date(byAdding: .weekOfYear, value: -weeksBeforeNow, to: .now) ?? .now
                        BarMark(
                            x: .value("Weeks before now", date, unit: .weekOfYear),
                            y: .value("Volume in week", exerciseVolumePerWeek(for: weeksBeforeNow)),
                            width: .ratio(0.5)
                        )
                        .foregroundStyle(weeksBeforeNow == 0 ? (exercise.muscleGroup?.color ?? Color.label) : Color.fill)
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
    
    private func exerciseVolumePerWeek(for weeksBeforeNow: Int) -> Int {
        guard let date = Calendar.current.date(byAdding: .weekOfYear, value: -(weeksBeforeNow), to: .now) else { return 0 }
        let workoutSetsThisWeek = workoutSetRepository.getWorkoutSets(
            with: exercise,
            for: [.weekOfYear, .yearForWeekOfYear],
            including: date
        )
        return convertWeightForDisplaying(getVolume(of: workoutSetsThisWeek, for: exercise))
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
