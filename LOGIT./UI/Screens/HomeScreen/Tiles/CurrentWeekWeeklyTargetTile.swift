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
    
    // MARK: - Environment
    
    @EnvironmentObject private var workoutRepository: WorkoutRepository
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(NSLocalizedString("Workouts per Week", comment: ""))
                    .tileHeaderStyle()
                Spacer()
                NavigationChevron()
                    .foregroundStyle(.secondary)
            }
            HStack {
                VStack(alignment: .leading) {
                    Text(NSLocalizedString("ThisWeek", comment: ""))
                    HStack(alignment: .lastTextBaseline) {
                        Text("\(numberOfWorkoutsInCurrentWeek)")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.accentColor.gradient)
                        Text("\(NSLocalizedString("of", comment: "")) \(targetPerWeek)")
                            .foregroundStyle(Color.secondaryLabel)
                    }
                }
                Spacer()
                Chart {
                    ForEach(0..<targetPerWeek, id:\.self) { value in
                        SectorMark(
                            angle: .value("Value", 1),
                            innerRadius: .ratio(0.65),
                            angularInset: 1
                        )
                        .foregroundStyle(value < numberOfWorkoutsInCurrentWeek ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.fill.gradient))
                    }
                }
                .overlay {
                    if numberOfWorkoutsInCurrentWeek >= targetPerWeek {
                        Image(systemName: "checkmark")
                            .fontWeight(.bold)
                            .fontDesign(.rounded)
                            .foregroundStyle(Color.accentColor.gradient)
                    }
                }
                .frame(width: 120, height: 80, alignment: .trailing)
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
