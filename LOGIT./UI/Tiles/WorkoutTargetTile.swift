//
//  WorkoutTargetTile.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 09.08.24.
//

import SwiftUI

struct WorkoutTargetTile: View {
    var targetPerWeek: Int = 2

    @EnvironmentObject private var workoutRepository: WorkoutRepository

    var body: some View {
        VStack {
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 5) {
                            Image(systemName: "target")
                            Text(NSLocalizedString("workoutTarget", comment: ""))
                        }
                        .tileHeaderTertiaryStyle()
                        Text("This Week")
                            .tileHeaderStyle()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    NavigationChevron()
                        .foregroundColor(.secondaryLabel)
                }
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.thinMaterial)
                        .overlay {
                            Text("\(workoutsThisWeek) / \(targetPerWeek)")
                                .font(.system(.body, design: .rounded, weight: .bold))
                        }
                        .overlay {
                            Rectangle()
                                .fill(.white)
                                .overlay {
                                    Text("\(workoutsThisWeek) / \(targetPerWeek)")
                                        .foregroundStyle(.black)
                                        .font(.system(.body, design: .rounded, weight: .bold))
                                }
                                .mask {
                                    HStack {
                                        Rectangle()
                                            .frame(width: geometry.size.width * targetPercentageDone)
                                        Spacer()
                                    }
                                }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .frame(height: 30)
            }
            .padding(CELL_PADDING)
            .background(.white.opacity(0.12))
            .cornerRadius(20)
            TargetPerWeekChart(
                selectedWeeksFromNowIndex: .constant(4),
                canSelectWeek: false,
                grayOutNotSelectedWeeks: false
            )
            .frame(height: 120)
            .padding(CELL_PADDING)
        }
        .tileStyle()
    }

    private var workoutsThisWeek: Int {
        workoutRepository.getWorkouts(for: .weekOfYear, including: .now).count
    }

    private var targetPercentageDone: CGFloat {
        CGFloat(workoutsThisWeek) / CGFloat(targetPerWeek)
    }
}

#Preview {
    WorkoutTargetTile()
        .previewEnvironmentObjects()
        .padding()
}
