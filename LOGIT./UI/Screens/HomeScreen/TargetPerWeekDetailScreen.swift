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
        
    // MARK: - State

    @State private var isShowingChangeGoalScreen = false
    @State private var selectedWeeksFromNow = 0
    
    // MARK: - Body
    
    var body: some View {
        FetchRequestWrapper(
            Workout.self,
            sortDescriptors: [SortDescriptor(\.date, order: .reverse)],
            predicate: WorkoutPredicateFactory.getWorkouts(
                from: Calendar.current.date(
                    byAdding: .weekOfYear,
                    value: -selectedWeeksFromNow,
                    to: .now
                )?.startOfWeek,
                to: Calendar.current.date(
                    byAdding: .weekOfYear,
                    value: -selectedWeeksFromNow,
                    to: .now
                )?.endOfWeek
            )
        ) { workouts in
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
                                FetchRequestWrapper(
                                    Workout.self,
                                    sortDescriptors: [SortDescriptor(\.date, order: .reverse)],
                                    predicate: WorkoutPredicateFactory.getWorkouts(
                                        from: Calendar.current.date(
                                            byAdding: .weekOfYear,
                                            value: -weeksFromNow,
                                            to: .now
                                        )?.startOfWeek,
                                        to: Calendar.current.date(
                                            byAdding: .weekOfYear,
                                            value: -weeksFromNow,
                                            to: .now
                                        )?.endOfWeek
                                    )
                                ) { workouts in
                                    Chart {
                                        ForEach(0..<targetPerWeek, id:\.self) { value in
                                            SectorMark(
                                                angle: .value("Value", 1),
                                                innerRadius: .ratio(0.65),
                                                angularInset: 1
                                            )
                                            .foregroundStyle(value < workouts.count ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.fill))
                                        }
                                    }
                                    .overlay {
                                        if workouts.count >= targetPerWeek {
                                            Image(systemName: "checkmark")
                                                .font(.title)
                                                .fontWeight(.bold)
                                                .foregroundStyle(Color.accentColor.gradient)
                                        } else {
                                            VStack(spacing: 0) {
                                                Text("\(targetPerWeek - workouts.count)")
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
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .frame(height: 250)
                        
                        HStack(alignment: .firstTextBaseline) {
                            Spacer()
                            VStack {
                                let numberOfWorkoutsInCurrentWeek = workouts.count
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
                        ForEach(workouts) { workout in
                            WorkoutCell(workout: workout)
                                .padding(CELL_PADDING)
                                .secondaryTileStyle()
                        }
                        .emptyPlaceholder(workouts) {
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
