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

    @AppStorage("workoutPerWeekTarget") var targetPerWeek: Int = -1
    
    // MARK: - State
    
    @State private var isShowingChangeGoalSheet = false

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
                    Text(NSLocalizedString("workoutGoal", comment: ""))
                        .tileHeaderStyle()
                    Spacer()
                    if targetPerWeek > 0 {
                        NavigationChevron()
                            .foregroundStyle(.secondary)
                    }
                }
                
                if targetPerWeek > 0 {
                    // Normal view with progress
                    HStack(alignment: .bottom) {
                        UnitView(value: "\(workouts.count)", unit: "\(NSLocalizedString("of", comment: "")) \(targetPerWeek)", configuration: .large, unitColor: Color.secondaryLabel)
                            .foregroundStyle(Color.accentColor.gradient)
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
                } else {
                    // No goal set - show set goal button
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(NSLocalizedString("noGoalSet", comment: ""))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            isShowingChangeGoalSheet = true
                        } label: {
                            Label(NSLocalizedString("setGoal", comment: ""), systemImage: "plus.circle.fill")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                    }
                }
            }
            .padding(CELL_PADDING)
            .tileStyle()
            .sheet(isPresented: $isShowingChangeGoalSheet) {
                NavigationStack {
                    ChangeWeeklyWorkoutGoalScreen()
                }
            }
        }
    }
}

#Preview {
    CurrentWeekWeeklyTargetTile()
        .previewEnvironmentObjects()
        .padding()
}
