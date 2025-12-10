//
//  PinnedExerciseVolumeTile.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 30.11.24.
//

import Charts
import SwiftUI

struct PinnedExerciseVolumeTile: View {
    let exercise: Exercise
    let workoutSets: [WorkoutSet]

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
                    Text(exercise.name ?? "")
                        .tileHeaderStyle()
                    Spacer()
                    NavigationChevron()
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading) {
                        Text(NSLocalizedString("volumeThisWeek", comment: ""))
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                            .fontWeight(.semibold)
                        UnitView(
                            value: "\(formatWeightForDisplay(getVolume(of: groupedWorkoutSets.first?.1 ?? [], for: exercise)))",
                            unit: WeightUnit.used.rawValue.uppercased(),
                            configuration: .large
                        )
                        .foregroundStyle((exercise.muscleGroup?.color ?? Color.label).gradient)
                    }
                    Spacer()
                    Chart {
                        ForEach(groupedWorkoutSets, id: \.0) { key, workoutSets in
                            BarMark(
                                x: .value("Weeks before now", key, unit: .weekOfYear),
                                y: .value("Volume in week", convertWeightForDisplayingDecimal(getVolume(of: workoutSets, for: exercise))),
                                width: .ratio(0.5)
                            )
                            .foregroundStyle(Calendar.current.isDate(key, equalTo: .now, toGranularity: .weekOfYear) ? (exercise.muscleGroup?.color ?? Color.label) : Color.fill)
                        }
                    }
                    .chartXScale(domain: xDomain)
                    .chartXAxis {}
                    .chartYAxis {}
                    .frame(width: 120, height: 70)
                }
            }
            .padding(CELL_PADDING)
            .tileStyle()
        }
    }

    private var xDomain: some ScaleDomain {
        let startDate = Calendar.current.date(byAdding: .weekOfYear, value: -4, to: .now)!.startOfWeek
        return startDate ... Date.now.endOfWeek
    }
}

struct PinnedExerciseVolumeTile_Previews: PreviewProvider {
    @EnvironmentObject static var database: Database

    static var previews: some View {
        PinnedExerciseVolumeTile(exercise: database.getExercises().first!, workoutSets: database.getExercises().flatMap { $0.sets })
            .previewEnvironmentObjects()
    }
}
