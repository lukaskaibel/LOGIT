//
//  CurrentWeekWeeklyTargetTile.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 24.08.24.
//

import SwiftUI

struct CurrentWeekWeeklyTargetTile: View {
    
    // MARK: - AppStorage
    
    @AppStorage("workoutPerWeekTarget") var targetPerWeek: Int = 3
    
    // MARK: - Environment
    
    @EnvironmentObject private var workoutRepository: WorkoutRepository
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading) {
                    Text(NSLocalizedString("workoutGoal", comment: ""))
                        .tileHeaderStyle()
                    Text(NSLocalizedString("PerWeek", comment: ""))
                        .tileHeaderSecondaryStyle()
                }
                Spacer()
                Text("\(targetPerWeek)")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .fontDesign(.rounded)
                    .foregroundStyle(Color.accentColor.gradient)
                NavigationChevron()
                    .foregroundStyle(.secondary)
            }
            
            
//            .frame(maxWidth: .infinity, alignment: .trailing)
//            VStack(alignment: .leading) {
//                Text(NSLocalizedString("goal", comment: ""))
//                    .fontWeight(.semibold)
//                    .foregroundStyle(.secondary)
//                
//                Text(NSLocalizedString("PerWeek", comment: ""))
//                    .fontWeight(.bold)
//                    .fontDesign(.rounded)
//                    .foregroundStyle(.secondary)
//            }
            VStack {
                HStack(alignment: .lastTextBaseline) {
                    Text(NSLocalizedString("currentWeek", comment: ""))
                        .font(.body.weight(.semibold))
                    Spacer()
                    if numberOfWorkoutsInCurrentWeek < targetPerWeek {
                        Label("\(targetPerWeek - numberOfWorkoutsInCurrentWeek) \(NSLocalizedString("toGo", comment: ""))", systemImage: "arrow.right.circle.fill")
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                    } else {
                        Label(NSLocalizedString("done", comment: ""), systemImage: "checkmark.circle.fill")
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.accentColor.gradient)
                    }
                }
                HStack(spacing: 2) {
                    ForEach(0..<targetPerWeek, id:\.self) { index in
                        UnevenRoundedRectangle(cornerRadii: .init(
                            topLeading: index == 0 ? 10 : 0,
                            bottomLeading: index == 0 ? 10 : 0,
                            bottomTrailing: index == targetPerWeek - 1 ? 10 : 0,
                            topTrailing: index == targetPerWeek - 1 ? 10 : 0
                        ))
                        .foregroundStyle(index < numberOfWorkoutsInCurrentWeek ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.placeholder))
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .foregroundStyle(Color.fill)
                )
                .frame(height: 30)
            }
        }
        .padding(CELL_PADDING)
        .tileStyle()
    }
    
    // MARK: - Computed Properties
    
    private var numberOfWorkoutsInCurrentWeek: Int {
        workoutRepository.getWorkouts(for: [.weekOfYear, .yearForWeekOfYear], including: .now).count
    }
}

#Preview {
    CurrentWeekWeeklyTargetTile()
        .previewEnvironmentObjects()
        .padding()
}
