//
//  CurrentWeekWeeklyTargetTile.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 24.08.24.
//

import Charts
import SwiftUI

struct CurrentWeekWeeklyTargetTile: View {
    // MARK: - AppStorage

    @AppStorage("workoutPerWeekTarget") var targetPerWeek: Int = 3

    // MARK: - Body

    var body: some View {
        FetchRequestWrapper(
            Workout.self,
            sortDescriptors: [SortDescriptor(\.date, order: .reverse)],
            predicate: WorkoutPredicateFactory.getWorkouts(
                from: .now.startOfWeek,
                to: .now
            )
        ) { workouts in
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    HStack {
                        Image(systemName: "target")
                        Text(NSLocalizedString("workoutGoal", comment: ""))
                    }
                    .tileHeaderStyle()
                    Spacer()
                    NavigationChevron()
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .bottom) {
                    HStack(alignment: .lastTextBaseline) {
                        Text("\(workouts.count)")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.accentColor.gradient)
                        Text("\(NSLocalizedString("of", comment: "")) \(targetPerWeek)")
                            .foregroundStyle(Color.secondaryLabel)
                    }
                    Spacer()
                    Chart {
                        ForEach(0 ..< targetPerWeek, id: \.self) { value in
                            SectorMark(
                                angle: .value("Value", 1),
                                innerRadius: .ratio(0.65),
                                angularInset: 1
                            )
                            .foregroundStyle(value < workouts.count ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.fill.gradient))
                        }
                    }
                    .overlay {
                        if workouts.count >= targetPerWeek {
                            Image(systemName: "checkmark")
                                .fontWeight(.bold)
                                .fontDesign(.rounded)
                                .foregroundStyle(Color.accentColor.gradient)
                        }
                    }
                    .frame(width: 70, height: 70, alignment: .trailing)
                }
            }
            .padding(CELL_PADDING)
            .tileStyle()
        }
    }
}

#Preview {
    CurrentWeekWeeklyTargetTile()
        .previewEnvironmentObjects()
        .padding()
}
