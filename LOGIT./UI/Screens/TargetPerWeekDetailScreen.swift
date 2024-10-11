//
//  TargetPerWeekDetailScreen.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 16.11.22.
//

import SwiftUI

struct TargetPerWeekDetailScreen: View {
    
    // MARK: - AppStorage
    
    @AppStorage("workoutPerWeekTarget") var targetPerWeek: Int = 3
    
    // MARK: - Environment
    
    @EnvironmentObject var workoutRepository: WorkoutRepository
    
    // MARK: - State
    
    @State private var selectedMonthIndexFromNow: Int = 0
    @State private var selectedIndexInWeekGroup: Int? = 0
    @State private var isShowingWorkoutDetail: Bool = false
    @State private var selectedWorkout: Workout? = nil
    
    // MARK: - Body
    
    var body: some View {
        ScrollView {
            VStack(spacing: SECTION_SPACING) {
                header
                    .padding(.horizontal)
                LazyVStack(spacing: SECTION_SPACING) {
                    ForEach(weeksSinceLogitStartGroupedByMonth, id:\.first) { weeksFromNowMonthGroup in
                        VStack(spacing: SECTION_HEADER_SPACING) {
                            Text(Calendar.current.date(byAdding: .weekOfYear, value: -weeksFromNowMonthGroup.first!, to: .now)?.startOfWeek.monthDescription ?? "")
                                .sectionHeaderStyle2()
                                .frame(maxWidth: .infinity, alignment: .leading)
                            VStack(spacing: CELL_SPACING) {
                                ForEach(weeksFromNowMonthGroup, id:\.self) { weeksFromNow in
                                    let isCurrentWeek = weeksFromNow == 0
                                    let numberOfWorkoutsInWeek = workoutRepository.getWorkouts(
                                        for: [.weekOfYear, .yearForWeekOfYear],
                                        including: dateForWeeksAgo(weeksFromNow)!
                                    ).count
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(alignment: .lastTextBaseline) {
                                            Text(Calendar.current.date(byAdding: .weekOfYear, value: -weeksFromNow, to: .now)!.weekDescription)
                                                .fontWeight(isCurrentWeek ? .semibold : .regular)
                                            Spacer()
                                            if numberOfWorkoutsInWeek < targetPerWeek {
                                                Label(
                                                    "\(targetPerWeek - numberOfWorkoutsInWeek) \(NSLocalizedString(isCurrentWeek ? "toGo" : "missing", comment: ""))", systemImage: isCurrentWeek ? "arrow.right.circle.fill" : "xmark.circle.fill")
                                                .font(.footnote)
                                                .fontWeight(.semibold)
                                                .foregroundStyle(.secondary)
                                            } else {
                                                Label(NSLocalizedString("completed", comment: ""), systemImage: "checkmark.circle.fill")
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
                                                .foregroundStyle(index < numberOfWorkoutsInWeek ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.placeholder))
                                            }
                                        }
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .foregroundStyle(Color.fill)
                                        )
                                        .frame(height: 25)
                                    }
                                    .padding(CELL_PADDING)
                                    .tileStyle()
                                }
                            }
                        }
                    }
                    .overlay {
                        if workouts.isEmpty {
                            Text(NSLocalizedString("noData", comment: ""))
                                .fontWeight(.bold)
                                .foregroundColor(.secondaryLabel)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $isShowingWorkoutDetail) {
            if let workout = selectedWorkout {
                WorkoutDetailScreen(workout: workout, canNavigateToTemplate: true)
            }
        }
    }
    
    // MARK: - Supporting Views
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(NSLocalizedString("workoutGoal", comment: ""))
                    .screenHeaderStyle()
                Text("\(NSLocalizedString("PerWeek", comment: ""))")
                    .screenHeaderSecondaryStyle()
                    .foregroundColor(.secondary)
            }
            Spacer()
            Menu {
                ForEach(1...10, id:\.self) { value in
                    Button {
                        targetPerWeek = value
                    } label: {
                        Text("\(value) \(NSLocalizedString("workout\(value == 1 ? "" : "s")", comment: ""))")
                        Text("\(NSLocalizedString("perWeek", comment: ""))")
                        if value == targetPerWeek {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text("\(targetPerWeek)")
                        .font(.system(size: 55))
                        .fontWeight(.bold)
                        .fontDesign(.rounded)
                    Image(systemName: "chevron.up.chevron.down")
                        .fontWeight(.bold)
                }
            }
        }
    }
    
    // MARK: - Supporting Methods
    
    var workouts: [Workout] {
        workoutRepository.getWorkouts(sortedBy: .date)
    }
    
    private var numberOfWeeksSinceLogitStart: Int {
        let logitStartDate = Calendar.current.date(from: .init(year: 2023, month: 1, day: 2))
        return Calendar.current.dateComponents([.weekOfYear], from: logitStartDate!, to: .now).weekOfYear!
    }
    
    private var weeksSinceLogitStartGroupedByMonth: [[Int]] {
        Array(0...numberOfWeeksSinceLogitStart).reduce([[Int]]()) { currentResult, nextValue in
            guard let lastMonth = currentResult.last, !lastMonth.isEmpty else {
                return currentResult + [[nextValue]]
            }
            
            let currentWeekDate = Calendar.current.date(byAdding: .weekOfYear, value: -nextValue, to: Date())!.startOfWeek
            let lastMonthWeekDate = Calendar.current.date(byAdding: .weekOfYear, value: -lastMonth.first!, to: Date())!.startOfWeek
            
            if Calendar.current.isDate(currentWeekDate, equalTo: lastMonthWeekDate, toGranularity: .month) {
                var newResult = currentResult
                newResult[newResult.count - 1].append(nextValue)
                return newResult
            } else {
                return currentResult + [[nextValue]]
            }
        }
    }
    
    private func dateForWeeksAgo(_ weeksAgo: Int) -> Date? {
        return Calendar.current.date(byAdding: .day, value: -(7 * weeksAgo), to: .now, wrappingComponents: false)
    }

}

struct TargetWorkoutsDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            TargetPerWeekDetailScreen()
        }
        .previewEnvironmentObjects()
    }
}
