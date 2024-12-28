//
//  TargetPerWeekDetailScreen.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 16.11.22.
//

import Charts
import OSLog
import SwiftUI

struct TargetPerWeekDetailScreen: View {
    
    // MARK: - Static
    
    private static let logger = Logger(
        subsystem: ".com.lukaskbl.LOGIT",
        category: "MuscleGroupSplitScreen"
    )
    
    // MARK: - AppStorage
    
    @AppStorage("workoutPerWeekTarget") var targetPerWeek: Int = 3
    
    // MARK: - Environment
    
    @EnvironmentObject var workoutRepository: WorkoutRepository
    
    // MARK: - State

    @State private var isShowingChangeGoalScreen = false
    @State private var selectedWeeksFromNow = 0
    
    // MARK: - Body
    
    var body: some View {
        ScrollView {
            VStack(spacing: SECTION_SPACING) {
                VStack(spacing: 20) {
                    HStack {
                        Text(Calendar.current.date(byAdding: .weekOfYear, value: -selectedWeeksFromNow, to: .now)?.startOfWeek.weekDescription ?? "")
                        Spacer()
                        HStack {
                            Button {
                                withAnimation {
                                    selectedWeeksFromNow = selectedWeeksFromNow < 54 ? selectedWeeksFromNow + 1 : 0
                                }
                            } label: {
                                Image(systemName: "chevron.left")
                            }
                            .disabled(selectedWeeksFromNow >= 54)
                            Button {
                                withAnimation {
                                    selectedWeeksFromNow = selectedWeeksFromNow > 0 ? selectedWeeksFromNow - 1 : 0
                                }
                            } label: {
                                Image(systemName: "chevron.right")
                            }
                            .disabled(selectedWeeksFromNow == 0)
                        }
                    }
                    .font(.title3)
                    
                    TabView(selection: $selectedWeeksFromNow) {
                        ForEach(Array<Int>(0..<54).reversed(), id:\.self) { weeksFromNow in
                            let numberOfWorkoutsInCurrentWeek = getWorkouts(inWeeksFromNow: weeksFromNow).count
                            Chart {
                                ForEach(0..<targetPerWeek, id:\.self) { value in
                                    SectorMark(
                                        angle: .value("Value", 1),
                                        innerRadius: .ratio(0.65),
                                        angularInset: 1
                                    )
                                    .foregroundStyle(value < numberOfWorkoutsInCurrentWeek ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.fill))
                                }
                            }
                            .overlay {
                                if numberOfWorkoutsInCurrentWeek >= targetPerWeek {
                                    Image(systemName: "checkmark")
                                        .font(.title)
                                        .fontWeight(.bold)
                                        .foregroundStyle(Color.accentColor.gradient)
                                } else {
                                    VStack(spacing: 0) {
                                        Text("\(targetPerWeek - numberOfWorkoutsInCurrentWeek)")
                                            .font(.title3)
                                            .fontWeight(.semibold)
                                        Text(NSLocalizedString("toGo", comment: ""))
                                            .font(.footnote)
                                            .textCase(.uppercase)
                                    }
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 200, height: 200)
                            .tag(weeksFromNow)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: 250)
                    
                    HStack(alignment: .firstTextBaseline) {
                        Spacer()
                        VStack {
                            let numberOfWorkoutsInCurrentWeek = getWorkouts(inWeeksFromNow: selectedWeeksFromNow).count
                            Text("\(numberOfWorkoutsInCurrentWeek)")
                                .font(.title)
                                .fontDesign(.rounded)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.accentColor.gradient)
                            Text(NSLocalizedString("workout\(numberOfWorkoutsInCurrentWeek == 1 ? "" : "s")", comment: ""))
                                .textCase(.uppercase)
                                .font(.footnote)
                                .foregroundStyle(Color.accentColor.gradient)
                        }
                        .frame(maxWidth: .infinity)
                        Text("/")
                            .textCase(.uppercase)
                            .font(.title2)
                            .fontDesign(.rounded)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        
                        VStack {
                            Text("\(targetPerWeek)")
                                .font(.title)
                                .fontDesign(.rounded)
                                .fontWeight(.bold)
                            Text(NSLocalizedString("goal", comment: ""))
                                .textCase(.uppercase)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        Spacer()
                    }
                }
                Spacer()
                Button {
                    isShowingChangeGoalScreen = true
                } label: {
                    Label("Change Goal", systemImage: "plusminus.circle")
                }
                .buttonStyle(SecondaryBigButtonStyle())
            }
            .padding(.horizontal)
            .padding(.bottom)
            VStack(spacing: SECTION_HEADER_SPACING) {
                Text(NSLocalizedString("workouts", comment: ""))
                    .sectionHeaderStyle2()
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: CELL_SPACING) {
                    ForEach(getWorkouts(inWeeksFromNow: selectedWeeksFromNow)) { workout in
                        WorkoutCell(workout: workout)
                            .padding(CELL_PADDING)
                            .secondaryTileStyle()
                    }
                    .emptyPlaceholder(getWorkouts(inWeeksFromNow: selectedWeeksFromNow)) {
                        Text(NSLocalizedString("noWorkouts", comment: ""))
                    }
                }
            }
            .padding()
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
            .background(Color.secondaryBackground)
        }
        .padding(.top)
        .isBlockedWithoutPro()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack {
                    Text(NSLocalizedString("workouts", comment: ""))
                        .font(.headline)
                    Text(NSLocalizedString("PerWeek", comment: ""))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $isShowingChangeGoalScreen) {
            NavigationStack {
                ChangeWeeklyWorkoutGoalScreen()
            }
        }
        .edgesIgnoringSafeArea(.bottom)
    }
    
    // MARK: - Supporting Methods
    
    var workouts: [Workout] {
        workoutRepository.getWorkouts(sortedBy: .date)
    }
    
    private func getWorkouts(inWeeksFromNow weeksFromNow: Int) -> [Workout] {
        guard let weeksFromNowDate = Calendar.current.date(
            byAdding: .weekOfYear,
            value: -weeksFromNow,
            to: .now
        ) else {
            Self.logger.warning("weeksFromNowDate could not be created.")
            return []
        }
        let workoutsInWeek = workoutRepository.getWorkouts(
            for: [.weekOfYear, .yearForWeekOfYear],
            including: weeksFromNowDate
        )
        return workoutsInWeek
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
